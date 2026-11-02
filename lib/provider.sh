#!/usr/bin/env bash

# Helpers for the lab scripts of this repository: first the shared helpers
# of cloud-labs-local next to this repository, then the settings in
# config.env, the helpers for all cloud labs and those for AWS.
# Source this file from a script; do not execute it directly.

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# ${BASH_SOURCE[0]} is this file, even when a script sources it: the repository
# is the folder above lib
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# cloud-labs-local next to this repository, unless LOCAL_LABS points elsewhere
LOCAL_LABS="${LOCAL_LABS:-$REPO_ROOT/../cloud-labs-local}"
if [[ ! -f "$LOCAL_LABS/lib/common.sh" ]]; then
    # die comes from common.sh, which is not loaded yet: print to stderr (>&2)
    # and stop
    printf 'ERROR: cloud-labs-local not found next to this repository (%s).\n' "$LOCAL_LABS" >&2
    printf 'Clone it in the WSL shell: cd ~/kurs && git clone https://github.com/mf-iu/cloud-labs-local.git\n' >&2
    exit 1
fi

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# source runs common.sh in this shell: its settings and functions are available
# from here on
# shellcheck source=../../cloud-labs-local/lib/common.sh
source "$LOCAL_LABS/lib/common.sh"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Settings for the cloud labs (copied from config.example.env, never
# committed). GITHUB_USER and PLACEFINDER_IMAGE come from config.env of
# cloud-labs-local.
[[ -f "$REPO_ROOT/config.env" ]] \
    || die "config.env not found: copy config.example.env to config.env in $REPO_ROOT and fill it in."

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# source runs config.env in this shell: its variables stay set
# shellcheck source=/dev/null
source "$REPO_ROOT/config.env"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# shellcheck disable=SC2034  # used by 02-vm/create-vm.sh
PLACEFINDER_REPO="https://github.com/$GITHUB_USER/placefinder.git"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Tag or label value that marks every resource of the course
# shellcheck disable=SC2034  # used by the lab scripts
COURSE_TAG="cloud-computing"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Random lowercase suffix, created once per clone, for globally unique names
suffix() {
    local file="$STATE_DIR/suffix"
    if [[ ! -s "$file" ]]; then
        # six random hex digits, e.g. 3fa9c1
        python3 -c 'import secrets; print(secrets.token_hex(3))' >"$file"
    fi
    cat "$file"
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Resource name: name t02-vm -> pf-mf-t02-vm
name() {
    echo "${PREFIX}-${OWNER}-$1"
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Public IPv4 address of this computer, used for firewall rules
my_ip() {
    # tr --delete '[:space:]' removes the line break at the end of the answer
    curl --fail --silent --show-error --max-time 10 https://checkip.amazonaws.com | tr --delete '[:space:]'
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Password with upper and lower case letters, digits and a symbol
random_password() {
    # Python prints Pf1- and 20 random letters and digits; the program spans
    # three lines inside the single quotes
    python3 -c 'import secrets, string
chars = string.ascii_letters + string.digits
print("Pf1-" + "".join(secrets.choice(chars) for _ in range(20)))'
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# AWS
require aws
# export passes the variables on to every aws command; AWS_PAGER="" prints the
# output directly instead of in the pager less
export AWS_REGION AWS_DEFAULT_REGION="$AWS_REGION" AWS_PAGER=""
if [[ -n "${AWS_PROFILE:-}" ]]; then
    export AWS_PROFILE
fi

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

check_login() {
    aws sts get-caller-identity >/dev/null 2>&1 \
        || die "Not logged in to AWS. Run: aws login --remote"
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

account_id() {
    # --query picks fields of the JSON answer (JMESPath); --output text prints
    # them without quotes
    aws sts get-caller-identity --query Account --output text
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Tags for "--tags" and for "--tag-specifications". "--tags" is used by Simple
# Storage Service (S3), Elastic Container Registry (ECR), Identity and Access
# Management (IAM) ..., "--tag-specifications" by Elastic Compute Cloud (EC2).
aws_tags() {
    echo "Key=course,Value=$COURSE_TAG Key=lab,Value=$1"
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# tag_spec <resource type> <lab> <name>
tag_spec() {
    echo "ResourceType=$1,Tags=[{Key=course,Value=$COURSE_TAG},{Key=lab,Value=$2},{Key=Name,Value=$3}]"
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

default_vpc() {
    local vpc
    # Vpcs[0].VpcId: the id of the first Virtual Private Cloud (VPC) in the
    # answer; the text None if there is none
    vpc=$(aws ec2 describe-vpcs --filters Name=is-default,Values=true \
        --query 'Vpcs[0].VpcId' --output text)
    [[ "$vpc" != "None" ]] || die "No default VPC in $AWS_REGION. Create one: aws ec2 create-default-vpc"
    echo "$vpc"
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Current Ubuntu 24.04 Long-Term Support (LTS) image published by Canonical
# ubuntu_ami [amd64|arm64]
ubuntu_ami() {
    # Canonical publishes the id of the current image as a public parameter of
    # Systems Manager (SSM); ${1:-amd64} is the architecture, amd64 if none is
    # given
    aws ssm get-parameter \
        --name "/aws/service/canonical/ubuntu/server/24.04/stable/current/${1:-amd64}/hvm/ebs-gp3/ami-id" \
        --query Parameter.Value --output text
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Import the SSH public key once; prints the key pair name
# ensure_key_pair <lab>
ensure_key_pair() {
    local key
    key=$(name key)
    [[ -f "$SSH_PUBLIC_KEY" ]] || die "SSH key $SSH_PUBLIC_KEY not found. Create it in the WSL shell, not in the dev container: ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519"
    if ! aws ec2 describe-key-pairs --key-names "$key" >/dev/null 2>&1; then
        # fileb:// passes the content of the file to the CLI as it is
        aws ec2 import-key-pair --key-name "$key" --public-key-material "fileb://$SSH_PUBLIC_KEY" \
            --tag-specifications "$(tag_spec key-pair "$1" "$key")" >/dev/null
    fi
    echo "$key"
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Settings for tools/tofu.sh
tofu_provider_vars() {
    # OpenTofu reads a variable x from the environment variable TF_VAR_x
    export TF_VAR_region="$AWS_REGION"
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

backend_key_arg() {
    echo "key=$1/terraform.tfstate"
}
