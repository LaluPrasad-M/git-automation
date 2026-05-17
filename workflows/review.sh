#!/usr/bin/env bash
set -euo pipefail

_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$_root/utils/logging.sh"
# shellcheck disable=SC1091
source "$_root/utils/policy.sh"
# shellcheck disable=SC1091
source "$_root/utils/authors.sh"
# shellcheck disable=SC1091
source "$_root/services/github/pr_service.sh"
# shellcheck disable=SC1091
source "$_root/services/github/comment_service.sh"
# shellcheck disable=SC1091
source "$_root/services/github/review_service.sh"
# shellcheck disable=SC1091
source "$_root/services/ai/ai_service.sh"
# shellcheck disable=SC1091
source "$_root/services/ai/prompt_service.sh"
# shellcheck disable=SC1091
source "$_root/services/ai/response_parser.sh"

trap 'log ERROR "review.sh failed at line $LINENO (exit $?)"' ERR

log INFO "Checking reviewer eligibility for $TARGET_REPO#$PR_NUMBER"
_pr_meta="$(gh_get_pr "$TARGET_REPO" "$PR_NUMBER" "reviewRequests,author")"
is_reviewer="$(jq --arg me "${MY_GITHUB_USERNAME:-}" '[.reviewRequests[]? | select(.login == $me)] | length > 0' <<<"$_pr_meta")"
pr_author="$(jq -r '.author.login // empty' <<<"$_pr_meta")"
author_whitelisted="false"
if [[ -n "${AUTO_REVIEW_AUTHORS:-}" ]]; then
  is_auto_review_author_for_repo "${TARGET_REPO:-}" "$pr_author" "$AUTO_REVIEW_AUTHORS" && author_whitelisted="true"
fi

is_own_pr="false"
[[ -n "${MY_GITHUB_USERNAME:-}" && "$pr_author" == "$MY_GITHUB_USERNAME" ]] && is_own_pr="true"
log INFO "Eligibility — own_pr=$is_own_pr is_reviewer=$is_reviewer author_whitelisted=$author_whitelisted"

if [[ "$is_own_pr" != "true" && "$is_reviewer" != "true" && "$author_whitelisted" != "true" ]]; then
  log SKIP "Not a requested reviewer and PR author not in AUTO_REVIEW_AUTHORS — skipping"
  exit 0
fi

log INFO "Checking for prior approvals on $TARGET_REPO#$PR_NUMBER"
already_approved="$(gh_get_pr "$TARGET_REPO" "$PR_NUMBER" "reviews" 2>/dev/null \
  | jq --arg me "${MY_GITHUB_USERNAME:-}" \
    '[.reviews[]? | select(.author.login == $me and .state == "APPROVED")] | length > 0' \
  || echo false)"
if [[ "$already_approved" == "true" ]]; then
  log SKIP "Already approved by ${MY_GITHUB_USERNAME} — skipping review"
  exit 0
fi

log INFO "Setting up git workspace"
[[ -n "${GITHUB_ENV:-}" ]] || { log ERROR "review.sh: GITHUB_ENV must be set before calling workspace_service"; exit 1; }
bash "$_root/services/git/workspace_service.sh"
_new_ws="$(grep '^WORKSPACE=' "${GITHUB_ENV:-/dev/null}" | tail -1 | cut -d= -f2-)"
[[ -n "$_new_ws" ]] && { export WORKSPACE="$_new_ws"; cd "$WORKSPACE"; }

log INFO "Fetching diff for $TARGET_REPO#$PR_NUMBER"
max_diff_lines="$(read_policy 'review.max_diff_lines')"
[[ -z "$max_diff_lines" ]] && max_diff_lines=2500

diff_output="$(gh_get_pr_diff "$TARGET_REPO" "$PR_NUMBER" 2>&1)" || {
  gh_post_pr_comment "$TARGET_REPO" "$PR_NUMBER" "Auto-review skipped: unable to fetch PR diff."
  exit 0
}
diff_lines="$(wc -l <<<"$diff_output" | tr -d ' ')"
log INFO "Diff fetched — $diff_lines lines"
if [[ "$diff_lines" -gt "$max_diff_lines" ]]; then
  gh_post_pr_comment "$TARGET_REPO" "$PR_NUMBER" "This PR has $diff_lines diff lines which exceeds the auto-review limit of $max_diff_lines. Please split it into smaller focused PRs so each can be reviewed effectively."
  exit 0
