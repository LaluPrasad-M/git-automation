#!/usr/bin/env bash
set -euo pipefail
_lib="$(dirname "${BASH_SOURCE[0]}")/../shared/lib.sh"
# shellcheck source=scripts/shared/lib.sh
# shellcheck disable=SC1091
source "$_lib"

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
  log ERROR "Action $action failed on PR #${PR_NUMBER:-?}"
else
  log INFO "Action $action completed with status=$status on PR #${PR_NUMBER:-?}"
fi
