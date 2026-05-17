#!/usr/bin/env bash
set -euo pipefail

pass=0
fail=0

_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$_root/utils/authors.sh"

check() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo "PASS: $name"; pass=$((pass+1))
  else echo "FAIL: $name expected='$expected' actual='$actual'"; fail=$((fail+1)); fi
}

match() { is_auto_review_author_for_repo "$1" "$2" "$3" && echo "true" || echo "false"; }

# --- Empty rules ---
check "empty rules" "false" "$(match "org/repo" "user1" "")"

# --- Legacy format (no colon) ---
check "legacy user1 matches" "true" "$(match "org/repo" "user1" "user1,user2")"
check "legacy user2 matches" "true" "$(match "org/repo" "user2" "user1,user2")"
check "legacy user3 no match" "false" "$(match "org/repo" "user3" "user1,user2")"
check "legacy spaces trimmed user2 matches" "true" "$(match "org/repo" "user2" "user1, user2")"

# --- Scoped format: all ---
check "all:user1 matches any repo" "true" "$(match "any/repo" "user1" "all:user1")"
check "all:user1 user2 no match" "false" "$(match "any/repo" "user2" "all:user1")"

# --- Scoped format: specific repo ---
check "org/repo1:user1 matches" "true" "$(match "org/repo1" "user1" "org/repo1:user1")"
check "org/repo1:user1 wrong repo" "false" "$(match "org/repo2" "user1" "org/repo1:user1")"
check "org/repo1:user1 wrong author" "false" "$(match "org/repo1" "user2" "org/repo1:user1")"

# --- Scoped format: multiple rules ---
check "all:user1 multi-rule user1 any repo" "true" "$(match "org/anything" "user1" "all:user1,org/repo2:user2")"
check "org/repo2:user2 multi-rule user2 on matching repo" "true" "$(match "org/repo2" "user2" "all:user1,org/repo2:user2")"
check "org/repo2:user2 multi-rule user2 wrong repo" "false" "$(match "org/other" "user2" "all:user1,org/repo2:user2")"

# --- Continuation (comma continuation within scope) ---
check "continuation org/repo:user1,user2 — user2 on matching repo" "true" "$(match "org/repo" "user2" "org/repo:user1,user2")"
check "continuation org/repo:user1,user2 — user2 on wrong repo" "false" "$(match "org/other" "user2" "org/repo:user1,user2")"

# --- Case-insensitive repo match ---
check "case-insensitive repo match Org/Repo vs org/repo" "true" "$(match "org/repo" "user1" "Org/Repo:user1")"

echo "Results: pass=$pass fail=$fail"
[[ "$fail" -eq 0 ]]
