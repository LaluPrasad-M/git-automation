#!/usr/bin/env bash
set -euo pipefail

_lib="$(dirname "${BASH_SOURCE[0]}")/../shared/lib.sh"
[[ -f "$_lib" ]] || { echo "lib.sh not found — ensure scripts/shared/lib.sh is committed" >&2; exit 1; }
# shellcheck source=scripts/lib.sh
# shellcheck disable=SC1091
source "$_lib"

# shellcheck disable=SC2016
is_reviewer="$(gh pr view "$PR_NUMBER" --repo "$TARGET_REPO" --json reviewRequests \
  --jq --arg me "${MY_GITHUB_USERNAME:-}" '[.reviewRequests[]? | select(.login == $me)] | length > 0')"

pr_author="$(gh pr view "$PR_NUMBER" --repo "$TARGET_REPO" --json author --jq '.author.login')"
author_whitelisted="false"
if [[ -n "${AUTO_REVIEW_AUTHORS:-}" ]]; then
  IFS=',' read -ra _authors <<< "$AUTO_REVIEW_AUTHORS"
  for _a in "${_authors[@]}"; do
    if [[ "$pr_author" == "${_a// /}" ]]; then
      author_whitelisted="true"
      break
    fi
  done
fi

is_own_pr="false"
[[ -n "${MY_GITHUB_USERNAME:-}" && "$pr_author" == "$MY_GITHUB_USERNAME" ]] && is_own_pr="true"

if [[ "$is_own_pr" != "true" && "$is_reviewer" != "true" && "$author_whitelisted" != "true" ]]; then
  log SKIP "Not a requested reviewer and PR author not in AUTO_REVIEW_AUTHORS — skipping"
  exit 0
fi

already_approved="$(gh pr view "$PR_NUMBER" --repo "$TARGET_REPO" --json reviews \
  --jq --arg me "${MY_GITHUB_USERNAME:-}" \
  '[.reviews[]? | select(.author.login == $me and .state == "APPROVED")] | length > 0' 2>/dev/null || echo false)"
if [[ "$already_approved" == "true" ]]; then
  log SKIP "Already approved by ${MY_GITHUB_USERNAME} — skipping review"
  exit 0
fi

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

severity_label() {
  case "$1" in
    critical) echo "Critical" ;;
    major) echo "Major" ;;
    minor) echo "Minor" ;;
    nit) echo "Nit" ;;
    *) echo "Minor" ;;
  esac
}

bash "$(dirname "${BASH_SOURCE[0]}")/../shared/setup-workspace.sh"
_new_ws="$(grep '^WORKSPACE=' "${GITHUB_ENV:-/dev/null}" | tail -1 | cut -d= -f2-)"
[[ -n "$_new_ws" ]] && { export WORKSPACE="$_new_ws"; cd "$WORKSPACE"; }

max_diff_lines="$(read_policy 'review.max_diff_lines')"
[[ -z "$max_diff_lines" ]] && max_diff_lines=2500

diff_output="$(gh pr diff "$PR_NUMBER" --repo "$TARGET_REPO" 2>&1)" || {
  gh pr comment "$PR_NUMBER" --repo "$TARGET_REPO" --body "Auto-review skipped: unable to fetch PR diff."
  exit 0
}
diff_lines="$(wc -l <<<"$diff_output" | tr -d ' ')"
if [[ "$diff_lines" -gt "$max_diff_lines" ]]; then
  gh pr comment "$PR_NUMBER" --repo "$TARGET_REPO" --body "This PR has $diff_lines diff lines which exceeds the auto-review limit of $max_diff_lines. Please split it into smaller focused PRs so each can be reviewed effectively."
  exit 0
fi

pr_json="$(gh pr view "$PR_NUMBER" --repo "$TARGET_REPO" --json title,author,additions,deletions,changedFiles)"
pr_title="$(jq -r '.title' <<<"$pr_json")"
pr_author="$(jq -r '.author.login' <<<"$pr_json")"
files_changed="$(jq -r '.changedFiles' <<<"$pr_json")"
lines_added="$(jq -r '.additions' <<<"$pr_json")"
lines_removed="$(jq -r '.deletions' <<<"$pr_json")"

