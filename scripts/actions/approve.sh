#!/usr/bin/env bash
set -euo pipefail

cd "$WORKSPACE"

_lib="$(dirname "${BASH_SOURCE[0]}")/../shared/lib.sh"
[[ -f "$_lib" ]] || { echo "lib.sh not found — ensure scripts/lib.sh is committed" >&2; exit 1; }
# shellcheck source=scripts/lib.sh
# shellcheck disable=SC1091
source "$_lib"

required_checks_json="$(read_policy 'approve.required_checks')"

pr_json="$(gh pr view "$PR_NUMBER" --repo "$TARGET_REPO" --json statusCheckRollup)"

failures="$(jq -r '.statusCheckRollup[]? | select((.conclusion // .state) != "SUCCESS" and (.conclusion // .state) != "NEUTRAL" and (.conclusion // .state) != "SKIPPED") | .name' <<<"$pr_json")"
if [[ -n "$failures" ]]; then
  gh pr comment "$PR_NUMBER" --repo "$TARGET_REPO" --body "Auto-approve blocked: some CI checks are not passing."
  exit 0
fi

owner="${TARGET_REPO%/*}"
repo="${TARGET_REPO#*/}"
threads_query="query(\$owner:String!,\$name:String!,\$number:Int!){repository(owner:\$owner,name:\$name){pullRequest(number:\$number){reviewThreads(first:100){nodes{isResolved comments(first:50){nodes{body author{login}}}}}}}}"
threads_json="$(gh api graphql -f query="$threads_query" -F owner="$owner" -F name="$repo" -F number="$PR_NUMBER")"
open_sentinel_threads="$(jq -r --arg bot "$MY_GITHUB_USERNAME" '[
  .data.repository.pullRequest.reviewThreads.nodes[]?
  | select(.isResolved == false)
  | ([.comments.nodes[]? | select(.author.login == $bot and (.body | test("SENTINEL:FINDING")))] | length) as $botCount
  | select($botCount > 0)
] | length' <<<"$threads_json")"
if [[ "$open_sentinel_threads" -gt 0 ]]; then
  gh pr comment "$PR_NUMBER" --repo "$TARGET_REPO" --body "Auto-approval deferred: $open_sentinel_threads unresolved sentinel review thread(s) remain."
  exit 0
fi

if [[ "$required_checks_json" != "null" && "$required_checks_json" != "[]" ]]; then
  while IFS= read -r chk; do
    [[ -z "$chk" ]] && continue
    found="$(jq -r --arg n "$chk" '.statusCheckRollup[]? | select(.name == $n) | .name' <<<"$pr_json" | head -n1)"
    if [[ -z "$found" ]]; then
      gh pr comment "$PR_NUMBER" --repo "$TARGET_REPO" --body "Auto-approve blocked: required check '$chk' was not found."
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
  skill_manifest=""
  while IFS= read -r skill_file; do
    [[ -z "$skill_file" ]] && continue
    skill_name="$(basename "$skill_file")"
    description="$(sed -n 's/^description:[[:space:]]*//p' "$skill_file" | head -1 | tr -d '"')"
    [[ -z "$description" ]] && description="$skill_name"
    skill_manifest+="- $skill_name: $description"$'\n'
  done < <(find "$repo_skills_dir" -maxdepth 1 -type f ! -name 'approve.md' | sort)

  if [[ -n "$skill_manifest" ]]; then
    prompt+=$'\n\n## Available Skill Files\n'
    prompt+="Read only the skill files relevant to the files changed in this PR. Use \`cat\` to read them from: $repo_skills_dir/"$'\n'
    prompt+="$skill_manifest"
  fi
fi

decision="$(call_llm "$prompt" "gh,git,cat,grep" 6 | tail -n 1)"
if grep -q "DECISION: APPROVE" <<<"$decision"; then
  gh pr review "$PR_NUMBER" --repo "$TARGET_REPO" --approve --body "Auto-approved by Claude Git Sentinel after CI and quality checks."
elif grep -q "DECISION: COMMENT - " <<<"$decision"; then
  reason="${decision#DECISION: COMMENT - }"
  gh pr comment "$PR_NUMBER" --repo "$TARGET_REPO" --body "Auto-approval deferred: $reason"
  gh pr comment "$PR_NUMBER" --repo "$TARGET_REPO" --body "Please respond to these comments. Approval will be retried on subsequent events."
else
  reason="${decision#DECISION: BLOCK - }"
  gh pr comment "$PR_NUMBER" --repo "$TARGET_REPO" --body "Auto-approve blocked: $reason"
fi
