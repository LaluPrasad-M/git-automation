#!/usr/bin/env bash
set -euo pipefail

action="${1:-unknown}"
status="${2:-unknown}"
audit_issue="${AUDIT_ISSUE_NUMBER:-}"

if [[ -n "$audit_issue" ]]; then
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  run_url="https://github.com/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
  body="[$now] action=$action status=$status pr=#${PR_NUMBER:-?} run=$run_url"
  gh issue comment "$audit_issue" --repo "$GITHUB_REPOSITORY" --body "$body"
fi

if [[ "$status" == "failure" ]]; then
  echo "::error::Action $action failed on PR #${PR_NUMBER:-?}"
else
  echo "::notice::Action $action completed with status=$status on PR #${PR_NUMBER:-?}"
fi
