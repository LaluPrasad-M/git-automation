#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <owner/repo>" >&2
  exit 2
fi

target_repo="$1"
repo_slug="${target_repo//\//-}"

policy_file="config/repos/${repo_slug}.yml"
if [[ ! -f "$policy_file" ]]; then
  policy_file="config/sentinel.yml"
fi

# Exact match first: config/prompts/repos/<owner>/<repo>
prompt_dir="config/prompts/repos/${target_repo}"
if [[ ! -d "$prompt_dir" ]]; then
  prompt_dir="config/prompts/defaults"
fi

if [[ -n "${TARGET_REPOS_JSON:-}" ]]; then
  if ! jq -e --arg repo "$target_repo" '.[] | select(. == $repo)' <<<"$TARGET_REPOS_JSON" >/dev/null 2>&1; then
    echo "::error::Repo $target_repo is not allow-listed in TARGET_REPOS_JSON"
    exit 1
  fi
fi

{
  echo "target_repo=$target_repo"
  echo "policy_file=$policy_file"
  echo "prompt_dir=$prompt_dir"
} >> "$GITHUB_OUTPUT"

{
  echo "TARGET_REPO=$target_repo"
  echo "POLICY_FILE=$policy_file"
  echo "PROMPT_DIR=$prompt_dir"
} >> "$GITHUB_ENV"

echo "::notice::Policy resolved: $policy_file | prompts: $prompt_dir"
