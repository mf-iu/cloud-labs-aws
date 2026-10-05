#!/usr/bin/env bash
# Run OpenTofu in a lab directory with the remote state from t08.
# The first call initialises the backend; settings come from config.env.
#
# Usage: tools/tofu.sh <directory> <tofu command> [arguments]
# Example: tools/tofu.sh t08-iac/infra plan
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/provider.sh"

[[ $# -ge 2 ]] || die "Usage: $0 <directory> <tofu command> [arguments]"
require tofu
check_login
dir="$(cd "$1" && pwd)"
shift

backend="$STATE_DIR/backend.hcl"
[[ -f "$backend" ]] || die "No remote state yet. Run t08-iac/bootstrap-state.sh first."

# Variables shared by all OpenTofu configurations in this repository
export TF_VAR_prefix="$PREFIX" TF_VAR_owner="$OWNER" TF_VAR_placefinder_image="$PLACEFINDER_IMAGE" TF_VAR_suffix
TF_VAR_suffix="$(suffix)"
# Your current IP address for firewall rules (e.g. database access)
export TF_VAR_admin_cidrs
TF_VAR_admin_cidrs="[\"$(my_ip)/32\"]"
tofu_provider_vars   # provider specific variables, see lib/provider.sh

# One state file per directory, e.g. t08-iac/infra/terraform.tfstate
state_key="${dir#"$REPO_ROOT"/}"
if [[ ! -f "$dir/.terraform/terraform.tfstate" ]]; then
  log "Initialising $state_key ..."
  tofu -chdir="$dir" init -input=false -backend-config="$backend" \
    -backend-config="$(backend_key_arg "$state_key")"
fi

tofu -chdir="$dir" "$@"
