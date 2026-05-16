#!/usr/bin/env bash
set -euo pipefail

pass=0
fail=0

check() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo "PASS: $name"; pass=$((pass+1))
  else echo "FAIL: $name expected='$expected' actual='$actual'"; fail=$((fail+1)); fi
}

is_positive_reply() {
  local text="$1"
  shopt -s nocasematch
  if [[ "$text" =~ (won\'t|wont|cannot|can\'t|partial|later|defer|not\ fix|decline|won.?t\ fix) ]]; then
    shopt -u nocasematch
    return 1
  fi

  if [[ "$text" =~ (fixed|addressed|done|updated|resolved|implemented|pushed\ changes|added\ tests) ]]; then
    shopt -u nocasematch
    return 0
  fi

  shopt -u nocasematch
  return 1
}

is_positive() { is_positive_reply "$1" && echo "positive" || echo "negative"; }

# --- Positive cases ---
check "fixed the issue" "positive" "$(is_positive "fixed the issue")"
check "addressed your comment" "positive" "$(is_positive "addressed your comment")"
check "done" "positive" "$(is_positive "done")"
check "updated the function" "positive" "$(is_positive "updated the function")"
check "resolved" "positive" "$(is_positive "resolved")"
check "implemented your suggestion" "positive" "$(is_positive "implemented your suggestion")"
check "pushed changes to address this" "positive" "$(is_positive "pushed changes to address this")"
check "added tests for this" "positive" "$(is_positive "added tests for this")"
check "FIXED all caps" "positive" "$(is_positive "FIXED")"
check "This is done now" "positive" "$(is_positive "This is done now")"

# --- Negative / non-positive cases ---
check "won't fix this" "negative" "$(is_positive "won't fix this")"
check "wont fix" "negative" "$(is_positive "wont fix")"
check "cannot change this now" "negative" "$(is_positive "cannot change this now")"
check "can't do that" "negative" "$(is_positive "can't do that")"
check "partial fix applied" "negative" "$(is_positive "partial fix applied")"
check "defer to next sprint" "negative" "$(is_positive "defer to next sprint")"
check "not fix right now" "negative" "$(is_positive "not fix right now")"
check "I'll decline this suggestion" "negative" "$(is_positive "I'll decline this suggestion")"
check "still working on it" "negative" "$(is_positive "still working on it")"
check "looks good to me" "negative" "$(is_positive "looks good to me")"
check "I'll look into this later" "negative" "$(is_positive "I'll look into this later")"

echo "Results: pass=$pass fail=$fail"
[[ "$fail" -eq 0 ]]
