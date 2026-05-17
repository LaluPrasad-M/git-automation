#!/usr/bin/env bash

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
    [[ "$author" == "$entry" ]] && return 0
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

# is_auto_review_author_for_repo <repo> <author> <rules>
# Rules formats:
#   Legacy:  "username1,username2"
#   Scoped:  "all:username1,org/repo:username2,username3"
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

  if [[ "$rules_raw" != *:* ]]; then
    author_in_list "$author" "$rules_raw"
    return $?
  fi

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
      active_values="${active_values:+$active_values,}$token"
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

  [[ "$parsed_scope" -eq 0 ]] && { author_in_list "$author" "$rules_raw"; return $?; }
  return 1
}
