#!/usr/bin/env bash

# Roll out a new PlaceFinder version on the Express Mode service from t03:
# copy $PLACEFINDER_IMAGE:<tag> into Elastic Container Registry (ECR), deploy it
# by digest, wait for the canary deployment and run the smoke test. Without a
# service from t03, it creates one with ./deploy.sh.
#
# Usage: ./update-service.sh [tag]   (default: t05)

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

source "$(dirname "$0")/../lib/provider.sh"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

require_github_user   # PLACEFINDER_IMAGE and PLACEFINDER_REPO need it

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

check_login
tag="${1:-t05}"
# Copy the image from ghcr.io into ECR; push-image.sh saves its address in IMAGE
"$REPO_ROOT/03-container-service/push-image.sh" "$PLACEFINDER_IMAGE:$tag"
load_state t03   # push-image.sh stored the ECR image

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# A tag can later point to another image; the digest names exactly this one
# ${IMAGE##*:} is the tag after the last colon, ${IMAGE%:*} the address without
# the tag
digest=$(aws ecr describe-images --repository-name "$(name placefinder)" \
    --image-ids "imageTag=${IMAGE##*:}" --query 'imageDetails[0].imageDigest' --output text)
image="${IMAGE%:*}@$digest"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

if [[ -z "${SERVICE_ARN:-}" ]]; then
    log "No service from t03; creating it with $image ..."
    "$REPO_ROOT/03-container-service/deploy.sh" "$image"
    load_state t03
else
    # newest service deployment: Amazon Resource Name (ARN) and status
    # A function defined inside the else branch; it exists from here on
    latest() {
        aws ecs list-service-deployments --cluster default --service "$SERVICE_ARN" \
            --query 'sort_by(serviceDeployments, &createdAt)[-1].[serviceDeploymentArn, status]' \
            --output text
    }
    # read splits the line at spaces: the ARN into previous, the status into _
    # (not needed); <(cmd) passes the output of cmd like a file
    read -r previous _ < <(latest)
    log "Updating $SERVICE_ARN to $image ..."
    aws ecs update-express-gateway-service --service-arn "$SERVICE_ARN" \
        --primary-container "{\"image\": \"$image\", \"containerPort\": 8000}" >/dev/null

    # Canary: 5 % of the traffic to the new tasks, 3 minutes bake time, then
    # 100 % and another 3 minutes before the old tasks stop. Alarms roll back
    # if more than 1 % of the answers are 4xx or 5xx errors.
    log "Waiting for the canary deployment (about 10 minutes) ..."
    start=$SECONDS
    # Repeat until break or die; case compares the status with the patterns (|
    # separates alternatives)
    while true; do
        read -r arn status < <(latest)
        # Still the deployment from before: the new one is not listed yet
        [[ "$arn" != "$previous" ]] || status="not started yet"
        case "$status" in
            SUCCESSFUL) break ;;
            STOPPED|ROLLBACK_SUCCESSFUL|ROLLBACK_FAILED)
                die "Deployment ended with $status. Details: aws ecs describe-service-deployments --service-deployment-arns $arn" ;;
        esac
        (( SECONDS - start < 1800 )) || die "Deployment not finished after 30 minutes. Check the service in the ECS console."
        log "... $status ($(( (SECONDS - start) / 60 )) min)"
        sleep 30
    done
    log "Deployment $status after $(( (SECONDS - start) / 60 )) min."
fi
# The smoke test wrapper next to this script
"$(dirname "$0")/smoke-test.sh" "$SERVICE_URL"
