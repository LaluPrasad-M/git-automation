#!/usr/bin/env bash

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
