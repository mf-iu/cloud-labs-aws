#!/usr/bin/env bash
# Upload a trained model (e.g. exported from MLflow) to the model location
# that the /estimate endpoint reads at start-up.
# Usage: ./upload-model.sh <model.joblib>
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/provider.sh"

check_login
model="${1:?Usage: $0 <model file>}"
uri=$("$REPO_ROOT/tools/tofu.sh" "$REPO_ROOT/t11-ml/infra" output -raw model_uri)
aws s3 cp "$model" "$uri"
log "Uploaded to $uri."

# The application loads the model at start-up. Stopped tasks are replaced
# by the service automatically, and the new tasks read the new model.
service=$(name t11-estimate)
for task in $(aws ecs list-tasks --cluster default --service-name "$service" \
    --query 'taskArns[]' --output text); do
  log "Restarting task ${task##*/} ..."
  aws ecs stop-task --cluster default --task "$task" --reason "new model" >/dev/null
done
