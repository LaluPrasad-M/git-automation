#!/usr/bin/env bash
set -euo pipefail
_lib="$(dirname "${BASH_SOURCE[0]}")/../shared/lib.sh"
# shellcheck source=scripts/shared/lib.sh
# shellcheck disable=SC1091
source "$_lib"

action="${1:-unknown}"
status="${2:-unknown}"
repo_slug="${TARGET_REPO//\//__}"
log_file="${SENTINEL_LOG:-${WORKSPACE:-.}/.state/logs/${repo_slug}.log}"

mkdir -p "$(dirname "$log_file")"
printf '[%s][AUDIT] action=%s status=%s pr=#%s\n' \
  "$(date +'%Y-%m-%d %H:%M:%S')" "$action" "$status" "${PR_NUMBER:-?}" \
  >> "$log_file"

if [[ "$status" == "failure" ]]; then
  log ERROR "Action $action failed on PR #${PR_NUMBER:-?}"
else
  log INFO "Action $action completed with status=$status on PR #${PR_NUMBER:-?}"
fi
