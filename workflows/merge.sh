#!/usr/bin/env bash
set -euo pipefail

_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$_root/utils/logging.sh"
# shellcheck disable=SC1091
source "$_root/utils/policy.sh"

trap 'log ERROR "merge.sh failed at line $LINENO (exit $?)"' ERR
# shellcheck disable=SC1091
source "$_root/services/github/pr_service.sh"
# shellcheck disable=SC1091
source "$_root/services/github/comment_service.sh"
# shellcheck disable=SC1091
source "$_root/services/github/merge_service.sh"

log INFO "Starting merge workflow for $TARGET_REPO#$PR_NUMBER"
merge_method="$(read_policy 'merge.method')"
[[ -z "$merge_method" ]] && merge_method=squash
[[ "$merge_method" =~ ^(squash|merge|rebase)$ ]] || { log ERROR "Invalid merge.method: $merge_method"; exit 1; }
min_approvals="$(read_policy 'merge.min_approvals')"
[[ -z "$min_approvals" ]] && min_approvals=1
merge_enabled="$(read_policy 'merge.enabled')"
[[ -z "$merge_enabled" ]] && merge_enabled=true
require_ci_pass="$(read_policy 'merge.require_ci_pass')"
[[ -z "$require_ci_pass" ]] && require_ci_pass=true

if [[ "$merge_enabled" != "true" ]]; then
  log SKIP "Merge skipped — merge is disabled in policy"
  exit 0
fi

poll_seconds=180
max_polls="${MAX_MERGE_POLLS:-20}"
poll_count=0
while true; do
  poll_count=$(( poll_count + 1 ))
  if [[ "$poll_count" -gt "$max_polls" ]]; then
    log SKIP "Merge timed out after $max_polls polls (~$(( max_polls * poll_seconds / 60 )) minutes) — CI may be stuck"
    exit 0
  fi
  pr_json="$(gh_get_pr "$TARGET_REPO" "$PR_NUMBER" "reviews,reviewThreads,statusCheckRollup,mergeable,title,labels")"

  has_do_not_merge_label="$(jq '[.labels[]? | (.name // "") | ascii_downcase | select(. == "do-not-merge")] | length > 0' <<<"$pr_json")"
  if [[ "$has_do_not_merge_label" == "true" ]]; then
    log SKIP "Merge skipped — PR has a do-not-merge label"
    exit 0
  fi

  unresolved="$(jq '[.reviewThreads[]? | select(.isResolved == false)] | length' <<<"$pr_json")"
  if [[ "$unresolved" -gt 0 ]]; then
    log SKIP "Merge skipped — $unresolved unresolved review thread(s) must be resolved first"
    exit 0
  fi

  if [[ "$require_ci_pass" == "true" ]]; then
    ci_running="$(jq -r '
      .statusCheckRollup[]?
      | ((.conclusion // .state // "") | ascii_upcase) as $s
      | select(
          $s == "PENDING" or
          $s == "IN_PROGRESS" or
          $s == "QUEUED" or
          $s == "EXPECTED" or
          $s == "WAITING" or
          $s == "REQUESTED"
        )
      | (.name // "unknown-check")
    ' <<<"$pr_json")"
    if [[ -n "$ci_running" ]]; then
      log INFO "CI still in progress — will recheck in 3 minutes"
      sleep "$poll_seconds"
      continue
    fi

    ci_failed="$(jq -r '
      .statusCheckRollup[]?
      | ((.conclusion // .state // "") | ascii_upcase) as $s
      | select(
          $s != "SUCCESS" and
          $s != "NEUTRAL" and
          $s != "SKIPPED"
        )
      | (.name // "unknown-check")
    ' <<<"$pr_json")"
    if [[ -n "$ci_failed" ]]; then
      log SKIP "Merge skipped — CI checks failed"
      exit 0
    fi
  fi

  break
done

approval_count="$(jq '[.reviews[]? | select(.state == "APPROVED") | .author.login] | unique | length' <<<"$pr_json")"
if [[ "$approval_count" -lt "$min_approvals" ]]; then
  log SKIP "Merge skipped — not enough approvals ($approval_count of $min_approvals required)"
  exit 0
fi

mergeable="$(jq -r '.mergeable // "UNKNOWN"' <<<"$pr_json")"
if [[ "$mergeable" != "MERGEABLE" ]]; then
  log SKIP "Merge skipped — PR is not in a mergeable state ($mergeable)"
  exit 0
fi

gh_post_pr_comment "$TARGET_REPO" "$PR_NUMBER" "All checks passed. Merging automatically."
gh_merge_pr "$TARGET_REPO" "$PR_NUMBER" "$merge_method" "Auto-merged by Claude Git Sentinel"
log INFO "Merge complete for $TARGET_REPO#$PR_NUMBER (method=$merge_method)"