fi

log INFO "Fetching PR metadata"
pr_json="$(gh_get_pr "$TARGET_REPO" "$PR_NUMBER" "title,author,additions,deletions,changedFiles")"
pr_title="$(jq -r '.title' <<<"$pr_json")"
pr_author="$(jq -r '.author.login' <<<"$pr_json")"
files_changed="$(jq -r '.changedFiles' <<<"$pr_json")"
lines_added="$(jq -r '.additions' <<<"$pr_json")"
lines_removed="$(jq -r '.deletions' <<<"$pr_json")"

log INFO "Building review prompt (files=$files_changed, +$lines_added/-$lines_removed)"
_sentinel_root="${GITHUB_WORKSPACE:-$_root}"
template_file="$_sentinel_root/config/prompts/review/template/review.md"
[[ -f "$template_file" ]] || { log ERROR "Review template not found: $template_file"; exit 1; }

prompt="$(cat "$template_file")"
prompt="${prompt//\{\{PR_NUMBER\}\}/$PR_NUMBER}"
prompt="${prompt//\{\{TARGET_REPO\}\}/$TARGET_REPO}"
prompt="${prompt//\{\{PR_TITLE\}\}/$pr_title}"
prompt="${prompt//\{\{PR_AUTHOR\}\}/$pr_author}"
prompt="${prompt//\{\{IS_OWN_PR\}\}/$is_own_pr}"
prompt="${prompt//\{\{FILES_CHANGED\}\}/$files_changed}"
prompt="${prompt//\{\{LINES_ADDED\}\}/$lines_added}"
prompt="${prompt//\{\{LINES_REMOVED\}\}/$lines_removed}"

repo_skills_dir="$_sentinel_root/git-listeners/$TARGET_REPO/review/skills"
skill_manifest=""
_effective_skills_dir=""
if [[ -d "$repo_skills_dir" ]]; then
  skill_manifest="$(build_skill_manifest "$repo_skills_dir")"
  [[ -n "$skill_manifest" ]] && _effective_skills_dir="$repo_skills_dir"
fi
if [[ -z "$_effective_skills_dir" ]]; then
  _default_skills_dir="$_sentinel_root/config/prompts/review/skills"
  skill_manifest="$(build_skill_manifest "$_default_skills_dir")"
  [[ -n "$skill_manifest" ]] && _effective_skills_dir="$_default_skills_dir"
fi
if [[ -n "$skill_manifest" && -n "$_effective_skills_dir" ]]; then
  skill_count="$(grep -c '^-' <<<"$skill_manifest" || true)"
  skill_count="${skill_count:-0}"
  log INFO "Loading $skill_count skill file(s) from $_effective_skills_dir"
  prompt+=$'\n\n## Available Skill Files\n'
  prompt+="Read only the skill files relevant to the files changed in this PR. Use \`cat\` to read them from: $_effective_skills_dir/"$'\n'
  prompt+="$skill_manifest"
else
  log INFO "No skill files found — using base prompt only"
fi

prompt+=$'\n\n## PR Diff\n\n```diff\n'"$diff_output"$'\n```\n'

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

prompt_lines="$(wc -l <<<"$prompt" | tr -d ' ')"
log INFO "Calling LLM for review of $TARGET_REPO#$PR_NUMBER (prompt=${prompt_lines} lines, max_turns=${MAX_TURNS:-5})"
raw_output="$(call_llm "$prompt" "cat,grep,find,head,tail")" || true
if [[ -z "$raw_output" ]]; then
  log ERROR "LLM call returned empty output"
  gh_post_pr_comment "$TARGET_REPO" "$PR_NUMBER" "Auto-review skipped: LLM call returned no output."
  exit 0
fi
printf '%s\n' "$raw_output" > "/tmp/claude-review-${TARGET_REPO//\//__}-${PR_NUMBER}.txt"

response_lines="$(wc -l <<<"$raw_output" | tr -d ' ')"
log INFO "LLM response received (${response_lines} lines) — parsing review JSON"
if ! review_json="$(extract_json_payload "$raw_output")"; then
  log WARN "Failed to parse structured review output — posting raw fallback"
  gh_post_pr_comment "$TARGET_REPO" "$PR_NUMBER" "Review parsing fallback: unable to parse structured output."$'\n\n'"${raw_output:0:6000}"
  exit 0
