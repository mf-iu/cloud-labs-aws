#!/usr/bin/env bash
# Create the S3 bucket for the OpenTofu state (versioned, private) and
# write .state/backend.hcl, which tools/tofu.sh uses for all configurations.
# Usage: ./bootstrap-state.sh
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/provider.sh"

check_login
bucket="$(name "$(suffix)-tfstate")"
if aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
  log "State bucket s3://$bucket exists already."
else
  log "Creating state bucket s3://$bucket ..."
  if [[ "$AWS_REGION" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "$bucket" >/dev/null
  else
    aws s3api create-bucket --bucket "$bucket" \
      --create-bucket-configuration "LocationConstraint=$AWS_REGION" >/dev/null
  fi
  # Versioning keeps older states, e.g. after a failed apply
  aws s3api put-bucket-versioning --bucket "$bucket" --versioning-configuration Status=Enabled
  aws s3api put-bucket-tagging --bucket "$bucket" \
    --tagging "TagSet=[{Key=course,Value=$COURSE_TAG},{Key=lab,Value=t08}]"
fi

cat >"$STATE_DIR/backend.hcl" <<HCL
bucket       = "$bucket"
region       = "$AWS_REGION"
encrypt      = true
use_lockfile = true
HCL
log "Wrote $STATE_DIR/backend.hcl. Next: ../tools/tofu.sh infra plan"
