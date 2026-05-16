#!/usr/bin/env bash
set -euo pipefail

pass=0
fail=0

check() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo "PASS: $name"; pass=$((pass+1))
  else echo "FAIL: $name expected='$expected' actual='$actual'"; fail=$((fail+1)); fi
}

trim_spaces() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

author_in_list() {
  local author="$1"
  local authors_raw="$2"
  local entry
  local entries=()

  IFS=',' read -ra entries <<<"$authors_raw"
  for entry in "${entries[@]}"; do
    entry="$(trim_spaces "$entry")"
    [[ -z "$entry" ]] && continue
    if [[ "$author" == "$entry" ]]; then
      return 0
    fi
  done

  return 1
}

scope_matches_repo() {
  local repo="$1"
  local scope="$2"
  local repo_lower scope_lower

  repo_lower="$(printf '%s' "$repo" | tr '[:upper:]' '[:lower:]')"
  scope_lower="$(printf '%s' "$scope" | tr '[:upper:]' '[:lower:]')"

  [[ "$scope_lower" == "all" || "$scope_lower" == "$repo_lower" ]]
}

is_auto_review_author_for_repo() {
  local repo="$1"
  local author="$2"
  local rules_raw="$3"
  local token scope values
  local tokens=()
  local active_scope=""
  local active_values=""
  local parsed_scope=0

  [[ -z "$rules_raw" || -z "$author" ]] && return 1

  # Legacy format: username1,username2
  if [[ "$rules_raw" != *:* ]]; then
    author_in_list "$author" "$rules_raw"
    return $?
  fi

  # Scoped format with continuation support:
  # all:username1,org/repo:username2,username3,org2/repo2:username4
  IFS=',' read -ra tokens <<<"$rules_raw"
  for token in "${tokens[@]}"; do
    token="$(trim_spaces "$token")"
    [[ -z "$token" ]] && continue

    if [[ "$token" == *:* ]]; then
      if [[ -n "$active_scope" ]]; then
        parsed_scope=1
        if scope_matches_repo "$repo" "$active_scope" && author_in_list "$author" "$active_values"; then
          return 0
        fi
      fi

      scope="$(trim_spaces "${token%%:*}")"
      values="$(trim_spaces "${token#*:}")"
      active_scope="$scope"
      active_values="$values"
      continue
    fi

    if [[ -n "$active_scope" ]]; then
      if [[ -n "$active_values" ]]; then
        active_values="$active_values,$token"
      else
        active_values="$token"
      fi
    elif [[ "$author" == "$token" ]]; then
      return 0
    fi
  done

  if [[ -n "$active_scope" ]]; then
    parsed_scope=1
    if scope_matches_repo "$repo" "$active_scope" && author_in_list "$author" "$active_values"; then
      return 0
    fi
  fi

  if [[ "$parsed_scope" -eq 0 ]]; then
    author_in_list "$author" "$rules_raw"
    return $?
  fi

  return 1
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
