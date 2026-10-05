#!/usr/bin/env bash
# AWS specific helpers. Source after lib/common.sh.

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
  [[ -f "$SSH_PUBLIC_KEY" ]] || die "SSH key $SSH_PUBLIC_KEY not found. Create one: ssh-keygen -t ed25519"
  if ! aws ec2 describe-key-pairs --key-names "$key" >/dev/null 2>&1; then
    aws ec2 import-key-pair --key-name "$key" --public-key-material "fileb://$SSH_PUBLIC_KEY" \
      --tag-specifications "$(tag_spec key-pair "$1" "$key")" >/dev/null
  fi
  echo "$key"
}

# Settings for tools/tofu.sh
tofu_provider_vars() { export TF_VAR_region="$AWS_REGION"; }
backend_key_arg() { echo "key=$1/terraform.tfstate"; }
