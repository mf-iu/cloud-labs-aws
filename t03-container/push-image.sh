#!/usr/bin/env bash
# Push a PlaceFinder image into an Amazon ECR repository.
# Usage: ./push-image.sh [source image]   (default: $PLACEFINDER_IMAGE:t03)
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/provider.sh"

LAB=t03
require docker
check_login
source_image="${1:-$PLACEFINDER_IMAGE:t03}"
repo_name=$(name placefinder)
registry="$(account_id).dkr.ecr.$AWS_REGION.amazonaws.com"

if ! aws ecr describe-repositories --repository-names "$repo_name" >/dev/null 2>&1; then
  log "Creating ECR repository $repo_name ..."
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

log "Logging in to $registry ..."
aws ecr get-login-password | docker login --username AWS --password-stdin "$registry"

if ! docker image inspect "$source_image" >/dev/null 2>&1; then
  check_public_image "$source_image" \
    || die "Cannot pull $source_image without login: it does not exist or is private. Run ./build-image.sh --push and make the package public on GitHub."
  log "Pulling $source_image ..."
  docker pull --platform linux/amd64 "$source_image"
fi
tag="${source_image##*:}"
target="$registry/$repo_name:$tag"
docker tag "$source_image" "$target"
docker push "$target"
save_state "$LAB" IMAGE "$target"
log "Pushed $target"
