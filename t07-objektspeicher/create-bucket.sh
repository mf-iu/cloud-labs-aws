#!/usr/bin/env bash
# Create a private S3 bucket with CORS (for map tiles) and lifecycle rules.
# Usage: ./create-bucket.sh
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/provider.sh"

LAB=t07
check_login
load_state "$LAB"
[[ -z "${BUCKET:-}" ]] || die "Bucket $BUCKET exists already."
cd "$(dirname "$0")"

# Bucket names are global, hence the random suffix
bucket="$(name "$(suffix)-$LAB")"
log "Creating bucket s3://$bucket in $AWS_REGION ..."
if [[ "$AWS_REGION" == "us-east-1" ]]; then
  aws s3api create-bucket --bucket "$bucket" >/dev/null
else
  aws s3api create-bucket --bucket "$bucket" \
    --create-bucket-configuration "LocationConstraint=$AWS_REGION" >/dev/null
fi
save_state "$LAB" BUCKET "$bucket"

# New buckets block all public access and encrypt objects (SSE-S3) by default
aws s3api put-bucket-tagging --bucket "$bucket" \
  --tagging "TagSet=[{Key=course,Value=$COURSE_TAG},{Key=lab,Value=$LAB}]"
aws s3api put-bucket-cors --bucket "$bucket" --cors-configuration file://cors.json
aws s3api put-bucket-lifecycle-configuration --bucket "$bucket" \
  --lifecycle-configuration file://lifecycle.json

log "Uploading GeoNames cities15000 as raw data ..."
aws s3 cp "$(download_cities)" "s3://$bucket/raw/geonames/cities15000.txt"
aws s3 ls --recursive --human-readable "s3://$bucket"
log "Next: ./upload.sh <file> [key] and ./presign.sh <key>"
