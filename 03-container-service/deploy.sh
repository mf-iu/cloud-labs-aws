#!/usr/bin/env bash

# Run the image from push-image.sh with Amazon ECS Express Mode (Fargate).
# Express Mode creates an HTTPS load balancer, scaling and logs by itself.
#
# Usage: ./deploy.sh [image]   (default: image pushed by push-image.sh)

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

source "$(dirname "$0")/../lib/provider.sh"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

LAB=t03
check_login
load_state "$LAB"
# The image given as argument, otherwise the one that push-image.sh saved
# (IMAGE), otherwise empty
image="${1:-${IMAGE:-}}"
[[ -n "$image" ]] || die "No image. Run ./push-image.sh first or pass an image."
[[ -z "${SERVICE_ARN:-}" ]] || die "Service exists already: $SERVICE_ARN. Use ./update-service.sh or ./destroy.sh."

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

account=$(account_id)
exec_role=$(name ecs-execution)
infra_role=$(name ecs-infrastructure)

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# ensure_role <name> <service principal> <managed policy>
# Create an IAM role if it does not exist: $1 name, $2 the AWS service that may
# use it, $3 the managed policy it gets
ensure_role() {
    if ! aws iam get-role --role-name "$1" >/dev/null 2>&1; then
        log "Creating IAM role $1 ..."
        # $(aws_tags ...) without quotes on purpose: each tag becomes an
        # argument of its own. The trust policy is a JSON text in double quotes;
        # \" is a quote inside it.
        # shellcheck disable=SC2046
        aws iam create-role --role-name "$1" --tags $(aws_tags "$LAB") \
            --assume-role-policy-document "{
        \"Version\": \"2012-10-17\",
        \"Statement\": [{\"Effect\": \"Allow\", \"Principal\": {\"Service\": \"$2\"},
                        \"Action\": \"sts:AssumeRole\"}]}" >/dev/null
        aws iam attach-role-policy --role-name "$1" --policy-arn "arn:aws:iam::aws:policy/service-role/$3"
        sleep 15   # new roles need a moment until ECS can use them
    fi
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

ensure_role "$exec_role" ecs-tasks.amazonaws.com AmazonECSTaskExecutionRolePolicy
ensure_role "$infra_role" ecs.amazonaws.com AmazonECSInfrastructureRoleforExpressGatewayServices

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

service_name=$(name placefinder)
log "Creating Express Mode service $service_name with $image ..."
# The JSON values are in single quotes, or in double quotes with \" where a
# variable must be filled in
service_arn=$(aws ecs create-express-gateway-service \
    --service-name "$service_name" \
    --execution-role-arn "arn:aws:iam::$account:role/$exec_role" \
    --infrastructure-role-arn "arn:aws:iam::$account:role/$infra_role" \
    --primary-container "{\"image\": \"$image\", \"containerPort\": 8000}" \
    --cpu 256 --memory 512 \
    --health-check-path /health \
    --scaling-target '{"minTaskCount": 1, "maxTaskCount": 2}' \
    --tags "key=course,value=$COURSE_TAG" "key=lab,value=$LAB" \
    --query service.serviceArn --output text)
save_state "$LAB" SERVICE_ARN "$service_arn"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# The endpoint appears as soon as the first configuration is active
endpoint=None
# Ask up to 30 times, every 10 seconds, until the service has a public endpoint.
# The query filters the ingress paths by accessType; the result is the text None
# while there is none.
for _ in $(seq 30); do
    endpoint=$(aws ecs describe-express-gateway-service --service-arn "$service_arn" \
        --query "service.activeConfigurations[0].ingressPaths[?accessType=='PUBLIC'].endpoint | [0]" \
        --output text)
    [[ "$endpoint" != "None" && -n "$endpoint" ]] && break
    sleep 10
done
[[ "$endpoint" != "None" ]] || die "No endpoint yet. Check the service in the ECS console."
# Add https:// if the endpoint is a bare host name
[[ "$endpoint" == http* ]] || endpoint="https://$endpoint"
save_state "$LAB" SERVICE_URL "$endpoint"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

cat <<INFO

Service: $service_arn
URL:     $endpoint
The first deployment takes about five minutes (load balancer, certificate).
Status:  aws ecs describe-express-gateway-service --service-arn $service_arn --query service.status
INFO
wait_for_http "$endpoint/health" 900
