#!/usr/bin/env bash
set -euo pipefail

extract_json_payload() {
  local raw="$1"
  if jq -e . >/dev/null 2>&1 <<<"$raw"; then
    printf '%s' "$raw"
    return 0
  fi

  local fenced
  fenced="$(printf '%s' "$raw" | awk '/```json/{flag=1;next}/```/{if(flag){flag=0;exit}}flag')"
  if [[ -n "$fenced" ]] && jq -e . >/dev/null 2>&1 <<<"$fenced"; then
    printf '%s' "$fenced"
    return 0
  fi

  return 1
}

severity_label() {
  case "$1" in
    critical) echo "Critical" ;;
    major)    echo "Major" ;;
    minor)    echo "Minor" ;;
    nit)      echo "Nit" ;;
    *)        echo "Minor" ;;
  esac
}
