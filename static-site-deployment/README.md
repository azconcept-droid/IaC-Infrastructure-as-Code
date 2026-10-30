# Static Site Deployment - CloudFront Cache Timing Test

This stack deploys a single static website to a private S3 bucket behind
CloudFront and includes a measurement harness for answering one question:

> After I upload a new version to S3 and invalidate CloudFront, how long does it
> actually take before the new version is served?

It measures the difference between:

1. **Edge behavior** - when a request to CloudFront starts returning the new file.
2. **Invalidation status** - when `GetInvalidation` reports `Completed`.
3. **Origin TTL behavior** - what happens with no invalidation at all.
4. **Browser cache behavior** - why a browser can still show the old page after
   CloudFront has updated (invalidation does not clear browser caches).

## TL;DR expectations

As of AWS's April 2026 announcement, CloudFront invalidation changes take effect
in under 5 seconds at P95, while end-to-end invalidation completion (including
status reporting) is under 25 seconds at P95. These are AWS-wide numbers, not a
guarantee for your account or your location, so this stack measures your actual
numbers.

The main trap: `aws cloudfront wait invalidation-completed` polls every **20
seconds**. If you time an invalidation with the AWS CLI waiter, the result looks
like "about 20 seconds" even when edge propagation took two seconds. The Python
harness polls invalidation status every second and polls the site itself every
second.

Other important expectations:

| Scenario | Expected update time |
|----------|----------------------|
| `index.html` with no `Cache-Control`, CloudFront invalidation | Usually seconds; AWS P95 effect < 5s, completion < 25s |
| `index.html` with `Cache-Control: max-age=30`, no invalidation | About 30 seconds, plus up to one poll interval |
| `index.html` with `Cache-Control: no-cache`, no invalidation | Next request (revalidates with S3) |
| `index.html` with no `Cache-Control`, no invalidation | Up to the cache policy `default_ttl` (24 hours by default) |
| Browser has cached HTML with `max-age=...` | Until the browser cache expires, regardless of invalidation |

The recommended production pattern is:

```text
index.html              Cache-Control: no-cache
/assets/app.<hash>.js   Cache-Control: public, max-age=31536000, immutable
/assets/app.<hash>.css  Cache-Control: public, max-age=31536000, immutable
```

That avoids invalidations for hashed assets and makes HTML revalidate on every
request. Invalidations remain useful for emergency fixes and for files that are
not content-hashed.

## Architecture

```text
Browser
   |
   v
CloudFront distribution (default certificate, index.html root object)
   |  OAC + SigV4
   v
Private S3 bucket (versioning enabled)
   |
   +-- index.html
   +-- styles.css
   +-- app.js

Shared root resources:
  - GitHub Actions OIDC provider (optional; reuse existing if present)
  - Shared GitHub deploy IAM role
  - Per-site IAM policy: S3 read/write + CloudFront invalidation
```

The CloudFront cache policy ignores headers, cookies, and query strings. The
measurement script appends `?probe=<random>` to requests so a local proxy never
serves a cached response. Because query strings are not part of the cache key,
this still exercises the CloudFront edge cache. Do not run the harness with
`--no-cache-buster` unless you have deliberately changed the cache policy to key
on query strings.

## Directory structure

```text
static-site-deployment/
├── main.tf                    # Root module: shared OIDC role, site + CloudFront
├── variables.tf               # Root variables
├── output.tf                  # Bucket / distribution / role outputs
├── versions.tf                # Terraform and AWS provider versions
├── terraform.tfvars.example   # Copy to terraform.tfvars and edit
├── cloudfront/                # Single-origin CloudFront + optional WAF
├── frontend-infra/
│   └── static-site/           # S3 bucket, bucket policy, IAM deploy policy
├── site/
│   ├── index.template.html    # Contains __BUILD_ID__
│   ├── styles.css
│   └── app.js
└── scripts/
    ├── deploy.sh              # Manual deploy helper
    ├── measure_update.py      # Measurement harness (stdlib + AWS CLI)
    └── run_experiment.sh      # Runs all measurement scenarios
```

