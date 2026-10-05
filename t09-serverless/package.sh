#!/usr/bin/env bash
# Build the deployment package in build/: code plus dependencies.
# OpenTofu zips this directory (t09-serverless/infra).
# Usage: ./package.sh
set -euo pipefail
cd "$(dirname "$0")"
rm -rf build
mkdir build
cp function/*.py build/
# Pure Python dependencies, installed for the Lambda runtime
python3 -m pip install --quiet --target build --no-compile \
  --platform manylinux2014_x86_64 --python-version 3.12 --only-binary=:all: \
  -r function/requirements.txt
echo "Package ready in $(pwd)/build"