fi

log INFO "Resolving PR head SHA for inline comments"
head_sha="$(gh_get_pr "$TARGET_REPO" "$PR_NUMBER" "headRefOid" | jq -r '.headRefOid // empty')"
if [[ -z "$head_sha" ]]; then
  gh_post_pr_comment "$TARGET_REPO" "$PR_NUMBER" "Review complete but could not post inline comments: unable to resolve PR head SHA."
  exit 0
fi
summary="$(jq -r '.summary // "No summary provided."' <<<"$review_json")"
verdict="$(jq -r '.verdict // "NEEDS_DISCUSSION"' <<<"$review_json")"
test_gaps="$(jq -r '.test_gaps // [] | if length == 0 then "none" else join("; ") end' <<<"$review_json")"
critical_count="$(jq -r '[.findings[]? | select(.severity == "critical")] | length' <<<"$review_json")"
major_count="$(jq -r '[.findings[]? | select(.severity == "major")] | length' <<<"$review_json")"
minor_count="$(jq -r '[.findings[]? | select(.severity == "minor")] | length' <<<"$review_json")"
nit_count="$(jq -r '[.findings[]? | select(.severity == "nit")] | length' <<<"$review_json")"
log INFO "Review findings: critical=$critical_count major=$major_count minor=$minor_count nit=$nit_count verdict=$verdict"

fallback_findings=""
finding_count="$(jq '.findings // [] | length' <<<"$review_json")"
finding_idx=0
if [[ "$finding_count" -gt 0 ]]; then
  log INFO "Posting $finding_count inline finding(s)"
  while IFS= read -r finding; do
    finding_idx=$((finding_idx + 1))
    severity="$(jq -r '.severity // "minor"' <<<"$finding")"
    path="$(jq -r '.path // ""' <<<"$finding")"
    line="$(jq -r '.line // 0' <<<"$finding")"
    title="$(jq -r '.title // "Untitled finding"' <<<"$finding")"
    log INFO "  [$finding_idx/$finding_count] $severity — ${path}:${line} — $title"
    details="$(jq -r '.details // ""' <<<"$finding")"
    recommendation="$(jq -r '.recommendation // ""' <<<"$finding")"

    finding_seed="$path|$line|$title|$severity"
    finding_id="$(printf '%s' "$finding_seed" | (command -v shasum >/dev/null 2>&1 && shasum || sha1sum) | awk '{print $1}' | cut -c1-12)"

    severity_text="$(severity_label "$severity")"
    body="$(printf 'Review Comment(Severity:%s)\n%s\n\n%s\n\n<!-- SENTINEL:FINDING id=%s severity=%s -->' \
      "$severity_text" "$title" "$details" "$finding_id" "$severity")"
    if [[ -n "$recommendation" && "$recommendation" != "null" ]]; then
      body+=$'\n\nRecommendation: '"$recommendation"
    fi

    if [[ -n "$path" && "$path" != "null" && "$line" =~ ^[0-9]+$ && "$line" -gt 0 ]]; then
      if ! gh_post_inline_comment "$TARGET_REPO" "$PR_NUMBER" "$head_sha" "$path" "$line" "$body" >/dev/null 2>&1; then
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

log INFO "Submitting review verdict for $TARGET_REPO#$PR_NUMBER (own_pr=$is_own_pr)"
if [[ "$critical_count" -gt 0 ]]; then
  if [[ "$is_own_pr" == "true" ]]; then
    gh_post_pr_comment "$TARGET_REPO" "$PR_NUMBER" "$summary_body"
  else
    gh_post_pr_review_request_changes "$TARGET_REPO" "$PR_NUMBER" "$summary_body"
  fi
elif [[ "$major_count" -gt 0 || "$is_own_pr" == "true" ]]; then
  gh_post_pr_comment "$TARGET_REPO" "$PR_NUMBER" "$summary_body"
else
  gh_post_pr_review_approve "$TARGET_REPO" "$PR_NUMBER" "$summary_body"
fi
log INFO "Review complete for $TARGET_REPO#$PR_NUMBER"
