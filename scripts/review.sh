#!/usr/bin/env bash
set -euo pipefail

cd "$WORKSPACE"

_lib="$(dirname "${BASH_SOURCE[0]}")/lib.sh"
[[ -f "$_lib" ]] || { echo "lib.sh not found — ensure scripts/lib.sh is committed" >&2; exit 1; }
# shellcheck source=lib.sh
source "$_lib"

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

max_diff_lines="$(read_policy 'review.max_diff_lines')"
[[ -z "$max_diff_lines" ]] && max_diff_lines=5000

diff_lines="$(gh pr diff "$PR_NUMBER" --repo "$TARGET_REPO" | wc -l | tr -d ' ')"
if [[ "$diff_lines" -gt "$max_diff_lines" ]]; then
  gh pr comment "$PR_NUMBER" --repo "$TARGET_REPO" --body "Warning: PR has $diff_lines diff lines, above auto-review limit $max_diff_lines."
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
[[ ! -f "$template_file" ]] && template_file="$prompt_root/review.md"
[[ ! -f "$template_file" ]] && template_file="$default_prompt_root/review/review.md"
[[ ! -f "$template_file" ]] && template_file="$default_prompt_root/review.md"

prompt="$(cat "$template_file")"
prompt="${prompt//\{\{PR_NUMBER\}\}/$PR_NUMBER}"
prompt="${prompt//\{\{TARGET_REPO\}\}/$TARGET_REPO}"
prompt="${prompt//\{\{PR_TITLE\}\}/$pr_title}"
prompt="${prompt//\{\{PR_AUTHOR\}\}/$pr_author}"
prompt="${prompt//\{\{FILES_CHANGED\}\}/$files_changed}"
prompt="${prompt//\{\{LINES_ADDED\}\}/$lines_added}"
prompt="${prompt//\{\{LINES_REMOVED\}\}/$lines_removed}"

skills_dir="$prompt_root/review"
if [[ ! -d "$skills_dir" ]]; then
  skills_dir="$default_prompt_root/review"
fi

skills_index_file="$skills_dir/index.md"
skills_file_list=""
if [[ -d "$skills_dir" ]]; then
  skills_file_list="$(find "$skills_dir" -maxdepth 1 -type f ! -name 'index.md' -exec basename {} \; | sort)"
fi

if [[ -f "$skills_index_file" || -n "$skills_file_list" ]]; then
  prompt+=$'\n\n## Optional Review Skills\n'
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

raw_output="$(claude -p "$prompt" --allowedTools "gh,git,cat,grep,find,head,tail,wc" --max-turns 10 --output-format text)"
printf '%s\n' "$raw_output" > /tmp/claude-review-output.txt

if ! review_json="$(extract_json_payload "$raw_output")"; then
  gh pr comment "$PR_NUMBER" --repo "$TARGET_REPO" --body "Review parsing fallback: unable to parse structured output.\n\n${raw_output:0:6000}"
  exit 0
fi

head_sha="$(gh pr view "$PR_NUMBER" --repo "$TARGET_REPO" --json headRefOid --jq '.headRefOid')"
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
    body="Review Comment(Severity:${severity_text})\n$title\n\n$details\n\n<!-- SENTINEL:FINDING id=$finding_id severity=$severity -->"
    if [[ -n "$recommendation" && "$recommendation" != "null" ]]; then
      body+="\n\nRecommendation: $recommendation"
    fi

    if [[ -n "$path" && "$path" != "null" && "$line" =~ ^[0-9]+$ && "$line" -gt 0 ]]; then
      if ! gh api "repos/$TARGET_REPO/pulls/$PR_NUMBER/comments" \
        -f body="$body" \
        -f commit_id="$head_sha" \
        -f path="$path" \
        -F line="$line" \
        -f side="RIGHT" >/dev/null 2>&1; then
        fallback_findings+="- [$severity] $path:$line - $title\n"
      fi
    else
      fallback_findings+="- [$severity] $title\n"
    fi
  done < <(jq -c '.findings // [] | .[]' <<<"$review_json")
fi

summary_body="Review summary: $summary\n\nVerdict: $verdict\nTest gaps: $test_gaps"
if [[ -n "$fallback_findings" ]]; then
  summary_body+="\n\nNon-inline findings (fallback):\n$fallback_findings"
fi

summary_body+="\n\nCounts: critical=$critical_count, major=$major_count, minor=$minor_count, nit=$nit_count"

summary_severity="nit"
if [[ "$critical_count" -gt 0 ]]; then
  summary_severity="critical"
elif [[ "$major_count" -gt 0 ]]; then
  summary_severity="major"
elif [[ "$minor_count" -gt 0 ]]; then
  summary_severity="minor"
fi
summary_severity_text="$(severity_label "$summary_severity")"
summary_body="Review Comment(Severity:${summary_severity_text})\n${summary_body}"

if [[ "$critical_count" -gt 0 ]]; then
  gh pr review "$PR_NUMBER" --repo "$TARGET_REPO" --request-changes --body "$summary_body"
elif [[ "$major_count" -gt 0 ]]; then
  gh pr comment "$PR_NUMBER" --repo "$TARGET_REPO" --body "$summary_body"
else
  gh pr review "$PR_NUMBER" --repo "$TARGET_REPO" --approve --body "$summary_body"
fi
