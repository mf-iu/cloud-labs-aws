#!/usr/bin/env bash
# Build the PlaceFinder image from the repository next to this one and load it
# into the k3d cluster. With --push, also upload it to the GitHub Container
# Registry for the container services of the cloud providers.
# Usage: ./build-image.sh [--push [--tag <name>]] [version]
#   version  image tag, default: version in pyproject.toml of PlaceFinder
#   --push   also push $PLACEFINDER_IMAGE:<version> and $PLACEFINDER_IMAGE:<name>
#   --tag    name of the session state, default: t03 (t05 for session 5 ...)
source "$(dirname "$0")/../lib/common.sh"

CLUSTER=pf
SOURCE_DIR=$(realpath --canonicalize-missing "${PLACEFINDER_DIR:-$REPO_ROOT/../placefinder}")
USAGE="Usage: ./build-image.sh [--push [--tag <name>]] [version]"
push=0
state_tag=""
version=""
while (( $# )); do
  case "$1" in
    --push) push=1 ;;
    --tag) (( $# > 1 )) || die "$USAGE"; state_tag=$2; shift ;;
    -*) die "Unknown option $1. $USAGE" ;;
    *) version=$1 ;;
  esac
  shift
done
[[ -z "$state_tag" ]] || (( push )) || die "--tag works only with --push. $USAGE"
state_tag=${state_tag:-t03}
require docker python3
if (( push )); then
  # check before the build, which takes a while
  require gh
  [[ "$GITHUB_USER" != your-github-user ]] || die "Set GITHUB_USER in config.env."
  gh auth status >/dev/null 2>&1 || die "Not logged in to GitHub. Run: gh auth login"
  gh auth status 2>&1 | grep --quiet "write:packages" \
    || die "The GitHub token cannot upload packages. Run: gh auth refresh --scopes write:packages"
fi
[[ -f "$SOURCE_DIR/Dockerfile" ]] \
  || die "No Dockerfile in $SOURCE_DIR. Clone your fork of PlaceFinder next to this repository (or set PLACEFINDER_DIR)."
if [[ -z "$version" ]]; then
  version=$(python3 -c 'import sys, tomllib; print(tomllib.load(open(sys.argv[1], "rb"))["project"]["version"])' \
    "$SOURCE_DIR/pyproject.toml")
fi
image="placefinder:$version"

log "Building $image from $SOURCE_DIR ..."
docker build --tag "$image" "$SOURCE_DIR"

if command -v k3d >/dev/null 2>&1 && k3d_cluster_exists "$CLUSTER"; then
  # the nodes run their own containerd and do not see the images of Docker
  log "Importing $image into the nodes of cluster $CLUSTER ..."
  k3d image import "$image" --cluster "$CLUSTER"
elif (( ! push )); then
  warn "No k3d cluster $CLUSTER. Run ./cluster-up.sh, then this script again."
fi

if (( push )); then
  log "Logging in to ghcr.io as $GITHUB_USER ..."
  gh auth token | docker login ghcr.io --username "$GITHUB_USER" --password-stdin >/dev/null
  for tag in "$version" "$state_tag"; do
    docker tag "$image" "$PLACEFINDER_IMAGE:$tag"
    docker push "$PLACEFINDER_IMAGE:$tag"
  done
  if check_public_image "$PLACEFINDER_IMAGE:$state_tag"; then
    log "$PLACEFINDER_IMAGE:$state_tag is public."
  else
    warn "$PLACEFINDER_IMAGE is private. Make it public on GitHub: Packages → placefinder → Package settings → Change visibility."
  fi
fi
log "Done: $image"
