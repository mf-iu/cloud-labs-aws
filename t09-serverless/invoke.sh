#!/usr/bin/env bash
# Invoke the function manually and show the result.
# Usage: ./invoke.sh [YYYY-MM-DD]   (default: yesterday)
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/provider.sh"

check_login
function_name=$("$REPO_ROOT/tools/tofu.sh" "$REPO_ROOT/t09-serverless/infra" output -raw function_name)
payload='{}'
[[ -n "${1:-}" ]] && payload="{\"date\": \"$1\"}"
out=$(mktemp)
trap 'rm --force "$out"' EXIT
aws lambda invoke --function-name "$function_name" --cli-binary-format raw-in-base64-out \
  --payload "$payload" --log-type Tail --query LogResult --output text "$out" | base64 --decode | tail --lines 20
echo
cat "$out"
echo
