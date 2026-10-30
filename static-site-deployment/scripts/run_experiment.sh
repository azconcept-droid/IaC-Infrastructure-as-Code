#!/usr/bin/env bash
#
# Run the full cache-timing experiment against the deployed stack.
#
# Scenarios:
#   1. default TTL + CloudFront invalidation (the main question)
#   2. max-age=30, no invalidation (validates TTL expiry behavior)
#   3. no-cache, no invalidation (validates revalidation behavior)
#   4. default TTL, no invalidation (shows 24h stale behavior via short timeout)
#
# Environment overrides:
#   RUNS       Measured runs for the main scenario (default: 5)
#   OUT_ROOT   Result directory (default: results/<UTC timestamp>)
#   AWS_REGION AWS region (default: eu-west-1)

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

RUNS="${RUNS:-5}"
REGION="${AWS_REGION:-eu-west-1}"
OUT_ROOT="${OUT_ROOT:-results/$(date -u +%Y%m%dT%H%M%SZ)}"

mkdir -p "$OUT_ROOT"

BUCKET="$(terraform output -raw bucket_name)"
DISTRIBUTION_ID="$(terraform output -raw cloudfront_distribution_id)"
DOMAIN="$(terraform output -raw cloudfront_distribution_domain)"

echo "Bucket:        ${BUCKET}"
echo "Distribution:  ${DISTRIBUTION_ID}"
echo "Domain:        ${DOMAIN}"
echo "Results:       ${OUT_ROOT}"

COMMON=(
  --bucket "$BUCKET"
  --distribution-id "$DISTRIBUTION_ID"
  --domain "$DOMAIN"
  --region "$REGION"
)

run_measure() {
  python3 scripts/measure_update.py "${COMMON[@]}" "$@"
}

echo
echo "=== Scenario 1/4: default TTL + invalidation ==="
run_measure \
  --label "invalidation-default-ttl" \
  --runs "$RUNS" \
  --reset-cache \
  --poll-interval 1 \
  --invalidation-poll-interval 1 \
  --timeout 180 \
  --settle-seconds 5 \
  --output-dir "$OUT_ROOT/invalidation-default-ttl"

echo
echo "=== Scenario 2/4: max-age=30, no invalidation ==="
run_measure \
  --label "ttl-30s-no-invalidation" \
  --runs 3 \
  --reset-cache \
  --no-invalidate \
  --cache-control "public, max-age=30" \
  --poll-interval 1 \
  --timeout 120 \
  --settle-seconds 3 \
  --output-dir "$OUT_ROOT/ttl-30s-no-invalidation"

echo
echo "=== Scenario 3/4: no-cache, no invalidation ==="
run_measure \
  --label "no-cache-no-invalidation" \
  --runs 3 \
  --reset-cache \
  --no-invalidate \
  --cache-control "no-cache" \
  --poll-interval 1 \
  --timeout 60 \
  --settle-seconds 3 \
  --output-dir "$OUT_ROOT/no-cache-no-invalidation"

echo
echo "=== Scenario 4/4: default TTL, no invalidation (expected stale) ==="
run_measure \
  --label "default-ttl-no-invalidation" \
  --runs 1 \
  --reset-cache \
  --no-invalidate \
  --poll-interval 5 \
  --timeout 60 \
  --settle-seconds 0 \
  --output-dir "$OUT_ROOT/default-ttl-no-invalidation"

echo
echo "All scenarios finished."
echo "Open ${OUT_ROOT}/*/summary.json for the detailed results."
