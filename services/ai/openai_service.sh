#!/usr/bin/env bash
# OpenAI provider — stub implementation of call_llm().
# Required env: OPENAI_API_KEY, OPENAI_MODEL (default: gpt-4o)

call_llm() {
  local prompt="$1"
  # local tools="$2"    # tool filtering not yet implemented
  # local max_turns="$3"

  local model="${OPENAI_MODEL:-gpt-4o}"

  curl -fsSL https://api.openai.com/v1/chat/completions \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$(jq -nc --arg model "$model" --arg content "$prompt" \
      '{model:$model, messages:[{role:"user",content:$content}]}')" \
    | jq -r '.choices[0].message.content // empty'
}
