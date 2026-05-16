#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 '<client_payload_json>'" >&2
  exit 2
fi

payload="$1"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
workspace="${WORKSPACE:-$repo_root}"

if [[ ! -d "$workspace" ]]; then
  if [[ -d "$repo_root" ]]; then
    workspace="$repo_root"
  elif [[ -d "/app" ]]; then
    workspace="/app"
  else
    echo "Valid WORKSPACE not found: $workspace" >&2
    exit 1
  fi
fi

export WORKSPACE="$workspace"
export GITHUB_WORKSPACE="${GITHUB_WORKSPACE:-$workspace}"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

classify_out="$tmp_dir/classify.out"
policy_out="$tmp_dir/policy.out"
guard_out="$tmp_dir/guard.out"
policy_env="$tmp_dir/policy.env"

export GITHUB_OUTPUT="$classify_out"
bash scripts/pipeline/classify.sh "$(jq -c '.client_payload // .' <<<"$payload")"

action="$(grep -E '^action=' "$classify_out" | tail -n1 | cut -d= -f2-)"
pr_number="$(grep -E '^pr_number=' "$classify_out" | tail -n1 | cut -d= -f2-)"
pr_author="$(grep -E '^pr_author=' "$classify_out" | tail -n1 | cut -d= -f2-)"
target_repo="$(grep -E '^target_repo=' "$classify_out" | tail -n1 | cut -d= -f2-)"
approved_by="$(grep -E '^approved_by=' "$classify_out" | tail -n1 | cut -d= -f2-)"

if [[ "$action" == "skip" ]]; then
  exit 0
fi

if [[ -z "$action" || "$action" == "unknown" ]]; then
  echo "Skipping — no actionable event (classified as: ${action:-empty})"
  exit 0
fi

export GITHUB_OUTPUT="$guard_out"
bash scripts/pipeline/guards.sh \
  --author "$pr_author" \
  --bot-user "${MY_GITHUB_USERNAME:-}" \
  --action "$action" \
  --pr-number "$pr_number" \
  --approved-by "$approved_by"

should_skip="$(grep -E '^should_skip=' "$guard_out" | tail -n1 | cut -d= -f2-)"
if [[ "$should_skip" == "true" ]]; then
  echo "Skipping $target_repo#$pr_number — guard blocked action=$action"
  exit 0
fi

if [[ "$action" == "review" || "$action" == "followup" ]]; then
  # shellcheck disable=SC2016
  _is_reviewer="$(gh pr view "$pr_number" --repo "$target_repo" --json reviewRequests \
    --jq --arg me "${MY_GITHUB_USERNAME:-}" \
    '[.reviewRequests[]? | select(.login == $me)] | length > 0' 2>/dev/null || echo false)"
  _author_whitelisted="false"
  if [[ -n "${AUTO_REVIEW_AUTHORS:-}" ]]; then
    IFS=',' read -ra _wl <<< "$AUTO_REVIEW_AUTHORS"
    for _a in "${_wl[@]}"; do
      [[ "$pr_author" == "${_a// /}" ]] && { _author_whitelisted="true"; break; }
    done
  fi
  if [[ "$_is_reviewer" != "true" && "$_author_whitelisted" != "true" ]]; then
    echo "Skipping $target_repo#$pr_number — not a reviewer and author not in whitelist"
    exit 0
  fi
fi

export GITHUB_OUTPUT="$policy_out"
export GITHUB_ENV="$policy_env"
bash scripts/pipeline/load-policy.sh "$target_repo"

policy_file="$(grep -E '^policy_file=' "$policy_out" | tail -n1 | cut -d= -f2-)"
prompt_dir="$(grep -E '^prompt_dir=' "$policy_out" | tail -n1 | cut -d= -f2-)"

export TARGET_REPO="$target_repo"
export POLICY_FILE="$policy_file"

enabled="true"
if [[ -f "$policy_file" ]]; then
  if [[ "$(yq e '.repo' "$policy_file" 2>/dev/null)" != "null" ]]; then
    enabled="$(yq e ".${action}.enabled // true" "$policy_file")"
  else
    enabled="$(yq e ".defaults.${action}.enabled // true" "$policy_file")"
  fi
fi
if [[ "$enabled" == "false" ]]; then
  echo "Skipping — $action is disabled in policy for $target_repo"
  exit 0
fi

export PR_NUMBER="$pr_number"
export PROMPT_DIR="$prompt_dir"

case "$action" in
  review)
    bash scripts/actions/review.sh
    ;;
  followup)
    bash scripts/actions/thread-followup.sh
    ;;
  approve)
    bash scripts/actions/approve.sh
    ;;
  merge)
    bash scripts/actions/merge.sh
    ;;
  *)
    echo "Unsupported action: $action"
    ;;
esac
