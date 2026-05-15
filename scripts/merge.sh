#!/usr/bin/env bash
set -euo pipefail

resolve_control_path() {
  local p="$1"
  if [[ "$p" = /* ]]; then
    echo "$p"
  else
    echo "$GITHUB_WORKSPACE/$p"
  fi
}

read_policy() {
  local key="$1"
  if yq e '.repo' "$POLICY_FILE" >/dev/null 2>&1; then
    yq e ".$key // \"\"" "$POLICY_FILE"
  else
    yq e ".defaults.$key // \"\"" "$POLICY_FILE"
  fi
}

merge_method="$(read_policy 'merge.method')"
[[ -z "$merge_method" ]] && merge_method=squash
min_approvals="$(read_policy 'merge.min_approvals')"
[[ -z "$min_approvals" ]] && min_approvals=1
merge_enabled="$(read_policy 'merge.enabled')"
[[ -z "$merge_enabled" ]] && merge_enabled=true
require_ci_pass="$(read_policy 'merge.require_ci_pass')"
[[ -z "$require_ci_pass" ]] && require_ci_pass=true

if [[ "$merge_enabled" != "true" ]]; then
  echo "Merge disabled by policy"
  exit 0
fi

if [[ "$require_ci_pass" != "true" ]]; then
  echo "Merge blocked: merge.require_ci_pass must be true"
  exit 0
fi

poll_seconds=180
while true; do
  pr_json="$(gh pr view "$PR_NUMBER" --repo "$TARGET_REPO" --json reviews,reviewThreads,statusCheckRollup,mergeable,title,labels)"

  has_do_not_merge_label="$(jq '[.labels[]? | (.name // "") | ascii_downcase | select(. == "do-not-merge")] | length > 0' <<<"$pr_json")"
  if [[ "$has_do_not_merge_label" == "true" ]]; then
    echo "PR has do-not-merge label"
    exit 0
  fi

  unresolved="$(jq '[.reviewThreads[]? | select(.isResolved == false)] | length' <<<"$pr_json")"
  if [[ "$unresolved" -gt 0 ]]; then
    echo "Open review comment threads present ($unresolved)"
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
    echo "CI still running; rechecking in 3 minutes"
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
    echo "CI failed"
    exit 0
  fi

  break
done

approval_count="$(jq '[.reviews[]? | select(.state == "APPROVED") | .author.login] | unique | length' <<<"$pr_json")"
if [[ "$approval_count" -lt "$min_approvals" ]]; then
  echo "Insufficient approvals ($approval_count/$min_approvals)"
  exit 0
fi

mergeable="$(jq -r '.mergeable // "UNKNOWN"' <<<"$pr_json")"
if [[ "$mergeable" != "MERGEABLE" ]]; then
  echo "PR not mergeable ($mergeable)"
  exit 0
fi

prompt_root="$(resolve_control_path "$PROMPT_DIR")"
default_prompt_root="$GITHUB_WORKSPACE/config/prompts/defaults"

template_file="$prompt_root/merge/merge.md"
[[ ! -f "$template_file" ]] && template_file="$prompt_root/merge.md"
[[ ! -f "$template_file" ]] && template_file="$default_prompt_root/merge/merge.md"
[[ ! -f "$template_file" ]] && template_file="$default_prompt_root/merge.md"
prompt="$(cat "$template_file")"
prompt="${prompt//\{\{PR_NUMBER\}\}/$PR_NUMBER}"
prompt="${prompt//\{\{TARGET_REPO\}\}/$TARGET_REPO}"
prompt="${prompt//\{\{APPROVAL_COUNT\}\}/$approval_count}"
prompt="${prompt//\{\{MIN_APPROVALS\}\}/$min_approvals}"
prompt="${prompt//\{\{CI_STATUS\}\}/ALL PASSING}"
prompt="${prompt//\{\{UNRESOLVED_THREADS\}\}/$unresolved}"
prompt="${prompt//\{\{MERGE_METHOD\}\}/$merge_method}"

skills_dir="$prompt_root/merge"
if [[ ! -d "$skills_dir" ]]; then
  skills_dir="$default_prompt_root/merge"
fi

skills_index_file="$skills_dir/index.md"
skills_file_list=""
if [[ -d "$skills_dir" ]]; then
  skills_file_list="$(find "$skills_dir" -maxdepth 1 -type f ! -name 'index.md' -exec basename {} \; | sort)"
fi

if [[ -f "$skills_index_file" || -n "$skills_file_list" ]]; then
  prompt+=$'\n\n## Optional Merge Skills\n'
  prompt+=$'You may choose any, all, or none of these skills based on relevance to this PR.\n'

  if [[ -f "$skills_index_file" ]]; then
    prompt+=$'\n### Skills Guidance\n'
    prompt+="$(cat "$skills_index_file")"
    prompt+=$'\n'
  fi

  if [[ -n "$skills_file_list" ]]; then
    prompt+=$'\n### Available Skill Files\n'
    while IFS= read -r skill_file; do
      [[ -z "$skill_file" ]] && continue
      prompt+="- $skill_file"
      prompt+=$'\n'
    done <<< "$skills_file_list"
  fi
fi

decision="$(claude -p "$prompt" --allowedTools "gh,git,cat,grep" --max-turns 4 --output-format text | tail -n 1)"
if grep -q "DECISION: MERGE" <<<"$decision"; then
  gh pr comment "$PR_NUMBER" --repo "$TARGET_REPO" --body "Merging PR automatically after policy checks."
  gh pr merge "$PR_NUMBER" --repo "$TARGET_REPO" --"$merge_method" --body "Auto-merged by Claude Git Sentinel"
else
  reason="${decision#DECISION: HOLD - }"
  gh pr comment "$PR_NUMBER" --repo "$TARGET_REPO" --body "Merge held: $reason"
fi
