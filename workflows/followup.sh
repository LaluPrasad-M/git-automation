#!/usr/bin/env bash
set -euo pipefail

_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$_root/utils/logging.sh"
# shellcheck disable=SC1091
source "$_root/utils/policy.sh"
# shellcheck disable=SC1091
source "$_root/services/github/pr_service.sh"
# shellcheck disable=SC1091
source "$_root/services/github/review_service.sh"
# shellcheck disable=SC1091
source "$_root/services/github/graphql_service.sh"
# shellcheck disable=SC1091
source "$_root/services/ai/ai_service.sh"
# shellcheck disable=SC1091
source "$_root/services/ai/response_parser.sh"

trap 'log ERROR "followup.sh failed at line $LINENO (exit $?)"' ERR

[[ -n "${GITHUB_OUTPUT:-}" ]] || { log ERROR "followup.sh: GITHUB_OUTPUT is unset"; exit 1; }

owner="${TARGET_REPO%/*}"
repo_name="${TARGET_REPO#*/}"
bot_user="${MY_GITHUB_USERNAME:-}"
[[ -n "$bot_user" ]] || { log ERROR "MY_GITHUB_USERNAME is required"; exit 1; }

is_positive_reply() {
  local text="$1"
  local prior_nocasematch; prior_nocasematch="$(shopt -p nocasematch)"
  shopt -s nocasematch
  local result=1
  if [[ "$text" =~ (fixed|addressed|done|updated|resolved|implemented|pushed\ changes|added\ tests) ]] && \
     ! [[ "$text" =~ (won\'t|wont|cannot|can\'t|partial|later|defer|not\ fix|decline|won.?t\ fix) ]]; then
    result=0
  fi
  eval "$prior_nocasematch"
  return $result
}

record_exception() {
  local path="$1"
  local thread_id="$2"
  local rationale="$3"
  local learning="$4"

  local repo_slug="${TARGET_REPO//\//__}"
  local log_file="${SENTINEL_LOG:-${WORKSPACE:-.}/.state/logs/${repo_slug}.log}"
  mkdir -p "$(dirname "$log_file")"
  printf '[%s][EXCEPTION] pr=#%s path=%s rationale=%s learning=%s\n' \
    "$(date +'%Y-%m-%d %H:%M:%S')" "$PR_NUMBER" "$path" "$rationale" "$learning" \
    >> "$log_file"
}

already_approved="$(gh_get_pr "$TARGET_REPO" "$PR_NUMBER" "reviews" 2>/dev/null \
  | jq --arg me "$bot_user" \
    '[.reviews[]? | select(.author.login == $me and .state == "APPROVED")] | length > 0' \
  || echo false)"
if [[ "$already_approved" == "true" ]]; then
  log SKIP "Already approved by $bot_user — skipping follow-up"
  exit 0
fi

threads_json="$(gh_get_pr_review_threads "$owner" "$repo_name" "$PR_NUMBER")"

candidates="$(jq -c --arg bot "$bot_user" '
  .data.repository.pullRequest.reviewThreads.nodes[]?
  | select(.isResolved == false)
  | . as $t
  | ([ $t.comments.nodes[]? | select(.author.login == $bot and (.body | test("SENTINEL:FINDING"))) ]) as $botComments
  | select(($botComments | length) > 0)
  | .comments.nodes[-1] as $last
  | select($last.author.login != $bot)
  | {
      thread_id: .id,
      path: (.path // ""),
      latest_comment_id: ($last.databaseId // 0),
      latest_body: ($last.body // ""),
      latest_author: ($last.author.login // "unknown"),
      bot_comment_body: ($botComments[0].body // "")
    }
' <<<"$threads_json")"

if [[ -z "$candidates" ]]; then
  log SKIP "Nothing to follow up on — no unresolved review threads with replies"
  echo "remaining_sentinel_threads=0" >> "$GITHUB_OUTPUT"
  exit 0
fi

[[ -n "${GITHUB_ENV:-}" ]] || { log ERROR "followup.sh: GITHUB_ENV must be set before calling workspace_service"; exit 1; }
bash "$_root/services/git/workspace_service.sh"
_new_ws="$(grep '^WORKSPACE=' "${GITHUB_ENV:-/dev/null}" | tail -1 | cut -d= -f2-)"
[[ -n "$_new_ws" ]] && { export WORKSPACE="$_new_ws"; cd "$WORKSPACE"; }

base_ref="$(gh_get_pr "$TARGET_REPO" "$PR_NUMBER" "baseRefName" | jq -r '.baseRefName // empty')"
if [[ -z "$base_ref" ]]; then
  log ERROR "Unable to resolve base ref for ${TARGET_REPO}#${PR_NUMBER} — skipping follow-up"
  exit 1
fi
git fetch origin "$base_ref" >/dev/null 2>&1 || log WARN "Failed to fetch $base_ref for ${TARGET_REPO}#${PR_NUMBER} — diff context may be incomplete"

while IFS= read -r item; do
  [[ -z "$item" ]] && continue
  thread_id="$(jq -r '.thread_id' <<<"$item")"
  path="$(jq -r '.path' <<<"$item")"
  latest_comment_id="$(jq -r '.latest_comment_id' <<<"$item")"
  latest_body="$(jq -r '.latest_body' <<<"$item")"
  latest_author="$(jq -r '.latest_author' <<<"$item")"
  bot_comment_body="$(jq -r '.bot_comment_body' <<<"$item")"
  log INFO "Processing reply from $latest_author on $path"

  if is_positive_reply "$latest_body"; then
    file_diff="$(git diff --unified=0 "origin/$base_ref...HEAD" -- "$path" | head -c 12000)"
    verify_prompt="You are verifying whether a review finding is fixed.

Finding:
$bot_comment_body

Developer reply:
$latest_body

File path: $path
Diff excerpt:
$file_diff

Return ONLY JSON: {\"fixed\": true|false, \"reason\": \"...\"}."

    verify_raw="$(call_llm "$verify_prompt" "cat,grep")"
    if verify_json="$(extract_json_payload "$verify_raw")"; then
      fixed="$(jq -r '.fixed // false' <<<"$verify_json")"
      reason="$(jq -r '.reason // "No reason provided"' <<<"$verify_json")"
      if [[ "$fixed" == "true" ]]; then
        gh_resolve_review_thread "$thread_id"
      else
        gh_reply_to_review_comment "$TARGET_REPO" "$PR_NUMBER" "$latest_comment_id" "Thanks for the update. I re-checked this and it does not appear fully resolved yet: $reason"
      fi
    else
      gh_reply_to_review_comment "$TARGET_REPO" "$PR_NUMBER" "$latest_comment_id" "I could not verify this change automatically yet. Please share exact commit/file context for this thread."
    fi
  else
    validate_prompt="You are validating whether a non-fix reply is acceptable to close a review thread.

Finding:
$bot_comment_body

Developer reply:
$latest_body

Return ONLY JSON: {\"accepted\": true|false, \"reason\": \"...\", \"learning\": \"...\"}."

    validate_raw="$(call_llm "$validate_prompt" "cat,grep")"
    if validate_json="$(extract_json_payload "$validate_raw")"; then
      accepted="$(jq -r '.accepted // false' <<<"$validate_json")"
      reason="$(jq -r '.reason // "No reason provided"' <<<"$validate_json")"
      learning="$(jq -r '.learning // ""' <<<"$validate_json")"
      if [[ "$accepted" == "true" ]]; then
        record_exception "$path" "$thread_id" "$reason" "$learning"
        gh_resolve_review_thread "$thread_id"
      else
        gh_reply_to_review_comment "$TARGET_REPO" "$PR_NUMBER" "$latest_comment_id" "I reviewed the rationale and cannot close this yet: $reason"
      fi
    else
      gh_reply_to_review_comment "$TARGET_REPO" "$PR_NUMBER" "$latest_comment_id" "I could not evaluate this rationale automatically yet. Please provide more concrete technical context."
    fi
  fi
done <<< "$candidates"

threads_after="$(gh_get_pr_review_threads "$owner" "$repo_name" "$PR_NUMBER")"
remaining="$(jq -r --arg bot "$bot_user" '[
  .data.repository.pullRequest.reviewThreads.nodes[]?
  | select(.isResolved == false)
  | ([ .comments.nodes[]? | select(.author.login == $bot and (.body | test("SENTINEL:FINDING"))) ] | length) as $botCount
  | select($botCount > 0)
] | length' <<<"$threads_after")"

echo "remaining_sentinel_threads=$remaining" >> "$GITHUB_OUTPUT"
log INFO "Follow-up complete — $remaining unresolved review thread(s) remaining"
