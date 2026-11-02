#!/usr/bin/env bash

# Push a PlaceFinder image into an Amazon Elastic Container Registry (ECR)
# repository.
#
# Usage: ./push-image.sh [source image]   (default: $PLACEFINDER_IMAGE:t03)

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

source "$(dirname "$0")/../lib/provider.sh"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

require_github_user   # PLACEFINDER_IMAGE and PLACEFINDER_REPO need it

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

LAB=t03
require docker
check_login
# The image given as argument, otherwise ghcr.io/<github-user>/placefinder:t03
source_image="${1:-$PLACEFINDER_IMAGE:t03}"
repo_name=$(name placefinder)
# The address of the private registry of the account in this region
registry="$(account_id).dkr.ecr.$AWS_REGION.amazonaws.com"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

if ! aws ecr describe-repositories --repository-names "$repo_name" >/dev/null 2>&1; then
    log "Creating ECR repository $repo_name ..."
    # $(aws_tags ...) without quotes on purpose: each tag becomes an argument of
    # its own. scanOnPush scans every image for vulnerabilities.
    # shellcheck disable=SC2046  # aws_tags returns several words on purpose
    aws ecr create-repository --repository-name "$repo_name" \
        --image-scanning-configuration scanOnPush=true \
        --tags $(aws_tags "$LAB") >/dev/null
    # Keep only the five newest images to stay within the free storage
    aws ecr put-lifecycle-policy --repository-name "$repo_name" --lifecycle-policy-text '{
    "rules": [{"rulePriority": 1, "description": "keep five images",
               "selection": {"tagStatus": "any", "countType": "imageCountMoreThan", "countNumber": 5},
               "action": {"type": "expire"}}]}' >/dev/null
fi

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

log "Logging in to $registry ..."
# The CLI prints a token valid for 12 hours; --password-stdin reads it from the
# pipe
aws ecr get-login-password | docker login --username AWS --password-stdin "$registry"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Pull the image only if it is not there already; --platform linux/amd64 because
# Fargate runs this architecture here
if ! docker image inspect "$source_image" >/dev/null 2>&1; then
    check_public_image "$source_image" \
        || die "Cannot pull $source_image without login: it does not exist or is private. Run ../../cloud-labs-local/02-container/publish-image.sh and make the package public on GitHub."
    log "Pulling $source_image ..."
    docker pull --platform linux/amd64 "$source_image"
fi
# ${x##*:} keeps the text after the last colon: the tag, e.g. t03
tag="${source_image##*:}"
target="$registry/$repo_name:$tag"
docker tag "$source_image" "$target"
docker push "$target"
save_state "$LAB" IMAGE "$target"
log "Pushed $target"
