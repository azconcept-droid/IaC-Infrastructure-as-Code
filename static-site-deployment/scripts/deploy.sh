#!/usr/bin/env bash
#
# Deploy the static site and optionally invalidate CloudFront.
#
# For manual checks. The measurement harness is scripts/measure_update.py.
#
# Environment overrides:
#   BUILD_ID       Build identifier (default: UTC timestamp)
#   CACHE_CONTROL  Cache-Control for index.html (default: no-cache)
#   INVALIDATE     Set to 0 to skip invalidation (default: 1)
#   AWS_REGION     AWS region (default: eu-west-1)

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

BUCKET="$(terraform output -raw bucket_name)"
DISTRIBUTION_ID="$(terraform output -raw cloudfront_distribution_id)"
REGION="${AWS_REGION:-eu-west-1}"
BUILD_ID="${BUILD_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
CACHE_CONTROL="${CACHE_CONTROL:-no-cache}"
BUILD_DIR=".build/${BUILD_ID}"

mkdir -p "$BUILD_DIR"
sed "s|__BUILD_ID__|${BUILD_ID}|g" site/index.template.html > "$BUILD_DIR/index.html"
cp site/styles.css "$BUILD_DIR/styles.css"
cp site/app.js "$BUILD_DIR/app.js"

echo "Uploading build ${BUILD_ID} to s3://${BUCKET}"

aws s3 cp "$BUILD_DIR/index.html" "s3://${BUCKET}/index.html" \
  --region "$REGION" \
  --content-type "text/html; charset=utf-8" \
  --cache-control "$CACHE_CONTROL"

aws s3 cp "$BUILD_DIR/styles.css" "s3://${BUCKET}/styles.css" \
  --region "$REGION" \
  --content-type "text/css; charset=utf-8" \
  --cache-control "public, max-age=31536000, immutable"

aws s3 cp "$BUILD_DIR/app.js" "s3://${BUCKET}/app.js" \
  --region "$REGION" \
  --content-type "application/javascript; charset=utf-8" \
  --cache-control "public, max-age=31536000, immutable"

if [[ "${INVALIDATE:-1}" == "1" ]]; then
  INVALIDATION_ID="$(aws cloudfront create-invalidation \
    --distribution-id "$DISTRIBUTION_ID" \
    --paths "/*" \
    --region "$REGION" \
    --query 'Invalidation.Id' \
    --output text)"

  echo "Invalidation ${INVALIDATION_ID} created"
  echo "Waiting for it to report Completed (the CLI waiter polls every 20s)..."

  aws cloudfront wait invalidation-completed \
    --distribution-id "$DISTRIBUTION_ID" \
    --id "$INVALIDATION_ID" \
    --region "$REGION"
else
  echo "Skipping invalidation because INVALIDATE=0"
fi

echo "Deployed build ${BUILD_ID}"
echo "CloudFront domain: $(terraform output -raw cloudfront_distribution_domain)"
