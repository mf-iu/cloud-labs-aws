#!/usr/bin/env bash

# Check the AWS CLI, the login and the most important settings.
# First, without config.env and login: the tools of the provider, and
# cloud-labs-local and placefinder next to this repository. With
# --tools-only, only that: the dev container runs it so when it is created,
# after tools/check-tools.sh of cloud-labs-local.
#
# Usage: ./check-cli.sh [--tools-only]

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Without errexit: a missing tool is reported, and the script goes on with the
# next one
set -o nounset -o pipefail
# Absolute path of the folder above this script, i.e. of the repository
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failed=0

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# report <status> <tool> <text>
report() {
    local color=32
    # { ...; } groups commands: both run if the status is not OK (31 = red, 32 =
    # green)
    [[ "$1" == OK ]] || { color=31; failed=1; }
    # %-8s prints the text left-aligned in a column 8 characters wide
    printf '  \033[1;%sm%-8s\033[0m %-16s %s\n' "$color" "$1" "$2" "$3"
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# version_ge 2.32.1 2.32 -> true
version_ge() {
    # Sort both versions as versions (2.9 before 2.10); if the minimum comes
    # first, the version is high enough
    [[ "$(printf '%s\n%s\n' "$2" "$1" | sort --version-sort | head --lines 1)" == "$2" ]]
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# check <tool> <minimum version or -> <command printing the version ...>
check() {
    local tool=$1 min=$2 version
    # shift 2 drops tool and minimum; "$@" is then the command that prints the
    # version
    shift 2
    if ! command -v "$tool" >/dev/null 2>&1; then
        report MISSING "$tool" "not installed"
        return
    fi
    # Run the command and keep the first number like 1.2 or 1.2.3 of its output
    version="$("$@" 2>&1 | grep --only-matching --extended-regexp '[0-9]+\.[0-9]+(\.[0-9]+)?' | sed --quiet 1p)"
    if [[ "$min" != - ]] && ! version_ge "${version:-0}" "$min"; then
        report "TOO OLD" "$tool" "${version:-unknown}, at least $min needed"
    else
        report OK "$tool" "${version:-installed}"
    fi
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

printf '\033[1;36m==>\033[0m Tools of the provider and folders next to this repository\n'
check aws 2.32 aws --version
for dir in cloud-labs-local placefinder; do
    if [[ -d "$repo_root/../$dir" ]]; then
        report OK "$dir" "$(cd "$repo_root/../$dir" && pwd)"
    else
        report MISSING "$dir" "clone it next to this repository (cloud-labs-local/00-setup)"
    fi
done
if (( failed )); then
    printf '\n\033[1;31mSomething is missing.\033[0m Clone the folders in the WSL shell, then\n'
    printf 'rebuild the dev container (VS Code: "Dev Containers: Rebuild Container").\n'
    exit 1
fi
# ${1:-} is the first argument, or empty if there is none
[[ "${1:-}" != --tools-only ]] || exit 0

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

source "$(dirname "$0")/../lib/provider.sh"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

log "AWS CLI: $(aws --version 2>&1)"
check_login
aws sts get-caller-identity --output table
log "Region: $AWS_REGION, profile: ${AWS_PROFILE:-<none>}"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Working with the root user is discouraged; warn if that is the case
arn=$(aws sts get-caller-identity --query Arn --output text)
# *":root": the Amazon Resource Name (ARN) ends with :root
if [[ "$arn" == *":root" ]]; then
    warn "You are logged in as root user. Create an IAM user for daily work (see README)."
fi

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

log "Budgets in this account:"
# --query picks fields of the JSON answer (JMESPath): name, amount and unit of
# every budget; || true: a missing permission is no error here
aws budgets describe-budgets --account-id "$(account_id)" \
    --query 'Budgets[].[BudgetName,BudgetLimit.Amount,BudgetLimit.Unit]' --output table || true
