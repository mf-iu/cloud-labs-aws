#!/usr/bin/env bash
# Shared helpers for all lab scripts.
# Source this file from a script; do not execute it directly.

set -o errexit -o errtrace -o nounset -o pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$REPO_ROOT/.state"
DATA_DIR="$STATE_DIR/data"
mkdir --parents "$STATE_DIR" "$DATA_DIR"

# Personal settings (copied from config.example.env, never committed)
if [[ ! -f "$REPO_ROOT/config.env" ]]; then
  echo "config.env not found: copy config.example.env to config.env and fill it in." >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$REPO_ROOT/config.env"

# Tag or label value that marks every resource of the course
# shellcheck disable=SC2034  # used by provider.sh and the lab scripts
COURSE_TAG="cloud-computing"

log()  { printf '\033[1;36m==>\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33mWARNING:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

trap 'warn "Command failed in line $LINENO: $BASH_COMMAND"' ERR

# Fail early if a required command is missing
require() {
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || die "Command not found: $cmd"
  done
}

# Ask before doing something expensive or destructive.
# Set ASSUME_YES=1 to skip all questions.
confirm() {
  [[ "${ASSUME_YES:-0}" == 1 ]] && return 0
  local answer
  read -r -p "$1 [y/N] " answer
  [[ "$answer" =~ ^[yYjJ] ]]
}

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

# State files remember the ids of created resources for the destroy scripts
state_file() { echo "$STATE_DIR/$1.env"; }
save_state() {   # save_state <lab> <key> <value>
  printf '%s=%q\n' "$2" "$3" >>"$(state_file "$1")"
}
load_state() {   # load_state <lab>
  local file
  file="$(state_file "$1")"
  if [[ -f "$file" ]]; then
    # shellcheck source=/dev/null
    source "$file"
  fi
}
clear_state() { rm --force "$(state_file "$1")"; }

# Replace a placeholder like __REPO__ in a template file and print the result
render() {   # render <file> KEY=value ...
  local file=$1 text pair
  shift
  # bash 5.2 would otherwise treat "&" in the value as the matched text
  shopt -u patsub_replacement 2>/dev/null || true
  text="$(cat "$file")"
  for pair in "$@"; do
    text="${text//__${pair%%=*}__/${pair#*=}}"
  done
  printf '%s\n' "$text"
}

# Check that the VM will be able to clone the Git repository: it clones
# anonymously, so the repository must be public and contain the tag or branch.
check_repo_ref() {   # check_repo_ref <repository url> <tag or branch>
  local repo=$1 ref=$2
  log "Checking $repo for '$ref' ..."
  GIT_TERMINAL_PROMPT=0 git -c credential.helper= ls-remote --exit-code \
      "$repo" "refs/tags/$ref" "refs/heads/$ref" >/dev/null 2>&1 \
    || die "Cannot read '$ref' from $repo. Check GITHUB_USER in config.env, make the repository public and push the tags (git push origin --tags)."
}

# Wait until a URL answers with a 2xx or 3xx status. Failed attempts are
# expected while a new VM installs the application, so they are not
# printed; a progress line appears once a minute.
wait_for_http() {   # wait_for_http <url> [timeout seconds]
  local url=$1 timeout=${2:-300} start=$SECONDS
  log "Waiting for $url (up to ${timeout}s; no answer yet is normal at first) ..."
  until curl --fail --silent --output /dev/null --max-time 5 "$url"; do
    if (( SECONDS - start > timeout )); then
      warn "No answer from $url after ${timeout}s"
      return 1
    fi
    sleep 10
    if (( (SECONDS - start) % 60 < 10 )); then
      log "... still waiting ($(( (SECONDS - start) / 60 )) min)"
    fi
  done
  log "$url answers after $(( SECONDS - start ))s."
}

# Download a GeoNames dump (CC BY 4.0) into .state/data and print the path of
# its text file, e.g. download_geonames DE -> .state/data/DE.txt
download_geonames() {   # download_geonames <name>
  local name=$1 txt="$DATA_DIR/$1.txt"
  if [[ ! -s "$txt" ]]; then
    log "Downloading $name from GeoNames ..."
    curl --fail --silent --show-error --location --output "$DATA_DIR/$name.zip" "https://download.geonames.org/export/dump/$name.zip"
    python3 -m zipfile --extract "$DATA_DIR/$name.zip" "$DATA_DIR"
  fi
  echo "$txt"
}

# Download GeoNames cities15000 into .state/data
download_cities() { download_geonames cities15000; }

# Run psql locally or, if it is not installed, in a container
psql_run() {
  if command -v psql >/dev/null 2>&1; then
    psql "$@"
  else
    require docker
    docker run --rm --interactive --network host --env PGOPTIONS --volume "$REPO_ROOT:$REPO_ROOT" --workdir "$PWD" \
      postgres:18-alpine psql "$@"
  fi
}
