#!/usr/bin/env bash
set -euo pipefail

log() {
  local type="$1"; shift
  local ts
  ts="$(date +'%Y-%m-%d %H:%M:%S')"
  printf '[%s][%s] %s\n' "$ts" "$type" "$*"
}
