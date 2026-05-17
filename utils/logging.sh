#!/usr/bin/env bash

log() {
  local type="$1"; shift
  local ts
  ts="$(date +'%Y-%m-%d %H:%M:%S')"
  printf '[%s][%s] %s\n' "$ts" "$type" "$*"
}
