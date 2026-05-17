#!/usr/bin/env bash
set -euo pipefail

_provider_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_provider="${LLM_PROVIDER:-anthropic}"
case "$_provider" in
  anthropic|openai) ;;
  *) echo "Unsupported LLM_PROVIDER: $_provider" >&2; exit 1 ;;
esac
# shellcheck disable=SC1090
source "$_provider_dir/${_provider}_service.sh"
