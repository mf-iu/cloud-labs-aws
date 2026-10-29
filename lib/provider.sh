#!/usr/bin/env bash
# Helpers for the lab scripts of this repository: first the shared helpers
# of cloud-labs-local next to this repository, then the settings in
# config.env, the helpers for all cloud labs and those for AWS.
# Source this file from a script; do not execute it directly.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_LABS="${LOCAL_LABS:-$REPO_ROOT/../cloud-labs-local}"
if [[ ! -f "$LOCAL_LABS/lib/common.sh" ]]; then
  printf 'ERROR: cloud-labs-local not found next to this repository (%s).\n' "$LOCAL_LABS" >&2
  printf 'Clone it in the WSL shell: cd ~/kurs && git clone https://github.com/mf-iu/cloud-labs-local.git\n' >&2
  exit 1
fi
# shellcheck source=../../cloud-labs-local/lib/common.sh
source "$LOCAL_LABS/lib/common.sh"

# Settings for the cloud labs (copied from config.example.env, never
# committed). GITHUB_USER and PLACEFINDER_IMAGE come from config.env of
# cloud-labs-local.
[[ -f "$REPO_ROOT/config.env" ]] \
  || die "config.env not found: copy config.example.env to config.env in $REPO_ROOT and fill it in."
# shellcheck source=/dev/null
source "$REPO_ROOT/config.env"
# shellcheck disable=SC2034  # used by 02-vm/create-vm.sh
PLACEFINDER_REPO="https://github.com/$GITHUB_USER/placefinder.git"

# Tag or label value that marks every resource of the course
# shellcheck disable=SC2034  # used by the lab scripts
COURSE_TAG="cloud-computing"

# Random lowercase suffix, created once per clone, for globally unique names
suffix() {
  local file="$STATE_DIR/suffix"
  if [[ ! -s "$file" ]]; then
    python3 -c 'import secrets; print(secrets.token_hex(3))' >"$file"
  fi
  cat "$file"
}

# Resource name: name t02-vm -> pf-mf-t02-vm
name() { echo "${PREFIX}-${OWNER}-$1"; }

# Public IPv4 address of this computer, used for firewall rules
my_ip() { curl --fail --silent --show-error --max-time 10 https://checkip.amazonaws.com | tr --delete '[:space:]'; }

# Password with upper and lower case letters, digits and a symbol
random_password() {
  python3 -c 'import secrets, string
chars = string.ascii_letters + string.digits
print("Pf1-" + "".join(secrets.choice(chars) for _ in range(20)))'
}

# AWS
require aws
export AWS_REGION AWS_DEFAULT_REGION="$AWS_REGION" AWS_PAGER=""
if [[ -n "${AWS_PROFILE:-}" ]]; then export AWS_PROFILE; fi

check_login() {
  aws sts get-caller-identity >/dev/null 2>&1 \
    || die "Not logged in to AWS. Run: aws login --remote"
}

account_id() { aws sts get-caller-identity --query Account --output text; }

# Tags for "--tags" (S3, ECR, IAM ...) and for "--tag-specifications" (EC2)
aws_tags() { echo "Key=course,Value=$COURSE_TAG Key=lab,Value=$1"; }
tag_spec() {   # tag_spec <resource type> <lab> <name>
  echo "ResourceType=$1,Tags=[{Key=course,Value=$COURSE_TAG},{Key=lab,Value=$2},{Key=Name,Value=$3}]"
}

default_vpc() {
  local vpc
  vpc=$(aws ec2 describe-vpcs --filters Name=is-default,Values=true \
    --query 'Vpcs[0].VpcId' --output text)
  [[ "$vpc" != "None" ]] || die "No default VPC in $AWS_REGION. Create one: aws ec2 create-default-vpc"
  echo "$vpc"
}

# Current Ubuntu 24.04 LTS image published by Canonical
ubuntu_ami() {   # ubuntu_ami [amd64|arm64]
  aws ssm get-parameter \
    --name "/aws/service/canonical/ubuntu/server/24.04/stable/current/${1:-amd64}/hvm/ebs-gp3/ami-id" \
    --query Parameter.Value --output text
}

# Import the SSH public key once; prints the key pair name
ensure_key_pair() {   # ensure_key_pair <lab>
  local key
  key=$(name key)
  [[ -f "$SSH_PUBLIC_KEY" ]] || die "SSH key $SSH_PUBLIC_KEY not found. Create it in the WSL shell, not in the dev container: ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519"
  if ! aws ec2 describe-key-pairs --key-names "$key" >/dev/null 2>&1; then
    aws ec2 import-key-pair --key-name "$key" --public-key-material "fileb://$SSH_PUBLIC_KEY" \
      --tag-specifications "$(tag_spec key-pair "$1" "$key")" >/dev/null
  fi
  echo "$key"
}

# Settings for tools/tofu.sh
tofu_provider_vars() { export TF_VAR_region="$AWS_REGION"; }
backend_key_arg() { echo "key=$1/terraform.tfstate"; }
