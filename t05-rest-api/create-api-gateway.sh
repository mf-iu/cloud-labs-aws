#!/usr/bin/env bash
# Put an Amazon API Gateway HTTP API in front of the PlaceFinder service.
# All paths are passed through; the stage limits the request rate so that
# you can watch "429 Too Many Requests".
# Usage: ./create-api-gateway.sh
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/provider.sh"

LAB=t05
check_login
load_state t03
[[ -n "${SERVICE_URL:-}" ]] || die "No service from t03. Run ../t03-container/deploy.sh first."
load_state "$LAB"
[[ -z "${API_ID:-}" ]] || die "API $API_ID exists already."

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

# Rate limit for all routes: 5 requests per second, bursts of 10
# shellcheck disable=SC2016  # $default is the literal stage name
aws apigatewayv2 create-stage --api-id "$api_id" --stage-name '$default' --auto-deploy \
  --default-route-settings ThrottlingRateLimit=5,ThrottlingBurstLimit=10 >/dev/null

endpoint=$(aws apigatewayv2 get-api --api-id "$api_id" --query ApiEndpoint --output text)
save_state "$LAB" API_URL "$endpoint"
cat <<INFO

API Gateway: $endpoint
  Test:        ./smoke-test.sh $endpoint
  Rate limit:  for i in \$(seq 30); do curl --silent --output /dev/null --write-out '%{http_code} ' $endpoint/health; done
  Delete:      ./destroy-api-gateway.sh
INFO
