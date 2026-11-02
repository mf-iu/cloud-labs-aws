#!/usr/bin/env bash

# Delete the Express Mode service, its log group, the Elastic Container Registry
# (ECR) repository and the roles.
#
# Usage: ./destroy.sh

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

source "$(dirname "$0")/../lib/provider.sh"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

LAB=t03
check_login
load_state "$LAB"
confirm "Delete the PlaceFinder service, its ECR repository and the IAM roles?" || exit 0

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

if [[ -n "${SERVICE_ARN:-}" ]]; then
    log "Deleting service (removes load balancer, target groups and security groups) ..."
    aws ecs delete-express-gateway-service --service-arn "$SERVICE_ARN" >/dev/null
    # Ask every 30 seconds, up to 30 minutes, until the service is INACTIVE; if
    # describe fails, the service is gone
    for _ in $(seq 60); do
        status=$(aws ecs describe-express-gateway-service --service-arn "$SERVICE_ARN" \
            --query service.status.statusCode --output text 2>/dev/null || echo INACTIVE)
        [[ "$status" == "INACTIVE" ]] && break
        log "Service status: $status, waiting ..."
        sleep 30
    done
fi

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Log groups of Express Mode services remain after deletion
# The loop runs once for each log group name; --output text separates them by
# whitespace
for group in $(aws logs describe-log-groups --log-group-name-pattern "$(name placefinder)" \
        --query 'logGroups[].logGroupName' --output text); do
    log "Deleting log group $group"
    aws logs delete-log-group --log-group-name "$group"
done

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

repo_name=$(name placefinder)
if aws ecr describe-repositories --repository-names "$repo_name" >/dev/null 2>&1; then
    log "Deleting ECR repository $repo_name ..."
    # --force deletes the images in the repository as well
    aws ecr delete-repository --repository-name "$repo_name" --force >/dev/null
fi

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# The infrastructure role must outlive the service, so it goes last
for role in "$(name ecs-execution)" "$(name ecs-infrastructure)"; do
    if aws iam get-role --role-name "$role" >/dev/null 2>&1; then
        # A role can only be deleted after its policies are detached
        for policy in $(aws iam list-attached-role-policies --role-name "$role" \
                --query 'AttachedPolicies[].PolicyArn' --output text); do
            aws iam detach-role-policy --role-name "$role" --policy-arn "$policy"
        done
        aws iam delete-role --role-name "$role"
        log "Deleted role $role"
    fi
done
clear_state "$LAB"
log "Done."
