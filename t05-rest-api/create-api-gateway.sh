#!/usr/bin/env bash
# Put an Amazon API Gateway HTTP API in front of the PlaceFinder service.
# All paths are passed through; the stage limits the request rate so that
# you can watch "429 Too Many Requests".
# Usage: ./create-api-gateway.sh
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/provider.sh"

LAB=t05
RATE=10     # requests per second for all clients together
BURST=20    # short peaks up to this number of requests
check_login
load_state t03
[[ -n "${SERVICE_URL:-}" ]] || die "No service from t03. Run ./update-service.sh first."
load_state "$LAB"
[[ -z "${API_ID:-}" ]] || die "API $API_ID exists already. Delete it with ./destroy-api-gateway.sh."

log "Creating HTTP API $(name api) ..."
api_id=$(aws apigatewayv2 create-api --name "$(name api)" --protocol-type HTTP \
  --tags "course=$COURSE_TAG,lab=$LAB" --query ApiId --output text)
save_state "$LAB" API_ID "$api_id"

# HTTP proxy integration: /{proxy+} is forwarded to the same path at the backend
integration=$(aws apigatewayv2 create-integration --api-id "$api_id" \
  --integration-type HTTP_PROXY --integration-method ANY \
  --integration-uri "${SERVICE_URL%/}/{proxy}" \
  --payload-format-version 1.0 --query IntegrationId --output text)
aws apigatewayv2 create-route --api-id "$api_id" --route-key 'ANY /{proxy+}' \
  --target "integrations/$integration" >/dev/null

# Rate limit for every route of the stage (token bucket: RATE per second,
# bursts up to BURST)
# shellcheck disable=SC2016  # $default is the literal stage name
aws apigatewayv2 create-stage --api-id "$api_id" --stage-name '$default' --auto-deploy \
  --default-route-settings "ThrottlingRateLimit=$RATE,ThrottlingBurstLimit=$BURST" >/dev/null

endpoint=$(aws apigatewayv2 get-api --api-id "$api_id" --query ApiEndpoint --output text)
save_state "$LAB" API_URL "$endpoint"
wait_for_http "$endpoint/health" 120
cat <<INFO

API Gateway: $endpoint  ($RATE requests per second, bursts up to $BURST)
  Test:        ./smoke-test.sh --gateway
  Rate limit:  ./rate-limit-test.sh
  Delete:      ./destroy-api-gateway.sh
INFO
