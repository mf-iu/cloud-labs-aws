#!/usr/bin/env bash

# Build the deployment package in build/: code plus dependencies.
# OpenTofu zips this directory (t09-serverless/infra).
#
# Usage: ./package.sh

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

set -o errexit -o nounset -o pipefail
# Work in the folder of this script
cd "$(dirname "$0")"
rm --recursive --force build
mkdir build
cp function/*.py build/

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Pure Python dependencies, installed for the Lambda runtime
# --target installs into build/ instead of the environment; --platform,
# --python-version and --only-binary fetch the packages built for the Lambda
# runtime, not for this computer
python3 -m pip install --quiet --target build --no-compile \
    --platform manylinux2014_x86_64 --python-version 3.12 --only-binary=:all: \
    --requirement function/requirements.txt
echo "Package ready in $(pwd)/build"
