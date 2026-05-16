#!/usr/bin/env bash
set -euo pipefail
_lib="$(dirname "${BASH_SOURCE[0]}")/../shared/lib.sh"
# shellcheck source=scripts/shared/lib.sh
# shellcheck disable=SC1091
source "$_lib"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <owner/repo>" >&2
  exit 2
fi

repo_in_allowlist() {
  local repo="$1"
  local raw="$2"
  while IFS= read -r item; do
    item="${item#"${item%%[![:space:]]*}"}"
    item="${item%"${item##*[![:space:]]}"}"
    [[ -z "$item" ]] && continue
    [[ "$item" == "$repo" ]] && return 0
  done < <(tr ',' '\n' <<<"$raw")
  return 1
}

target_repo="$1"
listener_dir="git-listeners/${target_repo}"

policy_file="$listener_dir/policy.yml"
if [[ ! -f "$policy_file" ]]; then
  policy_file="config/sentinel.yml"
fi
policy_file="$(cd "$(dirname "$policy_file")" && pwd)/$(basename "$policy_file")"

prompt_dir="$listener_dir/prompts"
if [[ ! -d "$prompt_dir" ]]; then
  prompt_dir="config/prompts/defaults"
fi
prompt_dir="$(cd "$prompt_dir" && pwd)"

if [[ -n "${TARGET_REPOS:-}" ]]; then
  if ! repo_in_allowlist "$target_repo" "$TARGET_REPOS"; then
    log ERROR "Repo $target_repo is not allow-listed in TARGET_REPOS"
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

log INFO "Using policy: $policy_file | prompts: $prompt_dir"
