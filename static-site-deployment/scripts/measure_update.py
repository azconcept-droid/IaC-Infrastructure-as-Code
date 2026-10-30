#!/usr/bin/env python3
"""Measure how long CloudFront takes to serve new S3 content.

The script deploys uniquely identifiable builds of index.html to S3, optionally
creates a CloudFront invalidation, and polls the distribution with plain HTTP
requests. It records both:

  * when the edge starts serving the new build, and
  * when the CloudFront invalidation API reports "Completed".

The two are not the same. AWS reports that invalidation propagation is usually
faster than the status API reporting. Polling the status with the AWS CLI waiter
(20 second interval) hides this difference, so this script polls every second by
default.

No third-party Python packages are required. The AWS CLI must be installed and
configured with credentials that can upload to the bucket and invalidate the
distribution.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import shutil
import statistics
import subprocess
import sys
import threading
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from urllib import error as urlerror
from urllib import request as urlrequest

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_TEMPLATE = REPO_ROOT / "site" / "index.template.html"
DEFAULT_SITE_DIR = REPO_ROOT / "site"
BUILD_ID_RE = re.compile(r'name="build-id"\s+content="([^"]+)"')

EVENT_FIELDS = [
    "run",
    "event",
    "utc",
    "elapsed_s",
    "http_status",
    "served_build_id",
    "is_expected",
    "x_cache",
    "age_s",
    "pop",
    "date",
    "etag",
    "last_modified",
    "latency_s",
    "invalidation_id",
    "invalidation_status",
    "note",
]

RUN_FIELDS = [
    "run",
    "label",
    "build_id",
    "cache_control",
    "invalidate",
    "upload_seconds",
    "pre_invalidation_was_stale",
    "pre_invalidation_status",
    "pre_invalidation_served_build_id",
    "pre_invalidation_x_cache",
    "pre_invalidation_age_s",
    "updated",
    "first_new_after_upload_s",
    "age_at_first_new_s",
    "first_new_x_cache",
    "first_new_pop",
    "invalidation_id",
    "invalidation_create_s",
    "invalidation_complete_s",
    "first_new_after_invalidation_s",
    "first_new_after_invalidation_complete_s",
    "first_new_before_invalidation",
    "first_new_before_invalidation_complete",
    "invalidation_completed",
    "invalidation_status",
    "probe_count",
    "max_age_seen_s",
    "stale_probes_after_first_new",
    "settle_seconds",
    "timeout_s",
]


def utc_now_iso() -> str:
    return (
        datetime.now(timezone.utc)
        .isoformat(timespec="milliseconds")
        .replace("+00:00", "Z")
    )


def make_build_id(prefix: str) -> str:
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
    return f"{prefix}-{timestamp}-{uuid.uuid4().hex[:8]}"


def run_aws(args: list[str], region: str) -> str:
    cmd = ["aws", *args, "--region", region]
    env = os.environ.copy()
    env["AWS_PAGER"] = ""
    proc = subprocess.run(cmd, capture_output=True, text=True, env=env)
    if proc.returncode != 0:
        raise RuntimeError(
            f"AWS CLI failed ({proc.returncode}): {' '.join(cmd)}\n{proc.stderr.strip()}"
        )
    return proc.stdout


def upload_file(
    bucket: str,
    local_path: Path,
    key: str,
    content_type: str,
    cache_control: str | None,
    region: str,
) -> None:
    cmd = [
        "s3",
        "cp",
        str(local_path),
        f"s3://{bucket}/{key}",
        "--content-type",
        content_type,
    ]
    if cache_control:
        cmd += ["--cache-control", cache_control]
    run_aws(cmd, region)


def upload_index(
    bucket: str, build_path: Path, cache_control: str | None, region: str
) -> None:
    upload_file(
        bucket=bucket,
        local_path=build_path,
        key="index.html",
        content_type="text/html; charset=utf-8",
        cache_control=cache_control,
        region=region,
    )


def upload_assets(args: argparse.Namespace) -> None:
    assets = [
        ("styles.css", "text/css; charset=utf-8"),
        ("app.js", "application/javascript; charset=utf-8"),
    ]
    for filename, content_type in assets:
        path = args.site_dir / filename
        if not path.is_file():
            continue
        upload_file(
            bucket=args.bucket,
            local_path=path,
            key=filename,
            content_type=content_type,
            cache_control="public, max-age=31536000, immutable",
            region=args.region,
        )


def create_invalidation(distribution_id: str, paths: list[str], region: str) -> str:
    cmd = [
        "cloudfront",
        "create-invalidation",
        "--distribution-id",
        distribution_id,
        "--paths",
        *paths,
    ]
    raw = run_aws(cmd, region)
    return json.loads(raw)["Invalidation"]["Id"]


def get_invalidation(
    distribution_id: str, invalidation_id: str, region: str
) -> dict:
    cmd = [
        "cloudfront",
        "get-invalidation",
        "--distribution-id",
        distribution_id,
        "--id",
        invalidation_id,
    ]
    raw = run_aws(cmd, region)
    return json.loads(raw)["Invalidation"]


def parse_age(headers: dict[str, str]) -> int | None:
    value = headers.get("age")
    try:
        return int(value)  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return None


def request_url(args: argparse.Namespace) -> str:
    url = f"{args.domain}{args.request_path}"
    if not args.no_cache_buster:
        separator = "&" if "?" in url else "?"
        url = f"{url}{separator}probe={uuid.uuid4().hex}"
    return url


def probe_once(url: str, expected_build_id: str, timeout: float) -> dict:
    started = time.monotonic()
    headers = {
        "Accept-Encoding": "identity",
        "User-Agent": "cloudfront-update-probe/1.0",
    }
    req = urlrequest.Request(url, headers=headers)

    try:
        with urlrequest.urlopen(req, timeout=timeout) as response:
            body = response.read()
            status = getattr(response, "status", response.getcode())
            response_headers = {
                key.lower(): value for key, value in response.headers.items()
            }
    except urlerror.HTTPError as exc:
        body = exc.read() or b""
        status = exc.code
        response_headers = {
            key.lower(): value for key, value in (exc.headers or {}).items()
        }
    except Exception as exc:  # noqa: BLE001 - probe errors are data, not failures
        return {
            "status": None,
            "served_build_id": None,
            "is_expected": False,
            "x_cache": None,
            "age_s": None,
            "pop": None,
            "date": None,
            "etag": None,
            "last_modified": None,
            "latency_s": round(time.monotonic() - started, 3),
            "error": f"{type(exc).__name__}: {exc}",
        }

    text = body.decode("utf-8", errors="replace")
    match = BUILD_ID_RE.search(text)
    served = match.group(1) if match else None
    if served is None and expected_build_id in text:
        served = expected_build_id

    return {
        "status": status,
        "served_build_id": served,
        "is_expected": served == expected_build_id,
        "x_cache": response_headers.get("x-cache"),
        "age_s": parse_age(response_headers),
        "pop": response_headers.get("x-amz-cf-pop"),
        "date": response_headers.get("date"),
        "etag": response_headers.get("etag"),
        "last_modified": response_headers.get("last-modified"),
        "latency_s": round(time.monotonic() - started, 3),
        "error": None,
    }


def probe_fields(probe: dict) -> dict:
    return {
        "http_status": probe.get("status"),
        "served_build_id": probe.get("served_build_id"),
        "is_expected": probe.get("is_expected"),
        "x_cache": probe.get("x_cache"),
        "age_s": probe.get("age_s"),
        "pop": probe.get("pop"),
        "date": probe.get("date"),
        "etag": probe.get("etag"),
        "last_modified": probe.get("last_modified"),
        "latency_s": probe.get("latency_s"),
    }


def write_build(
    output_dir: Path, run_tag: str, template_text: str, build_id: str
) -> Path:
    build_dir = output_dir / "builds" / run_tag
    build_dir.mkdir(parents=True, exist_ok=True)
    path = build_dir / "index.html"
    path.write_text(template_text.replace("__BUILD_ID__", build_id), encoding="utf-8")
    return path


def invalidation_worker(
    args: argparse.Namespace,
    run_idx: int,
    run_start: float,
    invalidation_id: str,
    inv_state: dict,
    stop_event: threading.Event,
    add_event,
) -> None:
    while not stop_event.is_set():
        call_start = time.monotonic()
        try:
            invalidation = get_invalidation(
                args.distribution_id, invalidation_id, args.region
            )
            status = invalidation.get("Status")
            now_abs = time.monotonic()
            inv_state["status"] = status
            add_event(
                run=run_idx,
                event="invalidation_status",
                utc=utc_now_iso(),
                elapsed_s=round(now_abs - run_start, 3),
                invalidation_id=invalidation_id,
                invalidation_status=status,
            )
            if status == "Completed":
                inv_state["completed"] = True
                inv_state["completed_abs"] = now_abs
                return
        except Exception as exc:  # noqa: BLE001 - keep polling and record the error
            add_event(
                run=run_idx,
                event="invalidation_status_error",
                utc=utc_now_iso(),
                elapsed_s=round(time.monotonic() - run_start, 3),
                invalidation_id=invalidation_id,
                note=str(exc),
            )

        call_elapsed = time.monotonic() - call_start
        wait_for = max(0.0, args.invalidation_poll_interval - call_elapsed)
        if stop_event.wait(wait_for):
            return


def reset_cache(args: argparse.Namespace, add_event) -> str:
    reset_start = time.monotonic()
    invalidation_id = create_invalidation(args.distribution_id, ["/*"], args.region)
    add_event(
        run=-1,
        event="reset_invalidation_created",
        utc=utc_now_iso(),
        elapsed_s=round(time.monotonic() - reset_start, 3),
        invalidation_id=invalidation_id,
        note="paths=/*",
    )

    deadline = reset_start + args.reset_timeout
    while time.monotonic() < deadline:
        invalidation = get_invalidation(
            args.distribution_id, invalidation_id, args.region
        )
        status = invalidation.get("Status")
        add_event(
            run=-1,
            event="reset_invalidation_status",
            utc=utc_now_iso(),
            elapsed_s=round(time.monotonic() - reset_start, 3),
            invalidation_id=invalidation_id,
            invalidation_status=status,
        )
        if status == "Completed":
            return invalidation_id
        time.sleep(args.invalidation_poll_interval)

    raise RuntimeError(
        f"Reset invalidation {invalidation_id} did not complete within "
        f"{args.reset_timeout}s"
    )


def warmup(args: argparse.Namespace, template_text: str, output_dir: Path, add_event) -> None:
    build_id = make_build_id("warmup")
    build_path = write_build(output_dir, f"warmup-{build_id}", template_text, build_id)
    warmup_start = time.monotonic()

    add_event(
        run=-1,
        event="warmup_upload_start",
        utc=utc_now_iso(),
        elapsed_s=0.0,
        note=f"build_id={build_id}",
    )
    upload_index(args.bucket, build_path, args.cache_control, args.region)
    add_event(
        run=-1,
        event="warmup_upload_end",
        utc=utc_now_iso(),
        elapsed_s=round(time.monotonic() - warmup_start, 3),
        note=f"build_id={build_id}",
    )

    deadline = warmup_start + args.warmup_timeout
    while time.monotonic() < deadline:
        probe = probe_once(request_url(args), build_id, args.probe_timeout)
        note = "warmup"
        if probe.get("error"):
            note += f"; error={probe['error']}"
        add_event(
            run=-1,
            event="warmup_probe",
            utc=utc_now_iso(),
            elapsed_s=round(time.monotonic() - warmup_start, 3),
            note=note,
            **probe_fields(probe),
        )
        if probe["is_expected"]:
            return
        time.sleep(args.poll_interval)

    raise RuntimeError(
        "Warmup failed: CloudFront never served the warmup build. "
        "The edge may still hold an object with a long TTL. "
        "Re-run with --reset-cache."
    )


def measure_run(
    args: argparse.Namespace,
    run_idx: int,
    template_text: str,
    output_dir: Path,
    add_event,
) -> dict:
    build_id = make_build_id(f"run{run_idx}")
    run_tag = f"run-{run_idx:03d}-{build_id}"
    build_path = write_build(output_dir, run_tag, template_text, build_id)

    run_start = time.monotonic()
    add_event(
        run=run_idx,
        event="upload_start",
        utc=utc_now_iso(),
        elapsed_s=0.0,
        note=f"build_id={build_id}",
    )

    upload_start = time.monotonic()
    upload_index(args.bucket, build_path, args.cache_control, args.region)
    upload_end = time.monotonic()

    add_event(
        run=run_idx,
        event="upload_end",
        utc=utc_now_iso(),
        elapsed_s=round(upload_end - run_start, 3),
        note=f"upload_seconds={upload_end - upload_start:.3f}",
    )

    expected = build_id
    pre_probe = probe_once(request_url(args), expected, args.probe_timeout)
    pre_elapsed = time.monotonic() - run_start
    pre_note = "pre_invalidation"
    if pre_probe.get("error"):
        pre_note += f"; error={pre_probe['error']}"
    add_event(
        run=run_idx,
        event="probe",
        utc=utc_now_iso(),
        elapsed_s=round(pre_elapsed, 3),
        note=pre_note,
        **probe_fields(pre_probe),
    )

    first_new_abs = pre_elapsed if pre_probe["is_expected"] else None
    first_new_age = pre_probe["age_s"] if pre_probe["is_expected"] else None
    first_new_probe = pre_probe if pre_probe["is_expected"] else None

    invalidation_id = None
    invalidation_create_seconds = None
    invalidation_created_abs = None
    inv_state = {"completed": False, "completed_abs": None, "status": None}
    stop_event = threading.Event()
    invalidation_thread = None

    if not args.no_invalidate:
        invalidation_start = time.monotonic()
        invalidation_id = create_invalidation(
            args.distribution_id, args.invalidation_paths, args.region
        )
        invalidation_end = time.monotonic()
        invalidation_created_abs = invalidation_start
        invalidation_create_seconds = invalidation_end - invalidation_start

        add_event(
            run=run_idx,
            event="invalidation_created",
            utc=utc_now_iso(),
            elapsed_s=round(invalidation_end - run_start, 3),
            invalidation_id=invalidation_id,
            note=(
                f"create_seconds={invalidation_create_seconds:.3f}; "
                f"paths={','.join(args.invalidation_paths)}"
            ),
        )

        invalidation_thread = threading.Thread(
            target=invalidation_worker,
            args=(
                args,
                run_idx,
                run_start,
                invalidation_id,
                inv_state,
                stop_event,
                add_event,
            ),
            daemon=True,
        )
        invalidation_thread.start()

    probe_count = 1
    stale_after_first = 0
    max_age = pre_probe["age_s"] if pre_probe["age_s"] is not None else None
    next_probe = time.monotonic() + args.poll_interval

    while True:
        sleep_for = next_probe - time.monotonic()
        if sleep_for > 0:
            time.sleep(sleep_for)

        elapsed = time.monotonic() - run_start
        if elapsed > args.timeout:
            break

        probe = probe_once(request_url(args), expected, args.probe_timeout)
        elapsed = time.monotonic() - run_start
        probe_count += 1

        if probe.get("age_s") is not None:
            max_age = (
                probe["age_s"]
                if max_age is None
                else max(max_age, probe["age_s"])
            )

        note = "poll"
        if probe["is_expected"] and first_new_abs is None:
            first_new_abs = elapsed
            first_new_age = probe.get("age_s")
            first_new_probe = probe
        elif first_new_abs is not None and not probe["is_expected"]:
            stale_after_first += 1
            note = "poll; stale_after_new"

        if probe.get("error"):
            note += f"; error={probe['error']}"

        add_event(
            run=run_idx,
            event="probe",
            utc=utc_now_iso(),
            elapsed_s=round(elapsed, 3),
            note=note,
            **probe_fields(probe),
        )

        if first_new_abs is not None:
            invalidation_done = args.no_invalidate or inv_state["completed"]
            if invalidation_done and (elapsed - first_new_abs) >= args.settle_seconds:
                break

        next_probe += args.poll_interval

    stop_event.set()
    if invalidation_thread is not None:
        invalidation_thread.join(
            timeout=max(5.0, args.invalidation_poll_interval * 2)
        )

    if invalidation_id and not inv_state["completed"]:
        try:
            invalidation = get_invalidation(
                args.distribution_id, invalidation_id, args.region
            )
            status = invalidation.get("Status")
            if status == "Completed":
                completed_abs = time.monotonic()
                inv_state["completed"] = True
                inv_state["completed_abs"] = completed_abs
                inv_state["status"] = status
                add_event(
                    run=run_idx,
                    event="invalidation_status",
                    utc=utc_now_iso(),
                    elapsed_s=round(completed_abs - run_start, 3),
                    invalidation_id=invalidation_id,
                    invalidation_status=status,
                    note="final_check",
                )
            else:
                inv_state["status"] = status
        except Exception as exc:  # noqa: BLE001 - record final-check errors
            add_event(
                run=run_idx,
                event="invalidation_status_error",
                utc=utc_now_iso(),
                elapsed_s=round(time.monotonic() - run_start, 3),
                invalidation_id=invalidation_id,
                note=f"final_check; error={exc}",
            )

    upload_end_elapsed = upload_end - run_start
    invalidation_created_elapsed = (
        invalidation_created_abs - run_start
        if invalidation_created_abs is not None
        else None
    )
    invalidation_completed_elapsed = (
        inv_state["completed_abs"] - run_start
        if inv_state["completed_abs"] is not None
        else None
    )

    metrics = {
        "run": run_idx,
        "label": args.label,
        "build_id": build_id,
        "cache_control": args.cache_control,
        "invalidate": not args.no_invalidate,
        "upload_seconds": round(upload_end - upload_start, 3),
        "pre_invalidation_was_stale": not pre_probe["is_expected"],
        "pre_invalidation_status": pre_probe.get("status"),
        "pre_invalidation_served_build_id": pre_probe.get("served_build_id"),
        "pre_invalidation_x_cache": pre_probe.get("x_cache"),
        "pre_invalidation_age_s": pre_probe.get("age_s"),
        "updated": first_new_abs is not None,
        "first_new_after_upload_s": (
            round(first_new_abs - upload_end_elapsed, 3)
            if first_new_abs is not None
            else None
        ),
        "age_at_first_new_s": first_new_age,
        "first_new_x_cache": (
            first_new_probe.get("x_cache") if first_new_probe else None
        ),
        "first_new_pop": first_new_probe.get("pop") if first_new_probe else None,
        "invalidation_id": invalidation_id,
        "invalidation_create_s": (
            round(invalidation_create_seconds, 3)
            if invalidation_create_seconds is not None
            else None
        ),
        "invalidation_complete_s": (
            round(invalidation_completed_elapsed - invalidation_created_elapsed, 3)
            if (
                invalidation_completed_elapsed is not None
                and invalidation_created_elapsed is not None
            )
            else None
        ),
        "first_new_after_invalidation_s": (
            round(first_new_abs - invalidation_created_elapsed, 3)
            if (
                first_new_abs is not None
                and invalidation_created_elapsed is not None
            )
            else None
        ),
        "first_new_after_invalidation_complete_s": (
            round(first_new_abs - invalidation_completed_elapsed, 3)
            if (
                first_new_abs is not None
                and invalidation_completed_elapsed is not None
            )
            else None
        ),
        "first_new_before_invalidation": (
            first_new_abs < invalidation_created_elapsed
            if (
                first_new_abs is not None
                and invalidation_created_elapsed is not None
            )
            else None
        ),
        "first_new_before_invalidation_complete": (
            first_new_abs < invalidation_completed_elapsed
            if (
                first_new_abs is not None
                and invalidation_completed_elapsed is not None
            )
            else None
        ),
        "invalidation_completed": inv_state["completed"],
        "invalidation_status": inv_state["status"],
        "probe_count": probe_count,
        "max_age_seen_s": max_age,
        "stale_probes_after_first_new": stale_after_first,
        "settle_seconds": args.settle_seconds,
        "timeout_s": args.timeout,
    }

    add_event(
        run=run_idx,
        event="run_complete",
        utc=utc_now_iso(),
        elapsed_s=round(time.monotonic() - run_start, 3),
        note=(
            f"updated={metrics['updated']}; "
            f"first_new_after_upload_s={metrics['first_new_after_upload_s']}; "
            f"invalidation_complete_s={metrics['invalidation_complete_s']}"
        ),
    )

    return metrics


def summarize(runs: list[dict]) -> dict:
    metric_keys = [
        "upload_seconds",
        "first_new_after_upload_s",
        "age_at_first_new_s",
        "invalidation_create_s",
        "invalidation_complete_s",
        "first_new_after_invalidation_s",
        "first_new_after_invalidation_complete_s",
    ]

    summary: dict = {
        "total_runs": len(runs),
        "updated_runs": sum(1 for run in runs if run.get("updated")),
        "runs_with_stale_pre_invalidation_probe": sum(
            1 for run in runs if run.get("pre_invalidation_was_stale")
        ),
        "runs_first_new_before_invalidation_complete": sum(
            1 for run in runs if run.get("first_new_before_invalidation_complete")
        ),
    }

    for key in metric_keys:
        values = [
            run[key] for run in runs if run.get(key) is not None  # type: ignore[list-item]
        ]
        if not values:
            continue
        summary[key] = {
            "count": len(values),
            "min": round(min(values), 3),
            "median": round(statistics.median(values), 3),
            "max": round(max(values), 3),
            "mean": round(statistics.mean(values), 3),
        }

    return summary


def config_dict(args: argparse.Namespace, started_utc: str) -> dict:
    return {
        "started_utc": started_utc,
        "label": args.label,
        "bucket": args.bucket,
        "distribution_id": args.distribution_id,
        "domain": args.domain,
        "region": args.region,
        "runs": args.runs,
        "cache_control": args.cache_control,
        "invalidate": not args.no_invalidate,
        "invalidation_paths": args.invalidation_paths,
        "request_path": args.request_path,
        "poll_interval_s": args.poll_interval,
        "invalidation_poll_interval_s": args.invalidation_poll_interval,
        "probe_timeout_s": args.probe_timeout,
        "timeout_s": args.timeout,
        "settle_seconds": args.settle_seconds,
        "warmup_timeout_s": args.warmup_timeout,
        "reset_cache": args.reset_cache,
        "reset_timeout_s": args.reset_timeout,
        "template": str(args.template),
        "site_dir": str(args.site_dir),
        "cache_buster_query": not args.no_cache_buster,
    }


def write_outputs(
    output_dir: Path,
    events: list[dict],
    runs: list[dict],
    args: argparse.Namespace,
    started_utc: str,
) -> dict:
    with (output_dir / "events.csv").open(
        "w", newline="", encoding="utf-8"
    ) as handle:
        writer = csv.DictWriter(
            handle, fieldnames=EVENT_FIELDS, extrasaction="ignore"
        )
        writer.writeheader()
        for event in events:
            writer.writerow(event)

    summary = {
        "started_utc": started_utc,
        "config": config_dict(args, started_utc),
        "runs": runs,
        "summary": summarize(runs),
    }
    (output_dir / "summary.json").write_text(
        json.dumps(summary, indent=2), encoding="utf-8"
    )

    if runs:
        with (output_dir / "summary.csv").open(
            "w", newline="", encoding="utf-8"
        ) as handle:
            writer = csv.DictWriter(
                handle, fieldnames=RUN_FIELDS, extrasaction="ignore"
            )
            writer.writeheader()
            for run in runs:
                writer.writerow(run)

    return summary


def print_summary(summary: dict, output_dir: Path) -> None:
    aggregate = summary["summary"]
    print(f"\nResults written to {output_dir}")
    print("=== Measurement summary ===")
    print(
        f"Runs updated: {aggregate['updated_runs']}/"
        f"{aggregate['total_runs']}"
    )

    for key in (
        "first_new_after_upload_s",
        "age_at_first_new_s",
        "first_new_after_invalidation_s",
        "first_new_after_invalidation_complete_s",
        "invalidation_create_s",
        "invalidation_complete_s",
    ):
        stats = aggregate.get(key)
        if not stats:
            continue
        print(
            f"{key}: min={stats['min']}s median={stats['median']}s "
            f"max={stats['max']}s (n={stats['count']})"
        )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--bucket", required=True, help="S3 bucket name")
    parser.add_argument(
        "--distribution-id", required=True, help="CloudFront distribution ID"
    )
    parser.add_argument(
        "--domain",
        required=True,
        help="CloudFront domain, with or without https://",
    )
    parser.add_argument(
        "--region",
        default=os.environ.get("AWS_REGION", "eu-west-1"),
        help="AWS region for S3 and CloudFront API calls",
    )
    parser.add_argument("--runs", type=int, default=1, help="Measured runs")
    parser.add_argument(
        "--cache-control",
        default=None,
        help=(
            "Cache-Control value for index.html. Omit for no header (uses "
            "the distribution default_ttl)."
        ),
    )
    parser.add_argument(
        "--no-invalidate",
        action="store_true",
        help="Do not create an invalidation (used for TTL experiments)",
    )
    parser.add_argument(
        "--invalidation-path",
        action="append",
        dest="invalidation_paths",
        help="Invalidation path; may be repeated. Defaults to /*",
    )
    parser.add_argument(
        "--request-path",
        default="/",
        help="Path to request from CloudFront. Defaults to /",
    )
    parser.add_argument(
        "--poll-interval",
        type=float,
        default=1.0,
        help="Seconds between content probes",
    )
    parser.add_argument(
        "--invalidation-poll-interval",
        type=float,
        default=1.0,
        help="Seconds between GetInvalidation calls",
    )
    parser.add_argument(
        "--probe-timeout",
        type=float,
        default=15.0,
        help="HTTP timeout for a single content probe",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=300.0,
        help="Maximum seconds to wait for a run to update",
    )
    parser.add_argument(
        "--settle-seconds",
        type=float,
        default=5.0,
        help="Extra seconds to keep probing after the new build is seen",
    )
    parser.add_argument(
        "--warmup-timeout",
        type=float,
        default=120.0,
        help="Maximum seconds to wait for the warmup build",
    )
    parser.add_argument(
        "--reset-cache",
        action="store_true",
        help="Invalidate /* and wait before warmup to isolate each scenario",
    )
    parser.add_argument(
        "--reset-timeout",
        type=float,
        default=120.0,
        help="Maximum seconds to wait for the reset invalidation",
    )
    parser.add_argument(
        "--no-cache-buster",
        action="store_true",
        help=(
            "Do not append a unique query string. Keep this off only if the "
            "distribution caches on query strings."
        ),
    )
    parser.add_argument(
        "--label", default="", help="Scenario label used in output files"
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("results"),
        help="Directory for config.json, events.csv, summary.json, and build files",
    )
    parser.add_argument(
        "--template",
        type=Path,
        default=DEFAULT_TEMPLATE,
        help="HTML template containing __BUILD_ID__",
    )
    parser.add_argument(
        "--site-dir",
        type=Path,
        default=DEFAULT_SITE_DIR,
        help="Directory containing styles.css and app.js",
    )

    args = parser.parse_args()

    if args.invalidation_paths is None:
        args.invalidation_paths = ["/*"]
    if args.runs < 1:
        parser.error("--runs must be at least 1")
    if args.poll_interval <= 0:
        parser.error("--poll-interval must be greater than 0")
    if args.invalidation_poll_interval <= 0:
        parser.error("--invalidation-poll-interval must be greater than 0")
    if args.timeout <= 0:
        parser.error("--timeout must be greater than 0")

    if not args.domain.startswith(("http://", "https://")):
        args.domain = f"https://{args.domain}"
    args.domain = args.domain.rstrip("/")

    if not args.request_path.startswith("/"):
        args.request_path = f"/{args.request_path}"

    return args


def main() -> None:
    args = parse_args()
    started_utc = utc_now_iso()

    if shutil.which("aws") is None:
        raise SystemExit("aws CLI not found in PATH")
    if not args.template.is_file():
        raise SystemExit(f"Template not found: {args.template}")
    if not args.site_dir.is_dir():
        print(
            f"warning: site directory not found, skipping asset upload: "
            f"{args.site_dir}",
            file=sys.stderr,
        )

    output_dir = args.output_dir
    output_dir.mkdir(parents=True, exist_ok=True)
    template_text = args.template.read_text(encoding="utf-8")

    events: list[dict] = []
    lock = threading.Lock()

    def add_event(**fields) -> None:
        fields.setdefault("utc", utc_now_iso())
        with lock:
            events.append(fields)

    (output_dir / "config.json").write_text(
        json.dumps(config_dict(args, started_utc), indent=2), encoding="utf-8"
    )

    runs: list[dict] = []
    exit_code = 0

    try:
        if args.reset_cache:
            print("Resetting CloudFront cache before warmup...")
            reset_cache(args, add_event)

        if args.site_dir.is_dir():
            upload_assets(args)
            print("Uploaded static assets.")

        print("Warming CloudFront cache...")
        warmup(args, template_text, output_dir, add_event)
        print("Warmup complete. Starting measured runs...")

        for run_idx in range(1, args.runs + 1):
            print(f"Run {run_idx}/{args.runs}...")
            runs.append(
                measure_run(
                    args, run_idx, template_text, output_dir, add_event
                )
            )
    except Exception as exc:  # noqa: BLE001 - always write partial results
        exit_code = 1
        print(f"error: {exc}", file=sys.stderr)
    finally:
        with lock:
            events_snapshot = list(events)
        summary = write_outputs(
            output_dir, events_snapshot, runs, args, started_utc
        )
        print_summary(summary, output_dir)

    raise SystemExit(exit_code)


if __name__ == "__main__":
    main()
