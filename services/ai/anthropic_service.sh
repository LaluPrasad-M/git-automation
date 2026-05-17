#!/usr/bin/env bash
set -euo pipefail
# Anthropic provider — implements call_llm() using the claude CLI.
# Required env: ANTHROPIC_API_KEY

call_llm() {
  local prompt="$1"
  local tools="${2:-}"
  local max_turns="${3:-${MAX_TURNS:-5}}"

  local model="${ANTHROPIC_MODEL:-claude-sonnet-4-6}"
  local args=(-p "$prompt" --model "$model" --max-turns "$max_turns" --output-format text)
  [[ -n "$tools" ]] && args+=(--allowedTools "$tools")

  claude "${args[@]}"
}
