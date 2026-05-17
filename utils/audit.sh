#!/usr/bin/env bash
set -euo pipefail

_logging="$(dirname "${BASH_SOURCE[0]}")/logging.sh"
# shellcheck source=utils/logging.sh
# shellcheck disable=SC1091
source "$_logging"

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
