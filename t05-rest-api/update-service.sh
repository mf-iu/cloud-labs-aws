#!/usr/bin/env bash
# Roll out a new PlaceFinder version on the Express Mode service from t03.
# Pushes $PLACEFINDER_IMAGE:<tag> into ECR first.
# Usage: ./update-service.sh [tag]   (default: t05)
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/provider.sh"

check_login
tag="${1:-t05}"
load_state t03
[[ -n "${SERVICE_ARN:-}" ]] || die "No service from t03. Run ../t03-container/deploy.sh first."

"$REPO_ROOT/t03-container/push-image.sh" "$PLACEFINDER_IMAGE:$tag"
load_state t03   # push-image.sh stored the new ECR image

log "Updating $SERVICE_ARN to $IMAGE (rolling deployment with canary) ..."
aws ecs update-express-gateway-service --service-arn "$SERVICE_ARN" \
  --primary-container "{\"image\": \"$IMAGE\", \"containerPort\": 8000}" >/dev/null
log "Deployment started. Test it with: ./smoke-test.sh $SERVICE_URL"
