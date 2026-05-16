#!/usr/bin/env bash
set -euo pipefail

pass=0
fail=0

check() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo "PASS: $name"; pass=$((pass+1))
  else echo "FAIL: $name expected='$expected' actual='$actual'"; fail=$((fail+1)); fi
}

classify_action() {
  local feed_title="$1" explicit_action="${2:-}"
  if [[ -n "$explicit_action" ]]; then
    case "$explicit_action" in review|followup|approve|merge) echo "$explicit_action"; return ;; esac
  fi
  if grep -Eqi 'review requested|requested your review' <<<"$feed_title"; then echo "review"
  elif grep -Eqi 'commented|requested changes' <<<"$feed_title"; then echo "followup"
  elif grep -Eqi 'approved' <<<"$feed_title"; then echo "merge"
  elif grep -Eqi 'checks|status|ci|build|test' <<<"$feed_title"; then echo "approve"
  else echo "unknown"; fi
}

# --- feed_title → review ---
check "review requested phrase" "review" "$(classify_action "review requested on PR #42")"
check "requested your review phrase" "review" "$(classify_action "LaluPrasad-M requested your review on PR #42")"
check "review requested uppercase" "review" "$(classify_action "REVIEW REQUESTED")"

# --- feed_title → followup ---
check "commented phrase" "followup" "$(classify_action "user commented on PR #42")"
check "requested changes phrase" "followup" "$(classify_action "user requested changes on PR #42")"
check "commented uppercase" "followup" "$(classify_action "COMMENTED on PR")"

# --- feed_title → merge ---
check "approved phrase" "merge" "$(classify_action "user approved PR #42")"
check "approved uppercase" "merge" "$(classify_action "APPROVED pull request")"

# --- feed_title → approve ---
check "checks keyword" "approve" "$(classify_action "checks completed on PR #42")"
check "ci keyword" "approve" "$(classify_action "CI build passing")"
check "build keyword" "approve" "$(classify_action "build status updated")"
check "test keyword" "approve" "$(classify_action "test results ready")"
check "status keyword" "approve" "$(classify_action "Status check passed")"

# --- feed_title → unknown ---
check "no matching keyword" "unknown" "$(classify_action "PR #42 was opened")"
check "merged does not match approved" "unknown" "$(classify_action "merged pull request")"

# --- explicit_action overrides ---
check "explicit review overrides approved title" "review" "$(classify_action "user approved PR #42" "review")"
check "explicit merge overrides any title" "merge" "$(classify_action "PR #42 was opened" "merge")"
check "explicit followup with empty title" "followup" "$(classify_action "" "followup")"
check "invalid explicit falls through to title patterns" "review" "$(classify_action "review requested on PR #42" "unknown_action")"

echo "Results: pass=$pass fail=$fail"
[[ "$fail" -eq 0 ]]
