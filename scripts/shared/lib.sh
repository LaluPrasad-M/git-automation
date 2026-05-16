#!/usr/bin/env bash

_provider_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../providers" && pwd)"
_provider="${LLM_PROVIDER:-anthropic}"
# shellcheck disable=SC1090
source "$_provider_dir/${_provider}.sh"

log() {
  local type="$1"; shift
  local ts
  ts="$(date +'%Y-%m-%d %H:%M:%S')"
  printf '[%s][%s] %s\n' "$ts" "$type" "$*"
}

resolve_control_path() {
  local p="$1"
  if [[ "$p" = /* ]]; then
    echo "$p"
  else
    echo "$GITHUB_WORKSPACE/$p"
  fi
}

read_policy() {
  local key="$1"
  if [[ "$(yq e '.repo' "$POLICY_FILE" 2>/dev/null)" != "null" ]]; then
    yq e ".$key // \"\"" "$POLICY_FILE"
  else
    yq e ".defaults.$key // \"\"" "$POLICY_FILE"
  fi
}
