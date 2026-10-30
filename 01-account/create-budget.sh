#!/usr/bin/env bash

# Create a monthly cost budget with e-mail alerts.
# Alerts at 50 % and 80 % of the actual costs and at 100 % of the forecast.
# The budget counts costs before credits: in the Free Plan the credits pay
# for everything, so a budget with credits would always stay at 0 USD.
#
# Usage: ./create-budget.sh

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

source "$(dirname "$0")/../lib/provider.sh"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

check_login
budget_name=$(name monthly-budget)
account=$(account_id)
# The exit code of describe-budget is enough: success means the budget exists
if aws budgets describe-budget --account-id "$account" --budget-name "$budget_name" >/dev/null 2>&1; then
    log "Budget $budget_name exists already. To change it, run ./delete-budget.sh first."
    exit 0
fi
# A temporary folder for the JSON files; trap deletes it when the script ends
# (EXIT), also after an error
tmp=$(mktemp --directory)
trap 'rm --recursive --force "$tmp"' EXIT

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Write the text up to the line JSON into the file; $variables in it are
# replaced
cat >"$tmp/budget.json" <<JSON
{
  "BudgetName": "$budget_name",
  "BudgetLimit": {"Amount": "$BUDGET_AMOUNT", "Unit": "USD"},
  "TimeUnit": "MONTHLY",
  "BudgetType": "COST",
  "CostTypes": {"IncludeCredit": false}
}
JSON

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# alert <ACTUAL|FORECASTED> <percent>
alert() {
    cat <<JSON
  {
    "Notification": {
      "NotificationType": "$1",
      "ComparisonOperator": "GREATER_THAN",
      "Threshold": $2,
      "ThresholdType": "PERCENTAGE"
    },
    "Subscribers": [{"SubscriptionType": "EMAIL", "Address": "$ALERT_EMAIL"}]
  }
JSON
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# A JSON list of the three alerts; each %s is replaced by the output of one
# alert call
printf '[%s,%s,%s]\n' "$(alert ACTUAL 50)" "$(alert ACTUAL 80)" "$(alert FORECASTED 100)" \
    >"$tmp/notifications.json"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

log "Creating budget $budget_name ($BUDGET_AMOUNT USD per month, alerts to $ALERT_EMAIL) ..."
# file:// makes the CLI read the parameter from a file
aws budgets create-budget --account-id "$account" \
    --budget "file://$tmp/budget.json" \
    --notifications-with-subscribers "file://$tmp/notifications.json"
log "Done. Check it in the console: Billing and Cost Management > Budgets."
