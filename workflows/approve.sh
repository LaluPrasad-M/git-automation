#!/usr/bin/env bash
set -euo pipefail

_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$_root/utils/logging.sh"
# shellcheck disable=SC1091
source "$_root/utils/policy.sh"

trap 'log ERROR "approve.sh failed at line $LINENO (exit $?)"' ERR
# shellcheck disable=SC1091
source "$_root/services/github/pr_service.sh"
# shellcheck disable=SC1091
source "$_root/services/github/comment_service.sh"
# shellcheck disable=SC1091
source "$_root/services/github/review_service.sh"
# shellcheck disable=SC1091
source "$_root/services/github/graphql_service.sh"
# shellcheck disable=SC1091
source "$_root/services/ai/ai_service.sh"

log INFO "Starting approve workflow for $TARGET_REPO#$PR_NUMBER"
[[ -d "${WORKSPACE:-}" ]] || { log ERROR "WORKSPACE is not set or invalid"; exit 1; }
cd "$WORKSPACE"

required_checks_json="$(read_policy 'approve.required_checks')"

pr_meta="$(gh_get_pr "$TARGET_REPO" "$PR_NUMBER" "statusCheckRollup,author")"
pr_author="$(jq -r '.author.login // empty' <<<"$pr_meta")"
if [[ -n "${MY_GITHUB_USERNAME:-}" && "$pr_author" == "$MY_GITHUB_USERNAME" ]]; then
  log SKIP "Own PR — GitHub blocks self-approval, skipping approve workflow"
  exit 0
fi

failures="$(jq -r '.statusCheckRollup[]? | select((.conclusion // .state) != "SUCCESS" and (.conclusion // .state) != "NEUTRAL" and (.conclusion // .state) != "SKIPPED") | .name' <<<"$pr_meta")"
if [[ -n "$failures" ]]; then
  log SKIP "Approve blocked — CI failures: $failures"
  gh_post_pr_comment "$TARGET_REPO" "$PR_NUMBER" "Holding off on approval — some CI checks are still failing. I'll retry once they're green."
  exit 0
fi

ci_checks="$(jq -r '[.statusCheckRollup[]? | select((.conclusion // .state) == "SUCCESS") | .name] | join(", ")' <<<"$pr_meta")"
[[ -z "$ci_checks" ]] && ci_checks="ALL PASSING"

owner="${TARGET_REPO%/*}"
repo_name="${TARGET_REPO#*/}"
threads_json="$(gh_get_pr_review_threads "$owner" "$repo_name" "$PR_NUMBER")"
open_sentinel_threads="$(jq -r --arg bot "${MY_GITHUB_USERNAME:-}" '[
  .data.repository.pullRequest.reviewThreads.nodes[]?
  | select(.isResolved == false)
  | ([.comments.nodes[]? | select(.author.login == $bot and (.body | test("SENTINEL:FINDING")))] | length) as $botCount
  | select($botCount > 0)
] | length' <<<"$threads_json")"
if [[ "$open_sentinel_threads" -gt 0 ]]; then
  gh_post_pr_comment "$TARGET_REPO" "$PR_NUMBER" "There are still $open_sentinel_threads unresolved review thread(s) — resolve those first and I'll take another look."
  exit 0
fi

if [[ "$required_checks_json" != "null" && "$required_checks_json" != "[]" ]]; then
  while IFS= read -r chk; do
    [[ -z "$chk" ]] && continue
    found="$(jq -r --arg n "$chk" '.statusCheckRollup[]? | select(.name == $n) | .name' <<<"$pr_meta" | head -n1)"
    if [[ -z "$found" ]]; then
      gh_post_pr_comment "$TARGET_REPO" "$PR_NUMBER" "Required check \`$chk\` wasn't found in the CI results — can't approve yet."
      exit 0
    fi
  done < <(jq -r '.[]' <<<"$required_checks_json")
fi

_sentinel_root="${GITHUB_WORKSPACE:-$_root}"
template_file="$_sentinel_root/config/prompts/approve/template/approve.md"
[[ -f "$template_file" ]] || { log ERROR "Approve template not found: $template_file"; exit 1; }
prompt="$(cat "$template_file")"
prompt="${prompt//\{\{PR_NUMBER\}\}/$PR_NUMBER}"
prompt="${prompt//\{\{TARGET_REPO\}\}/$TARGET_REPO}"
prompt="${prompt//\{\{CI_STATUS\}\}/$ci_checks}"

log INFO "Calling LLM for approval decision on $TARGET_REPO#$PR_NUMBER"
_llm_out="$(call_llm "$prompt" "gh,cat,grep")" || true
if [[ -z "$_llm_out" ]]; then
  log WARN "LLM returned empty output — skipping approval"
  gh_post_pr_comment "$TARGET_REPO" "$PR_NUMBER" "Ran into an issue — got no response from the LLM. Will retry on the next event."
  exit 0
fi
decision="$(grep 'DECISION:' <<<"$_llm_out" | tail -n 1 || true)"
log INFO "LLM decision: $decision"
if [[ -z "$decision" ]]; then
  log WARN "LLM output contained no DECISION line — skipping approval"
  gh_post_pr_comment "$TARGET_REPO" "$PR_NUMBER" "Something went wrong — couldn't parse a decision from the review. Will retry on the next event."
  exit 0
fi
if grep -q "DECISION: APPROVE" <<<"$decision"; then
  gh_post_pr_review_approve "$TARGET_REPO" "$PR_NUMBER" "Looks good — CI is passing and review threads are resolved. Approving."
elif grep -q "DECISION: COMMENT - " <<<"$decision"; then
  reason="${decision#DECISION: COMMENT - }"
  gh_post_pr_comment "$TARGET_REPO" "$PR_NUMBER" "Not quite ready to approve: $reason"$'\n\n'"Once you've addressed the above, I'll take another look on your next push."
else
  reason="${decision#DECISION: BLOCK - }"
  log WARN "LLM blocked approval for $TARGET_REPO#$PR_NUMBER: $reason"
  gh_post_pr_comment "$TARGET_REPO" "$PR_NUMBER" "Blocking this one: $reason"
fi