## Prerequisites

- Terraform >= 1.5
- AWS CLI v2 configured with credentials that can create/update the stack
- Python 3.10+ (standard library only)
- An AWS account that can create S3 buckets, CloudFront distributions, IAM
  roles/policies, and (optionally) WAF Web ACLs

## Configure

```bash
cd static-site-deployment
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

- Set `aws_account_id`.
- Set `github_org` and `github_repo` if you will use GitHub Actions.
- Keep `enable_waf = false` for the cache-timing test. WAF adds cost/request
  noise and does not change cache invalidation timing.
- If the account already has a GitHub OIDC provider (for example, from
  `multifrontend-deployment`), set:
  ```hcl
  create_github_oidc_provider = false
  github_oidc_provider_arn    = "arn:aws:iam::<account-id>:oidc-provider/token.actions.githubusercontent.com"
  ```
  If this is the first stack to create the provider, set
  `create_github_oidc_provider = true`.

CloudFront-scoped WAF Web ACLs must be created in `eu-west-1`. If you enable WAF,
keep `aws_region = "eu-west-1"`.

## Deploy the infrastructure

```bash
terraform init
terraform plan
terraform apply
```

CloudFront distribution creation commonly takes 5-15 minutes. The S3 bucket and
bucket policy may be ready before the distribution finishes. Wait for
`terraform apply` to complete before running measurements.

## Run the full experiment

```bash
bash scripts/run_experiment.sh
```

Optional environment overrides:

```bash
RUNS=10 OUT_ROOT=results/my-run AWS_REGION=eu-west-1 bash scripts/run_experiment.sh
```

The script runs four scenarios:

1. **default TTL + invalidation** (`invalidation-default-ttl`)
   - Uploads `index.html` without a `Cache-Control` header.
   - Warms the cache.
   - Uploads a new build.
   - Creates `/*` invalidation.
   - Measures the first new response and the invalidation completion time.
2. **max-age=30, no invalidation** (`ttl-30s-no-invalidation`)
   - Validates that CloudFront respects a 30-second origin TTL.
3. **no-cache, no invalidation** (`no-cache-no-invalidation`)
   - Validates revalidation on the next request.
4. **default TTL, no invalidation** (`default-ttl-no-invalidation`)
   - Uses a 60-second timeout to demonstrate that the default 24-hour TTL does
     not update quickly.

Each scenario uses `--reset-cache` first. This creates a `/*` invalidation and
waits for completion before the warmup. It prevents a long-lived cache entry
from a previous scenario (created with different `Cache-Control` metadata) from
contaminating the next scenario.

## Run a single measurement

```bash
BUCKET="$(terraform output -raw bucket_name)"
DIST_ID="$(terraform output -raw cloudfront_distribution_id)"
DOMAIN="$(terraform output -raw cloudfront_distribution_domain)"

python3 scripts/measure_update.py \
  --bucket "$BUCKET" \
  --distribution-id "$DIST_ID" \
  --domain "$DOMAIN" \
  --region eu-west-1 \
  --label "one-off-invalidation" \
  --runs 5 \
  --reset-cache \
  --poll-interval 1 \
  --invalidation-poll-interval 1 \
  --timeout 180 \
  --settle-seconds 5 \
  --output-dir results/one-off-invalidation
```

Useful variants:

```bash
# No invalidation, 30 second origin TTL
python3 scripts/measure_update.py ... \
  --no-invalidate --cache-control "public, max-age=30" --runs 3

# No invalidation, immediate revalidation
python3 scripts/measure_update.py ... \
  --no-invalidate --cache-control "no-cache" --runs 3

# Do not reset the cache before warmup
python3 scripts/measure_update.py ...   # omit --reset-cache
```

Only omit `--reset-cache` if you know the current cached object already has the
`Cache-Control` metadata you want to test. Changing S3 object metadata does not
change an object that is already cached in CloudFront.

## What the results mean

Each scenario writes:

```text
results/<timestamp>/<scenario>/
├── config.json     # Exact command/configuration for the run
├── events.csv      # Timeline: uploads, probes, invalidation status polls
├── summary.json    # Per-run metrics and aggregate min/median/max
├── summary.csv     # One row per measured run
└── builds/         # The exact index.html uploaded for each run
```

Key fields in `summary.json`:

| Field | Meaning |
|-------|---------|
| `first_new_after_upload_s` | Seconds from S3 upload completion to the first response containing the new build |
| `first_new_after_invalidation_s` | Seconds from the start of the `CreateInvalidation` call to the first new response (can be negative if the pre-invalidation probe already saw the new build) |
| `first_new_after_invalidation_complete_s` | Seconds from the invalidation reporting `Completed` to the first new response; negative means the edge updated before the status API caught up |
| `invalidation_create_s` | Time for the `CreateInvalidation` API call |
| `invalidation_complete_s` | Time from the start of the `CreateInvalidation` call until `GetInvalidation` reports `Completed` |
| `age_at_first_new_s` | `Age` header of the first new response, useful for TTL experiments |
| `first_new_before_invalidation_complete` | `true` if the edge served the new build before the status API said `Completed` |
| `pre_invalidation_was_stale` | `true` if the probe immediately after upload still saw the old build (a valid invalidation test) |
| `pre_invalidation_x_cache` | `x-cache` of that pre-invalidation probe; `Hit from cloudfront` confirms the edge was serving a cached object |
| `pre_invalidation_age_s` | `Age` header of the pre-invalidation probe |
| `stale_probes_after_first_new` | Number of stale responses received after the first new one (should normally be 0 from one vantage point) |
| `x_cache`, `pop` | CloudFront cache status and edge POP that served the first new response |

`events.csv` contains the raw sequence. The `x-cache` values are especially
useful:

- `Miss from cloudfront` - edge fetched from S3.
- `Hit from cloudfront` - edge served from cache.
- `RefreshHit from cloudfront` - edge revalidated with S3.
- `Age` - how long the object has been in the edge cache.

## Important caveats

### One probe location is one edge POP

Repeated requests from this machine normally go to the same nearby CloudFront
POP. `first_new_after_upload_s` is therefore **POP-local**. The invalidation
`Completed` status is the global signal that all edge locations have processed
the invalidation. To measure multiple POPs, run `measure_update.py` from hosts in
different regions (for example, EC2 instances in `eu-west-1`, `eu-west-1`, and
`ap-southeast-1`) with the same bucket/distribution, or use a multi-region HTTP
probe service.

### Invalidation completion is not the same as edge update

The script records both. It is common for the new content to be served before
the invalidation status flips to `Completed`, because AWS reports completion
after the invalidation has been processed everywhere and the status is
propagated back.

### Browser cache is separate

CloudFront invalidation does not clear a browser cache, a service worker cache,
a corporate proxy, or a CDN in front of CloudFront. If `index.html` is served
with `Cache-Control: max-age=86400`, a returning browser can show the old page
for a day even after CloudFront is updated.

To observe this manually:

1. Open the CloudFront URL in Chrome.
2. Open DevTools -> Network, and leave "Disable cache" **off**.
3. Deploy a new build (or run `scripts/deploy.sh`).
4. Invalidate CloudFront and wait for completion.
5. Click "Check edge build" on the page. The edge can report the new build while
   a hard refresh is still needed for the browser to reload the HTML.
6. Toggle "Disable cache" or hard reload to bypass the browser cache.

For production, set `Cache-Control: no-cache` (or `max-age=0,
must-revalidate`) on HTML and use content-hashed asset filenames with long
`max-age` and `immutable`.

### Negative/error responses

If you request the site before anything is uploaded, CloudFront can cache an
error response briefly. The harness uploads the warmup build before measuring,
so this should not affect the results.

### The script uploads to the real bucket

`measure_update.py` overwrites `s3://<bucket>/index.html` and uploads
`styles.css` and `app.js` once per invocation. Do not point it at a bucket that
serves production traffic.

### WAF

If WAF is enabled, the probes are simple `GET` requests and should pass the
default rules. WAF adds a fixed monthly cost and can add request latency, but it
does not change how long a cache invalidation takes.

### State

This stack uses local Terraform state, like the existing
`multifrontend-deployment`. For production, move state to S3 + DynamoDB and
enable encryption/locking. Never commit local state or `.env` files.

## Manual deploy

```bash
bash scripts/deploy.sh
```

Override behavior:

```bash
CACHE_CONTROL="public, max-age=30" INVALIDATE=0 bash scripts/deploy.sh
BUILD_ID="release-2026-10-26" bash scripts/deploy.sh
```

Note that `scripts/deploy.sh` uses the AWS CLI waiter, which polls every 20
seconds. Use `scripts/measure_update.py` when the timing matters.

## GitHub Actions (optional)

The shared role can be assumed by the configured repository environments:

```yaml
name: Deploy static site

on:
  push:
    branches: [main]

permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: testing
    steps:
      - uses: actions/checkout@v4

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: eu-west-1

      - name: Upload build
        run: |
          aws s3 cp dist/index.html "s3://${{ secrets.BUCKET_NAME }}/index.html" \
            --content-type "text/html; charset=utf-8" \
            --cache-control "no-cache"
          aws s3 sync dist/assets/ "s3://${{ secrets.BUCKET_NAME }}/assets/" \
            --cache-control "public, max-age=31536000, immutable"

      - name: Invalidate HTML
        run: |
          aws cloudfront create-invalidation \
            --distribution-id "${{ secrets.DISTRIBUTION_ID }}" \
            --paths "/*"
```

Invalidate the URL path that viewers actually request. If viewers load `/`, an
invalidation for `/index.html` does not clear the cached `/` entry; use `/` or
`/*` in that case. The harness defaults to `/*`.

For the experiment, use the local Python harness rather than the CLI waiter so
the 20-second waiter polling interval does not distort the timing.

## Troubleshooting

### Warmup fails with "CloudFront never served the warmup build"

The edge still has an object with a long TTL from an earlier run. Re-run with
`--reset-cache`, or invalidate `/*` manually and wait for `Completed`.

### `403 Forbidden` from CloudFront

The bucket is empty or the object key is wrong. Upload `index.html` and ensure
the request path maps to it (`/` uses the `index.html` default root object).

### OIDC provider already exists

The GitHub OIDC provider is account-wide. If another stack already created it,
set:

```hcl
create_github_oidc_provider = false
github_oidc_provider_arn    = "arn:aws:iam::<account-id>:oidc-provider/token.actions.githubusercontent.com"
```

### WAF apply fails outside eu-west-1

CloudFront-scoped WAF Web ACLs must be created in `eu-west-1`. Either keep
`aws_region = "eu-west-1"` or disable WAF for the test.

### Invalidation limit

CloudFront has limits on concurrent wildcard invalidations. The harness runs
invalidations sequentially and waits for each to complete, so the default
experiment stays well within limits.

### Costs

S3 storage/requests and CloudFront data transfer are small for this test.
Invalidations: `/*` counts as one path per request; the first 1,000 paths per
month are free. WAF has a fixed monthly cost, which is why the test stack keeps
it off by default.

## Destroy

```bash
terraform destroy
```

`force_destroy = true` is set on the bucket, so Terraform deletes all object
versions when the bucket is destroyed.

TGxp9LSUpck7mveruuwWN1J8KW1wHfsQLlYBV5IU
701544683237

AWS_PROFILE=default terraform apply