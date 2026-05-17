#!/usr/bin/env bash
set -euo pipefail

_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=utils/logging.sh
# shellcheck disable=SC1091
source "$_root/utils/logging.sh"
# shellcheck source=utils/authors.sh
# shellcheck disable=SC1091
source "$_root/utils/authors.sh"
# shellcheck source=utils/policy.sh
# shellcheck disable=SC1091
source "$_root/utils/policy.sh"
# shellcheck source=services/github/pr_service.sh
# shellcheck disable=SC1091
source "$_root/services/github/pr_service.sh"

trap 'log ERROR "dispatch.sh failed at line $LINENO (exit $?)"' ERR

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 '<client_payload_json>'" >&2
  exit 2
fi

payload="$1"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
workspace="${WORKSPACE:-$_root}"

if [[ ! -d "$workspace" ]]; then
  if [[ -d "$_root" ]]; then
    workspace="$_root"
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
guard_out="$tmp_dir/guard.out"
policy_env="$tmp_dir/policy.env"

jq -e '.' <<<"$payload" >/dev/null 2>&1 || { log ERROR "Malformed payload JSON"; exit 1; }

export GITHUB_OUTPUT="$classify_out"
bash "$script_dir/classify.sh" "$(jq -c '.client_payload // .' <<<"$payload")"

action="$(grep -E '^action=' "$classify_out" | tail -n1 | cut -d= -f2-)"
pr_number="$(grep -E '^pr_number=' "$classify_out" | tail -n1 | cut -d= -f2-)"
pr_author="$(grep -E '^pr_author=' "$classify_out" | tail -n1 | cut -d= -f2-)"
target_repo="$(grep -E '^target_repo=' "$classify_out" | tail -n1 | cut -d= -f2-)"
approved_by="$(grep -E '^approved_by=' "$classify_out" | tail -n1 | cut -d= -f2-)"
event_type="$(jq -r '.event_type // .client_payload.event_type // "unknown"' <<<"$payload")"

if [[ "$action" == "skip" ]]; then
  log SKIP "$target_repo#$pr_number — PR is not open, skipping dispatch"
  exit 0
fi

if [[ -z "$action" || "$action" == "unknown" ]]; then
  log SKIP "No actionable event (event: $event_type)"
  exit 0
fi

export GITHUB_OUTPUT="$guard_out"
bash "$_root/utils/guards.sh" \
  --author "$pr_author" \
  --bot-user "${MY_GITHUB_USERNAME:-}" \
  --action "$action" \
  --pr-number "$pr_number" \
  --approved-by "$approved_by"

should_skip="$(grep -E '^should_skip=' "$guard_out" | tail -n1 | cut -d= -f2-)"
if [[ "$should_skip" == "true" ]]; then
  log SKIP "$target_repo#$pr_number — guard blocked action=$action"
  exit 0
fi

if [[ "$action" == "review" || "$action" == "followup" ]]; then
  # Own PRs bypass the reviewer check — review was triggered by creation, not assignment
  if [[ -n "${MY_GITHUB_USERNAME:-}" && "$pr_author" == "$MY_GITHUB_USERNAME" ]]; then
    : # allowed — own PR review
  else
    # shellcheck disable=SC2016
    _is_reviewer="$(gh_get_pr "$target_repo" "$pr_number" "reviewRequests" 2>/dev/null \
      | jq --arg me "${MY_GITHUB_USERNAME:-}" \
        '[.reviewRequests[]? | select(.login == $me)] | length > 0' \
      || echo false)"
    _author_whitelisted="false"
    if [[ -n "${AUTO_REVIEW_AUTHORS:-}" ]]; then
      is_auto_review_author_for_repo "$target_repo" "$pr_author" "$AUTO_REVIEW_AUTHORS" && _author_whitelisted="true"
    fi
    if [[ "$_is_reviewer" != "true" && "$_author_whitelisted" != "true" ]]; then
      log SKIP "$target_repo#$pr_number — not a reviewer and author not in whitelist"
      exit 0
    fi
  fi
fi

export GITHUB_OUTPUT="$tmp_dir/policy.out"
export GITHUB_ENV="$policy_env"
load_policy "$target_repo" || { log ERROR "Policy load failed for $target_repo"; exit 1; }

policy_file="$(grep -E '^policy_file=' "$tmp_dir/policy.out" | tail -n1 | cut -d= -f2-)"

export TARGET_REPO="$target_repo"
export POLICY_FILE="$policy_file"

enabled="$(yq e ".${action}.enabled // true" "$policy_file" 2>/dev/null || echo true)"
if [[ "$enabled" == "false" ]]; then
  log SKIP "$action is disabled in policy for $target_repo"
  exit 0
fi

export PR_NUMBER="$pr_number"

case "$action" in
  review)   bash "$script_dir/review.sh" ;;
  followup) bash "$script_dir/followup.sh" ;;
  approve)  bash "$script_dir/approve.sh" ;;
  merge)    bash "$script_dir/merge.sh" ;;
  *)        log WARN "Unsupported action: $action" ;;
esac
