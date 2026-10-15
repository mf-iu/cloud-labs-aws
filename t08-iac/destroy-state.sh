#!/usr/bin/env bash
# Delete the state bucket with all versions. Only do this after every
# OpenTofu configuration has been destroyed (tofu destroy)!
# Usage: ./destroy-state.sh
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/provider.sh"

check_login
bucket="$(name "$(suffix)-tfstate")"
aws s3api head-bucket --bucket "$bucket" 2>/dev/null || { log "No state bucket."; exit 0; }
aws s3 ls --recursive "s3://$bucket"
confirm "Delete state bucket s3://$bucket with all state versions?" || exit 0

# A versioned bucket can only be deleted after all versions are gone
python3 - "$bucket" <<'PY'
import json, subprocess, sys
bucket = sys.argv[1]
out = subprocess.run(["aws", "s3api", "list-object-versions", "--bucket", bucket, "--output", "json"],
                     check=True, capture_output=True, text=True).stdout
data = json.loads(out or "{}")
objects = [{"Key": o["Key"], "VersionId": o["VersionId"]}
           for o in data.get("Versions", []) + data.get("DeleteMarkers", [])]
for i in range(0, len(objects), 1000):
    subprocess.run(["aws", "s3api", "delete-objects", "--bucket", bucket, "--delete",
                    json.dumps({"Objects": objects[i:i + 1000]})], check=True, capture_output=True)
print(f"deleted {len(objects)} object versions")
PY
aws s3api delete-bucket --bucket "$bucket"
rm --force "$STATE_DIR/backend.hcl"
log "State bucket deleted."
