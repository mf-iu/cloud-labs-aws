#!/usr/bin/env bash
# Rebuild the demo of session 4 in a local k3d cluster: PlaceFinder over
# HTTPS through the Gateway API of Traefik, with a certificate that
# cert-manager issues from a course CA of your own. Costs nothing, everything
# runs in the Docker Engine of the dev container. Safe to run again.
# Usage: ./gateway-up.sh
source "$(dirname "$0")/../lib/common.sh"

CLUSTER=net
HTTPS_PORT=8443                                   # port in the dev container
K3S_IMAGE="${K3S_IMAGE:-rancher/k3s:v1.36.5-k3s1}"
CERT_MANAGER_VERSION=v1.21.2
HERE=$(cd "$(dirname "$0")" && pwd)
K8S="$HERE/k8s"
SOURCE_DIR=$(realpath --canonicalize-missing "${PLACEFINDER_DIR:-$REPO_ROOT/../placefinder}")
MANIFEST="$SOURCE_DIR/deploy/k8s/placefinder.yaml"
CA_CERT="$STATE_DIR/course-ca.crt"
CA_KEY="$STATE_DIR/course-ca.key"
require docker k3d kubectl helm openssl curl python3
docker info >/dev/null 2>&1 || die "Docker is not running. Use the terminal of the dev container."
[[ -f "$MANIFEST" ]] \
  || die "$MANIFEST not found. PlaceFinder needs the manifest of session 3 (tag t03 or later)."

wait_until() {   # wait_until <what> <seconds> <command...>
  local what=$1 timeout=$2 start=$SECONDS
  shift 2
  until "$@" >/dev/null 2>&1; do
    (( SECONDS - start < timeout )) || die "No $what after ${timeout}s."
    sleep 5
  done
}

# 1 Cluster: port 8443 of the dev container to port 443 of the k3d load balancer
if k3d_cluster_exists "$CLUSTER"; then
  log "Cluster $CLUSTER exists; starting it in case it is stopped ..."
  k3d cluster start "$CLUSTER"
  k3d kubeconfig merge "$CLUSTER" --kubeconfig-merge-default --kubeconfig-switch-context >/dev/null
else
  if k3d_cluster_exists pf; then
    warn "Cluster pf of session 3 is running, too. Short of memory? k3d cluster stop pf"
  fi
  log "Creating cluster $CLUSTER with one node ($K3S_IMAGE) ..."
  k3d cluster create "$CLUSTER" --image "$K3S_IMAGE" --port "$HTTPS_PORT:443@loadbalancer"
fi
kubectl config use-context "k3d-$CLUSTER" >/dev/null
kubectl wait --for condition=Ready nodes --all --timeout 120s >/dev/null

# 2 Gateway API provider of the Traefik that comes with k3s
log "Switching on the Gateway API provider of Traefik ..."
kubectl apply --filename "$K8S/traefik-gw.yaml"
wait_until "GatewayClass traefik" 240 kubectl get gatewayclass traefik

# 3 PlaceFinder with the manifest of session 3 and the image it names
image=$(grep --only-matching --max-count 1 'placefinder:[0-9][0-9a-z.]*' "$MANIFEST")
if ! docker image inspect "$image" >/dev/null 2>&1; then
  log "Building $image with ../t03-container/build-image.sh ..."
  "$HERE/../t03-container/build-image.sh" "${image#placefinder:}"
fi
log "Importing $image and starting PlaceFinder ..."
k3d image import "$image" --cluster "$CLUSTER"
kubectl apply --filename "$SOURCE_DIR/deploy/k8s/"

# 4 cert-manager with Gateway API support, from its OCI registry
log "Installing cert-manager $CERT_MANAGER_VERSION (takes a minute) ..."
helm upgrade --install cert-manager oci://quay.io/jetstack/charts/cert-manager \
  --version "$CERT_MANAGER_VERSION" --namespace cert-manager --create-namespace \
  --values "$K8S/cert-manager-values.yaml" --wait --timeout 5m

# 5 Course CA (valid for 30 days, renewed one day before) as secret of the issuer
new_ca=false
if [[ ! -f "$CA_CERT" ]] || ! openssl x509 -checkend 86400 -noout -in "$CA_CERT" >/dev/null; then
  log "Creating the course CA in .state/course-ca.crt ..."
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
    -keyout "$CA_KEY" -out "$CA_CERT" -days 30 -subj "/CN=Cloud Computing Kurs-CA $OWNER" \
    -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign"
  new_ca=true
fi
kubectl create secret tls course-ca --namespace cert-manager --cert "$CA_CERT" --key "$CA_KEY" \
  --dry-run=client --output yaml | kubectl apply --filename -

# 6 Issuer, Gateway and HTTPRoute; cert-manager creates the certificate
kubectl apply --filename "$K8S/issuer.yaml" --filename "$K8S/gateway.yaml" \
  --filename "$K8S/route.yaml"
if $new_ca; then
  # a certificate from an earlier CA would no longer be trusted
  kubectl delete secret pf-tls --ignore-not-found
fi
log "Waiting for gateway, certificate and PlaceFinder ..."
kubectl wait --for condition=Programmed gateway/web --timeout 180s >/dev/null
wait_until "certificate pf-tls" 120 kubectl get certificate pf-tls
kubectl wait --for condition=Ready certificate/pf-tls --timeout 180s >/dev/null
kubectl rollout status deployment/placefinder --timeout 300s >/dev/null
kubectl get gateway,httproute,certificate

# 7 HTTPS request, checked against the course CA
url="https://placefinder.test:$HTTPS_PORT/places?q=Berlin"
https() { curl --fail --silent --show-error --cacert "$CA_CERT" \
  --resolve "placefinder.test:$HTTPS_PORT:127.0.0.1" "$@"; }
wait_until "HTTPS answer from $url" 60 https --output /dev/null "$url"
https "$url" | python3 -c 'import json, sys; p = json.load(sys.stdin); print(len(p), "places, first:", p[0]["name"], p[0]["country_code"])'

cat <<INFO

HTTPS:   curl --cacert ../.state/course-ca.crt --resolve placefinder.test:$HTTPS_PORT:127.0.0.1 \\
           "$url"
Extra:   kubectl apply --filename k8s/networkpolicies.yaml   (README: NetworkPolicies)
Remove:  ./gateway-down.sh
INFO
