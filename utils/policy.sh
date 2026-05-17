#!/usr/bin/env bash
set -euo pipefail

_logging="$(dirname "${BASH_SOURCE[0]}")/logging.sh"
# shellcheck source=utils/logging.sh
# shellcheck disable=SC1091
source "$_logging"

resolve_control_path() {
  local p="$1"
  if [[ "$p" = /* ]]; then
    echo "$p"
  else
    echo "$GITHUB_WORKSPACE/$p"
  fi
}

read_policy() {
  local key="$1"
  if [[ "$(yq e '.repo' "$POLICY_FILE" 2>/dev/null)" != "null" ]]; then
    yq e ".$key // \"\"" "$POLICY_FILE"
  else
    yq e ".defaults.$key // \"\"" "$POLICY_FILE"
  fi
}

_repo_in_allowlist() {
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

load_policy() {
  local target_repo="$1"
  [[ -n "${GITHUB_OUTPUT:-}" ]] || { log ERROR "load_policy: GITHUB_OUTPUT is unset"; return 1; }
  [[ -n "${GITHUB_ENV:-}" ]]    || { log ERROR "load_policy: GITHUB_ENV is unset"; return 1; }
  local listener_dir="git-listeners/${target_repo}"

  local policy_file="$listener_dir/policy.yml"
  if [[ ! -f "$policy_file" ]]; then
    policy_file="config/sentinel.yml"
  fi
  policy_file="$(cd "$(dirname "$policy_file")" && pwd)/$(basename "$policy_file")"

  local prompt_dir="$listener_dir/prompts"
  if [[ ! -d "$prompt_dir" ]]; then
    prompt_dir="config/prompts/defaults"
  fi
  prompt_dir="$(cd "$prompt_dir" && pwd)"

  if [[ -n "${TARGET_REPOS:-}" ]]; then
    if ! _repo_in_allowlist "$target_repo" "$TARGET_REPOS"; then
      log ERROR "Repo $target_repo is not allow-listed in TARGET_REPOS"
      return 1
    fi
  fi

  log INFO "Using policy: $policy_file | prompts: $prompt_dir"

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
}
