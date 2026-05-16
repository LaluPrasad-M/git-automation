#!/usr/bin/env bash
set -euo pipefail

_lib="$(dirname "${BASH_SOURCE[0]}")/../shared/lib.sh"
[[ -f "$_lib" ]] || { echo "lib.sh not found" >&2; exit 1; }
# shellcheck source=scripts/shared/lib.sh
# shellcheck disable=SC1091
source "$_lib"

trap 'log ERROR "thread-followup.sh failed at line $LINENO (exit $?)"' ERR

owner="${TARGET_REPO%/*}"
repo="${TARGET_REPO#*/}"
bot_user="${MY_GITHUB_USERNAME}"

extract_json_payload() {
  local raw="$1"
  if jq -e . >/dev/null 2>&1 <<<"$raw"; then
    printf '%s' "$raw"
    return 0
  fi

  local fenced
  fenced="$(printf '%s' "$raw" | awk '/```json/{flag=1;next}/```/{if(flag){flag=0;exit}}flag')"
  if [[ -n "$fenced" ]] && jq -e . >/dev/null 2>&1 <<<"$fenced"; then
    printf '%s' "$fenced"
    return 0
  fi

  return 1
}

is_positive_reply() {
  local text="$1"
  shopt -s nocasematch
  if [[ "$text" =~ (won\'t|wont|cannot|can\'t|partial|later|defer|not\ fix|decline|won.?t\ fix) ]]; then
    shopt -u nocasematch
    return 1
  fi

  if [[ "$text" =~ (fixed|addressed|done|updated|resolved|implemented|pushed\ changes|added\ tests) ]]; then
    shopt -u nocasematch
    return 0
  fi

  shopt -u nocasematch
  return 1
}

post_thread_reply() {
  local in_reply_to="$1"
  local body="$2"
  gh api "repos/$TARGET_REPO/pulls/$PR_NUMBER/comments" \
    -f body="$body" \
    -F in_reply_to="$in_reply_to" >/dev/null
}

resolve_thread() {
  local thread_id="$1"
  gh api graphql \
    -f query="mutation(\$threadId:ID!){resolveReviewThread(input:{threadId:\$threadId}){thread{id isResolved}}}" \
    -F threadId="$thread_id" >/dev/null
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

already_approved="$(gh pr view "$PR_NUMBER" --repo "$TARGET_REPO" --json reviews 2>/dev/null \
  | jq --arg me "$bot_user" \
    '[.reviews[]? | select(.author.login == $me and .state == "APPROVED")] | length > 0' \
  || echo false)"
if [[ "$already_approved" == "true" ]]; then
  log SKIP "Already approved by $bot_user — skipping follow-up"
  exit 0
fi

threads_query="query(\$owner:String!,\$name:String!,\$number:Int!){repository(owner:\$owner,name:\$name){pullRequest(number:\$number){reviewThreads(first:100){nodes{id isResolved path comments(first:50){nodes{id databaseId body author{login} createdAt}}}}}}}"
threads_json="$(gh api graphql -f query="$threads_query" -F owner="$owner" -F name="$repo" -F number="$PR_NUMBER")"

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

bash "$(dirname "${BASH_SOURCE[0]}")/../shared/setup-workspace.sh"
_new_ws="$(grep '^WORKSPACE=' "${GITHUB_ENV:-/dev/null}" | tail -1 | cut -d= -f2-)"
[[ -n "$_new_ws" ]] && { export WORKSPACE="$_new_ws"; cd "$WORKSPACE"; }

base_ref="$(gh pr view "$PR_NUMBER" --repo "$TARGET_REPO" --json baseRefName --jq '.baseRefName // empty')"
if [[ -z "$base_ref" ]]; then
  log ERROR "Unable to resolve base ref for ${TARGET_REPO}#${PR_NUMBER} — skipping follow-up" >&2
  exit 1
fi
git fetch origin "$base_ref" >/dev/null 2>&1 || true

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

    verify_raw="$(call_llm "$verify_prompt" "cat,grep" 4)"
    if verify_json="$(extract_json_payload "$verify_raw")"; then
      fixed="$(jq -r '.fixed // false' <<<"$verify_json")"
      reason="$(jq -r '.reason // "No reason provided"' <<<"$verify_json")"
      if [[ "$fixed" == "true" ]]; then
        resolve_thread "$thread_id"
      else
        post_thread_reply "$latest_comment_id" "Thanks for the update. I re-checked this and it does not appear fully resolved yet: $reason"
      fi
    else
      post_thread_reply "$latest_comment_id" "I could not verify this change automatically yet. Please share exact commit/file context for this thread."
    fi
  else
    validate_prompt="You are validating whether a non-fix reply is acceptable to close a review thread.

Finding:
$bot_comment_body

Developer reply:
$latest_body

Return ONLY JSON: {\"accepted\": true|false, \"reason\": \"...\", \"learning\": \"...\"}."

    validate_raw="$(call_llm "$validate_prompt" "cat,grep" 4)"
    if validate_json="$(extract_json_payload "$validate_raw")"; then
      accepted="$(jq -r '.accepted // false' <<<"$validate_json")"
      reason="$(jq -r '.reason // "No reason provided"' <<<"$validate_json")"
      learning="$(jq -r '.learning // ""' <<<"$validate_json")"
      if [[ "$accepted" == "true" ]]; then
        record_exception "$path" "$thread_id" "$reason" "$learning"
        resolve_thread "$thread_id"
      else
        post_thread_reply "$latest_comment_id" "I reviewed the rationale and cannot close this yet: $reason"
      fi
    else
      post_thread_reply "$latest_comment_id" "I could not evaluate this rationale automatically yet. Please provide more concrete technical context."
    fi
  fi
done <<< "$candidates"

threads_after="$(gh api graphql -f query="$threads_query" -F owner="$owner" -F name="$repo" -F number="$PR_NUMBER")"
remaining="$(jq -r --arg bot "$bot_user" '[
  .data.repository.pullRequest.reviewThreads.nodes[]?
  | select(.isResolved == false)
  | ([ .comments.nodes[]? | select(.author.login == $bot and (.body | test("SENTINEL:FINDING"))) ] | length) as $botCount
  | select($botCount > 0)
] | length' <<<"$threads_after")"

echo "remaining_sentinel_threads=$remaining" >> "$GITHUB_OUTPUT"
echo "Follow-up complete — $remaining unresolved review thread(s) remaining"
