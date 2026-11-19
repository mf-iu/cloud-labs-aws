#!/usr/bin/env bash

# Build the deployment package in 07-serverless/build/: the handler, the
# provider-neutral core geonames_sync.py from cloud-labs-local/09-serverless
# and the dependency pg8000. OpenTofu zips this folder (infra/main.tf).
#
# Usage: 07-serverless/package.sh

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

source "$(dirname "$0")/../lib/provider.sh"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

here="$REPO_ROOT/07-serverless"
core="$LOCAL_LABS/09-serverless/geonames_sync.py"
[[ -f "$core" ]] || die "Not found: $core. Update cloud-labs-local: git -C $LOCAL_LABS pull"
require python3

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

rm --recursive --force "$here/build"
mkdir "$here/build"
cp "$here"/function/*.py "$core" "$here/build/"

# Pure Python dependencies, installed for the Lambda runtime
# --target installs into build/ instead of the environment; --platform,
# --python-version and --only-binary fetch the packages built for the Lambda
# runtime, not for this computer
python3 -m pip install --quiet --target "$here/build" --no-compile \
    --platform manylinux2014_x86_64 --python-version 3.12 --only-binary=:all: \
    --requirement "$here/function/requirements.txt"
log "Package ready in $here/build"
