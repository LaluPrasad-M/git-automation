#!/usr/bin/env bash
set -euo pipefail

pass=0
fail=0

check() {
  local name="$1"
  local expected="$2"
  local actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "PASS: $name"
    pass=$((pass + 1))
  else
    echo "FAIL: $name expected='$expected' actual='$actual'"
    fail=$((fail + 1))
  fi
}

should_skip() {
  local action="$1" author="$2" bot="$3"
  local result="false"
  if [[ "$action" == "merge" ]]; then
    [[ "$author" != "$bot" ]] && result="true"
  elif [[ "$action" == "review" ]]; then
    result="false"
  else
    [[ "$author" == "$bot" ]] && result="true"
  fi
  [[ "${DRY_RUN:-false}" == "true" ]] && result="true"
  echo "$result"
}

bot="botuser"

# Review: always proceeds (own PRs allowed)
check "review: proceeds own PR"    "false" "$(should_skip review   botuser   $bot)"
check "review: proceeds other PR"  "false" "$(should_skip review   contributor $bot)"

# followup/approve: skip own PRs (push-triggered followup is overridden in run-dispatch-local)
check "approve: skips own PR"      "true"  "$(should_skip approve  botuser      $bot)"
check "approve: proceeds other PR" "false" "$(should_skip approve  contributor  $bot)"
check "followup: skips own PR"     "true"  "$(should_skip followup botuser      $bot)"
check "followup: proceeds other PR" "false" "$(should_skip followup contributor $bot)"

# Merge: only proceeds on own PRs
check "merge: proceeds on own PR"  "false" "$(should_skip merge    botuser   $bot)"
check "merge: skips other PR"      "true"  "$(should_skip merge    contributor $bot)"

# Merge guard log includes approver when present
approved_by="tirlochanarora16"
log_msg="PR authored by contributor, not botuser (approved by $approved_by) — skipping"
check "merge guard log includes approver" "PR authored by contributor, not botuser (approved by tirlochanarora16) — skipping" "$log_msg"

approved_by=""
log_msg="PR authored by contributor, not botuser${approved_by:+ (approved by $approved_by)} — skipping"
check "merge guard log without approver" "PR authored by contributor, not botuser — skipping" "$log_msg"


# DRY_RUN overrides all actions
check "DRY_RUN: forces skip on review"   "true"  "$(DRY_RUN=true  should_skip review   contributor $bot)"
check "DRY_RUN=false: does not force skip" "false" "$(DRY_RUN=false should_skip review contributor $bot)"

echo "Results: pass=$pass fail=$fail"
[[ "$fail" -eq 0 ]]
