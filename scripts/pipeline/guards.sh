#!/usr/bin/env bash
set -euo pipefail
_lib="$(dirname "${BASH_SOURCE[0]}")/../shared/lib.sh"
# shellcheck source=scripts/shared/lib.sh
# shellcheck disable=SC1091
source "$_lib"

pr_author=""
bot_user=""
action=""
pr_number=""
approved_by=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --author) pr_author="$2"; shift 2 ;;
    --bot-user) bot_user="$2"; shift 2 ;;
    --action) action="$2"; shift 2 ;;
    --pr-number) pr_number="$2"; shift 2 ;;
    --approved-by) approved_by="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Parsed for compatibility with callers that always pass PR context.
[[ -n "$pr_number" ]] && :

should_skip="false"

if [[ "$action" == "merge" ]]; then
  if [[ -n "$pr_author" && -n "$bot_user" && "$pr_author" != "$bot_user" ]]; then
    _approver_info="${approved_by:+ (approved by $approved_by)}"
    log SKIP "Merge guard: PR authored by $pr_author, not $bot_user${_approver_info} — skipping"
    should_skip="true"
  fi
elif [[ "$action" == "review" ]]; then
  : # reviewing own PRs is allowed
else
  if [[ -n "$pr_author" && -n "$bot_user" && "$pr_author" == "$bot_user" ]]; then
    log SKIP "Self-filter: PR authored by $bot_user — skipping $action"
    should_skip="true"
  fi
fi

if [[ "${DRY_RUN:-false}" == "true" ]]; then
  log INFO "DRY_RUN is on — no actions will be taken"
  should_skip="true"
fi



echo "should_skip=$should_skip" >> "$GITHUB_OUTPUT"
if [[ "$should_skip" == "true" ]]; then
  log SKIP "Guard: skipping action=$action pr=$pr_number"
else
  log INFO "Guard passed —, proceeding with action=$action pr=$pr_number"
fi