prompt_root="$(resolve_control_path "$PROMPT_DIR")"
default_prompt_root="$GITHUB_WORKSPACE/config/prompts/defaults"

template_file="$prompt_root/review/review.md"
[[ ! -f "$template_file" ]] && template_file="$default_prompt_root/review/review.md"

prompt="$(cat "$template_file")"
prompt="${prompt//\{\{PR_NUMBER\}\}/$PR_NUMBER}"
prompt="${prompt//\{\{TARGET_REPO\}\}/$TARGET_REPO}"
prompt="${prompt//\{\{PR_TITLE\}\}/$pr_title}"
prompt="${prompt//\{\{PR_AUTHOR\}\}/$pr_author}"
prompt="${prompt//\{\{FILES_CHANGED\}\}/$files_changed}"
prompt="${prompt//\{\{LINES_ADDED\}\}/$lines_added}"
prompt="${prompt//\{\{LINES_REMOVED\}\}/$lines_removed}"

repo_skills_dir="$prompt_root/review"
if [[ -d "$repo_skills_dir" ]]; then
  skill_manifest=""
  while IFS= read -r skill_file; do
    [[ -z "$skill_file" ]] && continue
    skill_name="$(basename "$skill_file")"
    description="$(sed -n 's/^description:[[:space:]]*//p' "$skill_file" | head -1 | tr -d '"')"
    [[ -z "$description" ]] && description="$skill_name"
    skill_manifest+="- $skill_name: $description"$'\n'
  done < <(find "$repo_skills_dir" -maxdepth 1 -type f ! -name 'review.md' | sort)

  if [[ -n "$skill_manifest" ]]; then
    prompt+=$'\n\n## Available Skill Files\n'
    prompt+="Read only the skill files relevant to the files changed in this PR. Use \`cat\` to read them from: $repo_skills_dir/"$'\n'
    prompt+="$skill_manifest"
  fi
fi

prompt+=$'\n\n## Response Format (Mandatory)\n'
prompt+=$'Return ONLY valid JSON. Do not run gh commands directly.\n'
prompt+=$'JSON schema:\n'
prompt+=$'{\n'
prompt+=$'  "summary": "string",\n'
prompt+=$'  "verdict": "APPROVE_READY|NEEDS_CHANGES|NEEDS_DISCUSSION",\n'
prompt+=$'  "test_gaps": ["string"],\n'
prompt+=$'  "findings": [\n'
prompt+=$'    {"severity":"critical|major|minor|nit","path":"string","line":1,"title":"string","details":"string","recommendation":"string"}\n'
prompt+=$'  ]\n'
prompt+=$'}\n'

raw_output="$(call_llm "$prompt" "gh,git,cat,grep,find,head,tail,wc" 10)"
printf '%s\n' "$raw_output" > /tmp/claude-review-output.txt

if ! review_json="$(extract_json_payload "$raw_output")"; then
  gh pr comment "$PR_NUMBER" --repo "$TARGET_REPO" --body "Review parsing fallback: unable to parse structured output.\n\n${raw_output:0:6000}"
  exit 0
fi

head_sha="$(gh pr view "$PR_NUMBER" --repo "$TARGET_REPO" --json headRefOid --jq '.headRefOid // empty')"
if [[ -z "$head_sha" ]]; then
  gh pr comment "$PR_NUMBER" --repo "$TARGET_REPO" --body "Review complete but could not post inline comments: unable to resolve PR head SHA."
  exit 0
fi
summary="$(jq -r '.summary // "No summary provided."' <<<"$review_json")"
verdict="$(jq -r '.verdict // "NEEDS_DISCUSSION"' <<<"$review_json")"
test_gaps="$(jq -r '.test_gaps // [] | if length == 0 then "none" else join("; ") end' <<<"$review_json")"
critical_count="$(jq -r '[.findings[]? | select(.severity == "critical")] | length' <<<"$review_json")"
major_count="$(jq -r '[.findings[]? | select(.severity == "major")] | length' <<<"$review_json")"
minor_count="$(jq -r '[.findings[]? | select(.severity == "minor")] | length' <<<"$review_json")"
nit_count="$(jq -r '[.findings[]? | select(.severity == "nit")] | length' <<<"$review_json")"

