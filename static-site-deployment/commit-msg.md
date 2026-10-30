feat: Add CloudFront cache-timing measurement harness and S3+CloudFront static site stack

Summary
-------
Implements a complete single-site static deployment (S3 private bucket behind CloudFront with Origin Access Control) plus a deterministic measurement harness to quantify how fast CloudFront serves updated content under different caching/invalidation strategies.

Key Changes
-----------
Infrastructure (Terraform)
- Add root stack (main.tf/variables.tf/output.tf/versions.tf) wiring shared GitHub OIDC/IAM deploy role to site and CloudFront modules.
- Add CloudFront module with OAC, managed cache policy (configurable min/default/max TTLs), optional WAF (CloudFront-scoped, us-east-1), and default HTTPS viewer cert.
- Add frontend-infra/static-site module: private S3 bucket (versioning, ownership controls, public access block), bucket policy restricted to CloudFront via OAC, and least-privilege GitHub deploy IAM policy (S3 + CloudFront invalidation).
- Support reusing existing GitHub OIDC provider via variables; normalize GitHub environment subject claims.
- Enforce TTL ordering (min_ttl <= default_ttl <= max_ttl) and validate inputs.

Static Site
- Add simple test site (site/index.template.html, styles.css, app.js) with __BUILD_ID__ placeholder and "Check edge build" button that fetches with a probe query and displays x-cache/Age/x-amz-cf-pop.
- App uses fetch with query cache-buster for probing; build ID embedded in meta tag for detection.

Measurement & Automation
- Add scripts/measure_update.py (stdlib + AWS CLI): uploads uniquely-tagged builds, optionally creates/monitors CloudFront invalidations (polls GetInvalidation every second), probes CloudFront every second with no-cache headers and query cache-buster, detects new build via HTML meta tag, and records edge vs invalidation timing (first_new_after_upload_s, first_new_after_invalidation_s, invalidation_complete_s, x-cache/pop/Age, etc.).
- Add scripts/run_experiment.sh to run four scenarios: default TTL + invalidation, max-age=30s no invalidation, no-cache no invalidation, default TTL no invalidation (with reset-cache/warmup).
- Add scripts/deploy.sh for manual deploys with optional invalidation and configurable Cache-Control/BUILD_ID.
- Output detailed artifacts: config.json, events.csv, summary.json, summary.csv, and per-run builds/ in results/.

Documentation
- Add comprehensive README with architecture, TL;DR expectations (AWS 2026 invalidation numbers), caveats (POP-local vs global invalidation, browser cache separate), troubleshooting, and example GitHub Actions workflow.
- Add terraform.tfvars.example and .gitignore.

Notes
-----
- Cache policy ignores headers/cookies/query strings by design; probe uses query string cache-buster while still exercising edge cache.
- Invalidation timing measured separately from edge update (edge often updates before GetInvalidation reports Completed).
- Harness overwrites index.html on each run; use with non-production buckets.
