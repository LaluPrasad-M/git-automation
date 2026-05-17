#!/usr/bin/env bash

_provider_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_provider="${LLM_PROVIDER:-anthropic}"
# shellcheck disable=SC1090
source "$_provider_dir/${_provider}_service.sh"
