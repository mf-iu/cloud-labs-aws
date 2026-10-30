#!/usr/bin/env bash

# Run OpenTofu in a lab directory with the remote state that
# 06-infrastructure-as-code/bootstrap-state.sh set up. The first call
# initialises the backend; settings come from config.env.
#
# Usage: tools/tofu.sh <directory> <tofu command> [arguments]
# Example: tools/tofu.sh 06-infrastructure-as-code/base plan

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

source "$(dirname "$0")/../lib/provider.sh"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

require_github_user   # PLACEFINDER_IMAGE and PLACEFINDER_REPO need it

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

[[ $# -ge 2 ]] || die "Usage: $0 <directory> <tofu command> [arguments]"
require tofu
check_login
# Absolute path of the directory; shift drops it, so "$@" is the tofu command
# with its arguments
dir="$(cd "$1" && pwd)"
shift

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

backend="$STATE_DIR/backend.hcl"
[[ -f "$backend" ]] || die "No remote state yet. Run 06-infrastructure-as-code/bootstrap-state.sh first."

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Variables shared by all OpenTofu configurations in this repository
# OpenTofu reads a variable x from the environment variable TF_VAR_x; export
# passes them on to tofu
export TF_VAR_prefix="$PREFIX" TF_VAR_owner="$OWNER" TF_VAR_placefinder_image="$PLACEFINDER_IMAGE" TF_VAR_suffix
TF_VAR_suffix="$(suffix)"
tofu_provider_vars   # provider specific variables, see lib/provider.sh

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# The settings of the backend as a map of strings, for configurations that
# read the outputs of another one, e.g. service reads base
# (terraform_remote_state)
export TF_VAR_backend
# Python reads the lines key = "value" of backend.hcl with a regular expression
# and prints them as a JSON object, which OpenTofu accepts as a map
TF_VAR_backend="$(python3 -c '
import json, re, sys
pairs = re.findall(r"^\s*(\w+)\s*=\s*\"([^\"]*)\"", open(sys.argv[1]).read(), re.M)
print(json.dumps(dict(pairs)))' "$backend")"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# One state file per directory, e.g. 06-infrastructure-as-code/base/terraform.tfstate
# ${dir#x/} removes x/ from the start: the path relative to the repository
state_key="${dir#"$REPO_ROOT"/}"
if [[ ! -f "$dir/.terraform/terraform.tfstate" ]]; then
    log "Initialising $state_key ..."
    # -chdir runs tofu in that directory; -input=false: fail instead of asking
    tofu -chdir="$dir" init -input=false -backend-config="$backend" \
        -backend-config="$(backend_key_arg "$state_key")"
fi

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

tofu -chdir="$dir" "$@"
