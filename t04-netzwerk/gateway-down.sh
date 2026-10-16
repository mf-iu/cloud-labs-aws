#!/usr/bin/env bash
# Delete the k3d cluster of the Gateway API demo (gateway-up.sh).
# The course CA stays in .state for the next run; it is valid for 30 days.
# Usage: ./gateway-down.sh
source "$(dirname "$0")/../lib/common.sh"

CLUSTER=net
require k3d
if ! k3d_cluster_exists "$CLUSTER"; then
  log "No cluster $CLUSTER."
  exit 0
fi
confirm "Delete the k3d cluster $CLUSTER with gateway, cert-manager and PlaceFinder?" || exit 0
k3d cluster delete "$CLUSTER"
log "Done."
