#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <owner/repo>" >&2
  exit 2
fi

repo_in_allowlist() {
  local repo="$1"
  local raw="$2"

  if jq -e 'type == "array"' >/dev/null 2>&1 <<<"$raw"; then
    jq -e --arg repo "$repo" '.[] | select(. == $repo)' <<<"$raw" >/dev/null 2>&1
    return $?
  fi

  while IFS= read -r item; do
    item="${item#${item%%[![:space:]]*}}"
    item="${item%${item##*[![:space:]]}}"
    [[ -z "$item" ]] && continue
    if [[ "$item" == "$repo" ]]; then
      return 0
    fi
  done < <(tr ',' '\n' <<<"$raw")

  return 1
}

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
  if ! repo_in_allowlist "$target_repo" "$TARGET_REPOS_JSON"; then
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
