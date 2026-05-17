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
source "$_root/services/github/comment_service.sh"
# shellcheck disable=SC1091
source "$_root/services/github/review_service.sh"
# shellcheck disable=SC1091
source "$_root/services/github/graphql_service.sh"
# shellcheck disable=SC1091
source "$_root/services/ai/ai_service.sh"
# shellcheck disable=SC1091
source "$_root/services/ai/prompt_service.sh"

cd "$WORKSPACE"

required_checks_json="$(read_policy 'approve.required_checks')"

pr_json="$(gh_get_pr "$TARGET_REPO" "$PR_NUMBER" "statusCheckRollup")"

failures="$(jq -r '.statusCheckRollup[]? | select((.conclusion // .state) != "SUCCESS" and (.conclusion // .state) != "NEUTRAL" and (.conclusion // .state) != "SKIPPED") | .name' <<<"$pr_json")"
if [[ -n "$failures" ]]; then
  gh_post_pr_comment "$TARGET_REPO" "$PR_NUMBER" "Auto-approve blocked: some CI checks are not passing."
  exit 0
fi

owner="${TARGET_REPO%/*}"
repo_name="${TARGET_REPO#*/}"
threads_json="$(gh_get_pr_review_threads "$owner" "$repo_name" "$PR_NUMBER")"
open_sentinel_threads="$(jq -r --arg bot "$MY_GITHUB_USERNAME" '[
  .data.repository.pullRequest.reviewThreads.nodes[]?
  | select(.isResolved == false)
  | ([.comments.nodes[]? | select(.author.login == $bot and (.body | test("SENTINEL:FINDING")))] | length) as $botCount
  | select($botCount > 0)
] | length' <<<"$threads_json")"
if [[ "$open_sentinel_threads" -gt 0 ]]; then
  gh_post_pr_comment "$TARGET_REPO" "$PR_NUMBER" "Auto-approval deferred: $open_sentinel_threads unresolved sentinel review thread(s) remain."
  exit 0
fi

if [[ "$required_checks_json" != "null" && "$required_checks_json" != "[]" ]]; then
  while IFS= read -r chk; do
    [[ -z "$chk" ]] && continue
    found="$(jq -r --arg n "$chk" '.statusCheckRollup[]? | select(.name == $n) | .name' <<<"$pr_json" | head -n1)"
    if [[ -z "$found" ]]; then
      gh_post_pr_comment "$TARGET_REPO" "$PR_NUMBER" "Auto-approve blocked: required check '$chk' was not found."
      exit 0
    fi
  done < <(jq -r '.[]' <<<"$required_checks_json")
fi

prompt_root="$(resolve_control_path "$PROMPT_DIR")"
default_prompt_root="$GITHUB_WORKSPACE/config/prompts/defaults"

template_file="$prompt_root/approve/approve.md"
[[ ! -f "$template_file" ]] && template_file="$default_prompt_root/approve/approve.md"
prompt="$(cat "$template_file")"
prompt="${prompt//\{\{PR_NUMBER\}\}/$PR_NUMBER}"
prompt="${prompt//\{\{TARGET_REPO\}\}/$TARGET_REPO}"
prompt="${prompt//\{\{CI_STATUS\}\}/ALL PASSING}"

repo_skills_dir="$prompt_root/approve"
if [[ -d "$repo_skills_dir" ]]; then
  skill_manifest="$(build_skill_manifest "$repo_skills_dir" "approve.md")"
  if [[ -n "$skill_manifest" ]]; then
    prompt+=$'\n\n## Available Skill Files\n'
    prompt+="Read only the skill files relevant to the files changed in this PR. Use \`cat\` to read them from: $repo_skills_dir/"$'\n'
    prompt+="$skill_manifest"
  fi
fi

decision="$(call_llm "$prompt" "gh,git,cat,grep" 6 | tail -n 1)"
if grep -q "DECISION: APPROVE" <<<"$decision"; then
  gh_post_pr_review_approve "$TARGET_REPO" "$PR_NUMBER" "Auto-approved by Claude Git Sentinel after CI and quality checks."
elif grep -q "DECISION: COMMENT - " <<<"$decision"; then
  reason="${decision#DECISION: COMMENT - }"
  gh_post_pr_comment "$TARGET_REPO" "$PR_NUMBER" "Auto-approval deferred: $reason"
  gh_post_pr_comment "$TARGET_REPO" "$PR_NUMBER" "Please respond to these comments. Approval will be retried on subsequent events."
else
  reason="${decision#DECISION: BLOCK - }"
  gh_post_pr_comment "$TARGET_REPO" "$PR_NUMBER" "Auto-approve blocked: $reason"
fi
