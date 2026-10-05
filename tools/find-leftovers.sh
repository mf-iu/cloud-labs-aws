#!/usr/bin/env bash
# List course resources that still exist, and everything that costs money
# by the hour even without the course tag. Deletes nothing.
# Usage: tools/find-leftovers.sh
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/provider.sh"

check_login
section() { printf '\n\033[1;36m%s\033[0m\n' "$*"; }

section "Resources tagged course=$COURSE_TAG in $AWS_REGION"
# shellcheck disable=SC2016  # backticks are JMESPath literals
aws resourcegroupstaggingapi get-resources \
  --tag-filters "Key=course,Values=$COURSE_TAG" \
  --query 'ResourceTagMappingList[].[ResourceARN, Tags[?Key==`lab`]|[0].Value]' --output table

section "Running or stopped EC2 instances"
# shellcheck disable=SC2016
aws ec2 describe-instances \
  --filters Name=instance-state-name,Values=pending,running,stopping,stopped \
  --query 'Reservations[].Instances[].[InstanceId,InstanceType,State.Name,Tags[?Key==`Name`]|[0].Value]' \
  --output table
section "NAT gateways"
aws ec2 describe-nat-gateways --filter Name=state,Values=pending,available \
  --query 'NatGateways[].[NatGatewayId,State,VpcId]' --output table
section "Elastic IP addresses"
aws ec2 describe-addresses --query 'Addresses[].[PublicIp,AllocationId,AssociationId]' --output table
section "Load balancers"
aws elbv2 describe-load-balancers --query 'LoadBalancers[].[LoadBalancerName,Type,State.Code]' --output table
section "RDS instances"
aws rds describe-db-instances --query 'DBInstances[].[DBInstanceIdentifier,DBInstanceClass,DBInstanceStatus]' --output table
section "ECS services"
aws ecs list-services --cluster default --query 'serviceArns' --output table 2>/dev/null || echo "no default cluster"
section "S3 buckets (global)"
aws s3 ls | grep -- "$PREFIX-$OWNER-" || echo "none"
