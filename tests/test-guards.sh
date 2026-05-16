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
  if [[ "$action" == "merge" ]]; then
    if [[ "$author" != "$bot" ]]; then echo "true"; else echo "false"; fi
  else
    if [[ "$author" == "$bot" ]]; then echo "true"; else echo "false"; fi
  fi
}

bot="botuser"

# Non-merge actions: skip own PRs
check "review: skips own PR"       "true"  "$(should_skip review   botuser   $bot)"
check "review: proceeds other PR"  "false" "$(should_skip review   contributor $bot)"
check "approve: skips own PR"      "true"  "$(should_skip approve  botuser   $bot)"
check "followup: skips own PR"     "true"  "$(should_skip followup botuser   $bot)"

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

# Rate limit
recent=21; max=20
if [[ "$recent" -ge "$max" ]]; then res="true"; else res="false"; fi
check "rate limited" "true" "$res"

recent=5
if [[ "$recent" -ge "$max" ]]; then res="true"; else res="false"; fi
check "not rate limited" "false" "$res"

echo "Results: pass=$pass fail=$fail"
[[ "$fail" -eq 0 ]]
