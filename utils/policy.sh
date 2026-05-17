#!/usr/bin/env bash
set -euo pipefail

_policy_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

_logging="$_policy_root/utils/logging.sh"
# shellcheck source=utils/logging.sh
# shellcheck disable=SC1091
source "$_logging"

read_policy() {
  local key="$1"
  local defaults="$_policy_root/config/sentinel.yml"
  local val=""
  if [[ -n "${POLICY_FILE:-}" && -f "$POLICY_FILE" ]]; then
    val="$(yq e ".$key // \"\"" "$POLICY_FILE" 2>/dev/null)"
  fi
  if [[ -z "$val" && "$POLICY_FILE" != "$defaults" ]]; then
    val="$(yq e ".$key // \"\"" "$defaults" 2>/dev/null)"
  fi
  echo "$val"
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
  [[ ! -f "$policy_file" ]] && policy_file="$_policy_root/config/sentinel.yml"
  [[ -f "$policy_file" ]] || { log ERROR "Policy file not found: $policy_file"; return 1; }
  policy_file="$(cd "$(dirname "$policy_file")" && pwd)/$(basename "$policy_file")"

  if [[ -n "${TARGET_REPOS:-}" ]]; then
    if ! _repo_in_allowlist "$target_repo" "$TARGET_REPOS"; then
      log ERROR "Repo $target_repo is not allow-listed in TARGET_REPOS"
      return 1
    fi
  fi

  log INFO "Using policy: $policy_file"

  {
    echo "target_repo=$target_repo"
    echo "policy_file=$policy_file"
  } >> "$GITHUB_OUTPUT"

  {
    echo "TARGET_REPO=$target_repo"
    echo "POLICY_FILE=$policy_file"
  } >> "$GITHUB_ENV"
}
