#!/usr/bin/env bash
# Anthropic provider — implements call_llm() using the claude CLI.
# Required env: ANTHROPIC_API_KEY

call_llm() {
  local prompt="$1"
  local tools="${2:-}"
  local max_turns="${3:-10}"

  local args=(-p "$prompt" --max-turns "$max_turns" --output-format text)
  [[ -n "$tools" ]] && args+=(--allowedTools "$tools")

  claude "${args[@]}"
}
