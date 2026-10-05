#!/usr/bin/env bash
# Check the AWS CLI, the login and the most important settings.
# Usage: ./check-cli.sh
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/provider.sh"

log "AWS CLI: $(aws --version 2>&1)"
check_login
aws sts get-caller-identity --output table
log "Region: $AWS_REGION, profile: ${AWS_PROFILE:-<none>}"

# Working with the root user is discouraged; warn if that is the case
arn=$(aws sts get-caller-identity --query Arn --output text)
if [[ "$arn" == *":root" ]]; then
  warn "You are logged in as root user. Create an IAM user for daily work (see README)."
fi

log "Budgets in this account:"
aws budgets describe-budgets --account-id "$(account_id)" \
  --query 'Budgets[].[BudgetName,BudgetLimit.Amount,BudgetLimit.Unit]' --output table || true
