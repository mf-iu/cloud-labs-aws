#!/usr/bin/env bash
# Create the local Kubernetes cluster for session 3 with k3d: one server
# (control plane) and two agents (worker nodes), each a container in the
# Docker Engine of the dev container. Starts the cluster if it exists.
# Usage: ./cluster-up.sh [agents]   (default: 2)
source "$(dirname "$0")/../lib/common.sh"

CLUSTER=pf
# Kubernetes version of the nodes; newer ones: https://docs.k3s.io/release-notes
K3S_IMAGE="${K3S_IMAGE:-rancher/k3s:v1.36.5-k3s1}"
agents="${1:-2}"
require docker k3d kubectl
docker info >/dev/null 2>&1 || die "Docker is not running. Use the terminal of the dev container."

# three nodes need about 1.5 to 2 GB of memory (WSL: see .wslconfig)
available=$(awk '/^MemAvailable/ { print int($2 / 1024) }' /proc/meminfo)
(( available >= 2500 )) || warn "Only ${available} MB of memory available; the cluster may be slow."

if k3d_cluster_exists "$CLUSTER"; then
  log "Cluster $CLUSTER exists; starting it in case it is stopped ..."
  k3d cluster start "$CLUSTER"
  # after a rebuild of the dev container the kubeconfig entry is gone
  k3d kubeconfig merge "$CLUSTER" --kubeconfig-merge-default --kubeconfig-switch-context >/dev/null
else
  log "Creating cluster $CLUSTER with 1 server and $agents agents ($K3S_IMAGE) ..."
  k3d cluster create "$CLUSTER" --agents "$agents" --image "$K3S_IMAGE"
fi
kubectl config use-context "k3d-$CLUSTER" >/dev/null
log "Waiting until all nodes are ready ..."
kubectl wait --for condition=Ready nodes --all --timeout 120s >/dev/null
kubectl get nodes --output wide

cat <<INFO

Next:    ./build-image.sh
         kubectl apply --filename ../../placefinder/deploy/k8s/
Remove:  ./cluster-down.sh
INFO
