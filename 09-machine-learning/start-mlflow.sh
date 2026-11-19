#!/usr/bin/env bash

# Start the MLflow tracking server of cloud-labs-local with the artifacts in
# the bucket of base, under mlflow/. The metadata stay in SQLite on this
# computer, in .state/mlflow of this repository. Stop it with Ctrl+C.
#
# Usage: 09-machine-learning/start-mlflow.sh

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

source "$(dirname "$0")/../lib/provider.sh"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

check_login
bucket=$(base_output bucket)
mkdir --parents "$STATE_DIR/mlflow"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# A database of its own: the runs of the local server point to artifacts in
# cloud-labs-local/.state, those of this one to the bucket
export MLFLOW_BACKEND_STORE_URI="sqlite:///$STATE_DIR/mlflow/mlflow.db"
export MLFLOW_ARTIFACTS_DESTINATION="s3://$bucket/mlflow"
# The server writes to S3 with boto3. It reads the login of "aws login" from
# the profile in AWS_PROFILE (lib/provider.sh) and renews it itself; for that
# it needs the extra crt (AWS Common Runtime).
export MLFLOW_EXTRA_PACKAGES="boto3[crt]"
exec "$LOCAL_LABS/11-machine-learning/start-mlflow.sh"
