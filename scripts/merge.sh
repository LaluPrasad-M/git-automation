#!/usr/bin/env bash
set -euo pipefail

_lib="$(dirname "${BASH_SOURCE[0]}")/lib.sh"
[[ -f "$_lib" ]] || { echo "lib.sh not found — ensure scripts/lib.sh is committed" >&2; exit 1; }
# shellcheck source=scripts/lib.sh
# shellcheck disable=SC1091
source "$_lib"

merge_method="$(read_policy 'merge.method')"
[[ -z "$merge_method" ]] && merge_method=squash
min_approvals="$(read_policy 'merge.min_approvals')"
[[ -z "$min_approvals" ]] && min_approvals=1
merge_enabled="$(read_policy 'merge.enabled')"
[[ -z "$merge_enabled" ]] && merge_enabled=true
require_ci_pass="$(read_policy 'merge.require_ci_pass')"
[[ -z "$require_ci_pass" ]] && require_ci_pass=true

if [[ "$merge_enabled" != "true" ]]; then
  echo "Merge skipped — merge is disabled in policy"
  exit 0
fi

if [[ "$require_ci_pass" != "true" ]]; then
  echo "Merge skipped — policy requires CI to pass before merging"
  exit 0
fi

poll_seconds=180
while true; do
  pr_json="$(gh pr view "$PR_NUMBER" --repo "$TARGET_REPO" --json reviews,reviewThreads,statusCheckRollup,mergeable,title,labels)"

  has_do_not_merge_label="$(jq '[.labels[]? | (.name // "") | ascii_downcase | select(. == "do-not-merge")] | length > 0' <<<"$pr_json")"
  if [[ "$has_do_not_merge_label" == "true" ]]; then
    echo "Merge skipped — PR has a do-not-merge label"
    exit 0
  fi

  unresolved="$(jq '[.reviewThreads[]? | select(.isResolved == false)] | length' <<<"$pr_json")"
  if [[ "$unresolved" -gt 0 ]]; then
    echo "Merge skipped — $unresolved unresolved review thread(s) must be resolved first"
    exit 0
  fi

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
    echo "CI still in progress — will recheck in 3 minutes"
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
    echo "Merge skipped — CI checks failed"
    exit 0
  fi

  break
done

approval_count="$(jq '[.reviews[]? | select(.state == "APPROVED") | .author.login] | unique | length' <<<"$pr_json")"
if [[ "$approval_count" -lt "$min_approvals" ]]; then
  echo "Merge skipped — not enough approvals ($approval_count of $min_approvals required)"
  exit 0
fi

mergeable="$(jq -r '.mergeable // "UNKNOWN"' <<<"$pr_json")"
if [[ "$mergeable" != "MERGEABLE" ]]; then
  echo "Merge skipped — PR is not in a mergeable state ($mergeable)"
  exit 0
fi

gh pr comment "$PR_NUMBER" --repo "$TARGET_REPO" --body "All checks passed. Merging automatically."
gh pr merge "$PR_NUMBER" --repo "$TARGET_REPO" --"$merge_method" --body "Auto-merged by Claude Git Sentinel"
