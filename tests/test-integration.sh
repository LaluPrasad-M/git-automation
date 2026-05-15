#!/usr/bin/env bash
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required"
  exit 1
fi

echo "Running dry integration checks"
for f in tests/payloads/*.json; do
  jq . "$f" >/dev/null
  repo="$(jq -r '.target_repo // ""' "$f")"
  if [[ -z "$repo" ]]; then
    echo "Missing target_repo in $f"
    exit 1
  fi
  echo "Validated payload: $f (repo=$repo)"
done

echo "Integration checks complete"