fallback_findings=""
finding_count="$(jq '.findings // [] | length' <<<"$review_json")"
if [[ "$finding_count" -gt 0 ]]; then
  while IFS= read -r finding; do
    severity="$(jq -r '.severity // "minor"' <<<"$finding")"
    path="$(jq -r '.path // ""' <<<"$finding")"
    line="$(jq -r '.line // 0' <<<"$finding")"
    title="$(jq -r '.title // "Untitled finding"' <<<"$finding")"
    details="$(jq -r '.details // ""' <<<"$finding")"
    recommendation="$(jq -r '.recommendation // ""' <<<"$finding")"

    finding_seed="$path|$line|$title|$severity"
    finding_id="$(printf '%s' "$finding_seed" | shasum | awk '{print $1}' | cut -c1-12)"

    severity_text="$(severity_label "$severity")"
    body="$(printf 'Review Comment(Severity:%s)\n%s\n\n%s\n\n<!-- SENTINEL:FINDING id=%s severity=%s -->' \
      "$severity_text" "$title" "$details" "$finding_id" "$severity")"
    if [[ -n "$recommendation" && "$recommendation" != "null" ]]; then
      body+=$'\n\nRecommendation: '"$recommendation"
    fi

    if [[ -n "$path" && "$path" != "null" && "$line" =~ ^[0-9]+$ && "$line" -gt 0 ]]; then
      if ! gh api "repos/$TARGET_REPO/pulls/$PR_NUMBER/comments" \
        -f body="$body" \
        -f commit_id="$head_sha" \
        -f path="$path" \
        -F line="$line" \
        -f side="RIGHT" >/dev/null 2>&1; then
        fallback_findings+="$(printf '- [%s] %s:%s - %s\n' "$severity" "$path" "$line" "$title")"
      fi
    else
      fallback_findings+="$(printf '- [%s] %s\n' "$severity" "$title")"
    fi
  done < <(jq -c '.findings // [] | .[]' <<<"$review_json")
fi

summary_body="$(printf 'Review summary: %s\n\nVerdict: %s\nTest gaps: %s' "$summary" "$verdict" "$test_gaps")"
if [[ -n "$fallback_findings" ]]; then
  summary_body+="$(printf '\n\nNon-inline findings (fallback):\n%s' "$fallback_findings")"
fi

summary_body+="$(printf '\n\nCounts: critical=%s, major=%s, minor=%s, nit=%s' "$critical_count" "$major_count" "$minor_count" "$nit_count")"

summary_severity="nit"
if [[ "$critical_count" -gt 0 ]]; then
  summary_severity="critical"
elif [[ "$major_count" -gt 0 ]]; then
  summary_severity="major"
elif [[ "$minor_count" -gt 0 ]]; then
  summary_severity="minor"
fi
summary_severity_text="$(severity_label "$summary_severity")"
summary_body="$(printf 'Review Comment(Severity:%s)\n%s' "$summary_severity_text" "$summary_body")"

if [[ "$critical_count" -gt 0 ]]; then
  if [[ "$is_own_pr" == "true" ]]; then
    gh pr comment "$PR_NUMBER" --repo "$TARGET_REPO" --body "$summary_body"
  else
    gh pr review "$PR_NUMBER" --repo "$TARGET_REPO" --request-changes --body "$summary_body"
  fi
elif [[ "$major_count" -gt 0 || "$is_own_pr" == "true" ]]; then
  gh pr comment "$PR_NUMBER" --repo "$TARGET_REPO" --body "$summary_body"
else
  gh pr review "$PR_NUMBER" --repo "$TARGET_REPO" --approve --body "$summary_body"
fi
