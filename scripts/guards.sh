#!/usr/bin/env bash
set -euo pipefail

pr_author=""
bot_user=""
action=""
pr_number=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --author) pr_author="$2"; shift 2 ;;
    --bot-user) bot_user="$2"; shift 2 ;;
    --action) action="$2"; shift 2 ;;
    --pr-number) pr_number="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

should_skip="false"

if [[ -n "$pr_author" && -n "$bot_user" && "$pr_author" == "$bot_user" ]]; then
  echo "::warning::Self-filter: PR author is bot user"
  should_skip="true"
fi

if [[ "${DRY_RUN:-false}" == "true" ]]; then
  echo "::notice::DRY_RUN enabled"
  should_skip="true"
fi

max_actions="${MAX_ACTIONS_PER_HOUR:-20}"
recent_runs="$(gh run list --repo "$GITHUB_REPOSITORY" --limit "$max_actions" --json createdAt --jq 'length' 2>/dev/null || echo 0)"
if [[ "$recent_runs" -ge "$max_actions" ]]; then
  echo "::warning::Rate limit reached: $recent_runs/$max_actions"
  should_skip="true"
fi

enabled="true"
if [[ -f "${POLICY_FILE:-}" ]]; then
  if yq e '.repo' "${POLICY_FILE}" >/dev/null 2>&1; then
    enabled="$(yq e ".${action}.enabled // true" "${POLICY_FILE}")"
  else
    enabled="$(yq e ".defaults.${action}.enabled // true" "${POLICY_FILE}")"
  fi
fi

if [[ "$enabled" == "false" ]]; then
  echo "::notice::Action $action disabled by policy"
  should_skip="true"
fi

echo "should_skip=$should_skip" >> "$GITHUB_OUTPUT"
echo "::notice::Guard result: $should_skip"
