#!/usr/bin/env bash
# Delete the budget created by create-budget.sh.
# Usage: ./delete-budget.sh
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/provider.sh"

check_login
budget_name=$(name monthly-budget)
account=$(account_id)
if ! aws budgets describe-budget --account-id "$account" --budget-name "$budget_name" >/dev/null 2>&1; then
  log "No budget $budget_name."
  exit 0
fi
confirm "Delete budget $budget_name?" || exit 0
aws budgets delete-budget --account-id "$account" --budget-name "$budget_name"
log "Budget $budget_name deleted."
