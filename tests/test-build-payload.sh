#!/usr/bin/env bash
set -euo pipefail

pass=0
fail=0

check() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo "PASS: $name"; pass=$((pass+1))
  else echo "FAIL: $name expected='$expected' actual='$actual'"; fail=$((fail+1)); fi
}

MY_GITHUB_USERNAME="botuser"
AUTO_REVIEW_AUTHORS=""

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

build_action() {
  local event_json="$1"
  local repo="${2:-owner/repo}"
  local type action pr_number state requested_login pr_author is_draft

  type="$(jq -r '.type // ""' <<<"$event_json")"
  action="$(jq -r '.payload.action // ""' <<<"$event_json")"

  case "$type" in
    PullRequestEvent)
      pr_number="$(jq -r '.payload.number // empty' <<<"$event_json")"
      [[ -z "$pr_number" ]] && { echo "skip"; return; }
      if [[ "$action" == "review_requested" ]]; then
        requested_login="$(jq -r '.payload.requested_reviewer.login // empty' <<<"$event_json")"
        if [[ -n "${MY_GITHUB_USERNAME:-}" && "$requested_login" != "$MY_GITHUB_USERNAME" ]]; then echo "skip"; return; fi
        echo "review"; return
      fi
      if [[ "$action" == "opened" || "$action" == "reopened" ]]; then
        pr_author="$(jq -r '.payload.pull_request.user.login // empty' <<<"$event_json")"
        is_draft="$(jq -r '.payload.pull_request.draft // false' <<<"$event_json")"
        [[ "$is_draft" == "true" ]] && { echo "skip"; return; }
        if [[ -n "${MY_GITHUB_USERNAME:-}" && "$pr_author" == "$MY_GITHUB_USERNAME" ]]; then echo "review"; return; fi
        if [[ -n "${AUTO_REVIEW_AUTHORS:-}" ]]; then
          if is_auto_review_author_for_repo "$repo" "$pr_author" "$AUTO_REVIEW_AUTHORS"; then
            echo "review"; return
          fi
        fi
        echo "skip"; return
      fi
      if [[ "$action" == "synchronize" ]]; then
        pr_author="$(jq -r '.payload.pull_request.user.login // empty' <<<"$event_json")"
        is_draft="$(jq -r '.payload.pull_request.draft // false' <<<"$event_json")"
        if [[ -n "${MY_GITHUB_USERNAME:-}" && "$pr_author" == "$MY_GITHUB_USERNAME" && "$is_draft" != "true" ]]; then echo "review"; return; fi
        echo "skip"; return
      fi
      echo "skip"
      ;;
    PullRequestReviewEvent)
      pr_number="$(jq -r '.payload.pull_request.number // empty' <<<"$event_json")"
      state="$(jq -r '.payload.review.state // "" | ascii_upcase' <<<"$event_json")"
      [[ -z "$pr_number" ]] && { echo "skip"; return; }
      [[ "$state" == "APPROVED" ]] && { echo "merge"; return; }
      [[ "$state" == "CHANGES_REQUESTED" || "$state" == "COMMENTED" ]] && { echo "followup"; return; }
      echo "skip"
      ;;
    IssueCommentEvent)
      [[ "$(jq -r '.payload.action // ""' <<<"$event_json")" != "created" ]] && { echo "skip"; return; }
      [[ "$(jq -r '.payload.issue.pull_request.url // empty' <<<"$event_json")" == "" ]] && { echo "skip"; return; }
      pr_number="$(jq -r '.payload.issue.number // empty' <<<"$event_json")"
      [[ -z "$pr_number" ]] && { echo "skip"; return; }
      echo "followup"
      ;;
    PullRequestReviewCommentEvent)
      [[ "$(jq -r '.payload.action // ""' <<<"$event_json")" != "created" ]] && { echo "skip"; return; }
      pr_number="$(jq -r '.payload.pull_request.number // empty' <<<"$event_json")"
      [[ -z "$pr_number" ]] && { echo "skip"; return; }
      echo "followup"
      ;;
    CheckSuiteEvent)
      [[ "$action" != "completed" ]] && { echo "skip"; return; }
      pr_number="$(jq -r '.payload.check_suite.pull_requests[0].number // empty' <<<"$event_json")"
      [[ -z "$pr_number" ]] && { echo "skip"; return; }
      echo "approve"
      ;;
    CheckRunEvent)
      [[ "$action" != "completed" ]] && { echo "skip"; return; }
      pr_number="$(jq -r '.payload.check_run.pull_requests[0].number // empty' <<<"$event_json")"
      [[ -z "$pr_number" ]] && { echo "skip"; return; }
      echo "approve"
      ;;
    *) echo "skip" ;;
  esac
}

# --- PullRequestEvent: review_requested ---
event="$(jq -nc '{type:"PullRequestEvent", payload:{action:"review_requested", number:42, requested_reviewer:{login:"botuser"}}}')"
check "PullRequestEvent review_requested for bot" "review" "$(build_action "$event")"

event="$(jq -nc '{type:"PullRequestEvent", payload:{action:"review_requested", number:42, requested_reviewer:{login:"someone_else"}}}')"
check "PullRequestEvent review_requested for other user" "skip" "$(build_action "$event")"

# --- PullRequestEvent: opened ---
event="$(jq -nc '{type:"PullRequestEvent", payload:{action:"opened", number:42, pull_request:{user:{login:"botuser"}, draft:false}}}')"
check "PullRequestEvent opened draft=false author=bot" "review" "$(build_action "$event")"

event="$(jq -nc '{type:"PullRequestEvent", payload:{action:"opened", number:42, pull_request:{user:{login:"botuser"}, draft:true}}}')"
check "PullRequestEvent opened draft=true author=bot" "skip" "$(build_action "$event")"

event="$(jq -nc '{type:"PullRequestEvent", payload:{action:"opened", number:42, pull_request:{user:{login:"otheruser"}, draft:false}}}')"
check "PullRequestEvent opened other author no AUTO_REVIEW_AUTHORS" "skip" "$(build_action "$event")"

AUTO_REVIEW_AUTHORS="otheruser"
event="$(jq -nc '{type:"PullRequestEvent", payload:{action:"opened", number:42, pull_request:{user:{login:"otheruser"}, draft:false}}}')"
check "PullRequestEvent opened author in AUTO_REVIEW_AUTHORS" "review" "$(build_action "$event")"
AUTO_REVIEW_AUTHORS=""

AUTO_REVIEW_AUTHORS="all:otheruser"
event="$(jq -nc '{type:"PullRequestEvent", payload:{action:"opened", number:42, pull_request:{user:{login:"otheruser"}, draft:false}}}')"
check "PullRequestEvent opened author in scoped AUTO_REVIEW_AUTHORS all:user" "review" "$(build_action "$event" "owner/repo")"

event="$(jq -nc '{type:"PullRequestEvent", payload:{action:"opened", number:42, pull_request:{user:{login:"stranger"}, draft:false}}}')"
check "PullRequestEvent opened author not in scoped AUTO_REVIEW_AUTHORS" "skip" "$(build_action "$event" "owner/repo")"
AUTO_REVIEW_AUTHORS=""

# --- PullRequestEvent: reopened ---
event="$(jq -nc '{type:"PullRequestEvent", payload:{action:"reopened", number:42, pull_request:{user:{login:"botuser"}, draft:false}}}')"
check "PullRequestEvent reopened draft=false author=bot" "review" "$(build_action "$event")"

# --- PullRequestEvent: synchronize ---
event="$(jq -nc '{type:"PullRequestEvent", payload:{action:"synchronize", number:42, pull_request:{user:{login:"botuser"}, draft:false}}}')"
check "PullRequestEvent synchronize draft=false author=bot" "review" "$(build_action "$event")"

event="$(jq -nc '{type:"PullRequestEvent", payload:{action:"synchronize", number:42, pull_request:{user:{login:"botuser"}, draft:true}}}')"
check "PullRequestEvent synchronize draft=true author=bot" "skip" "$(build_action "$event")"

event="$(jq -nc '{type:"PullRequestEvent", payload:{action:"synchronize", number:42, pull_request:{user:{login:"otheruser"}, draft:false}}}')"
check "PullRequestEvent synchronize other author" "skip" "$(build_action "$event")"

# --- PullRequestEvent: unmatched action ---
event="$(jq -nc '{type:"PullRequestEvent", payload:{action:"closed", number:42, pull_request:{user:{login:"botuser"}, draft:false}}}')"
check "PullRequestEvent closed action" "skip" "$(build_action "$event")"

# --- PullRequestEvent: missing pr_number ---
event="$(jq -nc '{type:"PullRequestEvent", payload:{action:"review_requested", requested_reviewer:{login:"botuser"}}}')"
check "PullRequestEvent missing pr_number" "skip" "$(build_action "$event")"

# --- PullRequestReviewEvent ---
event="$(jq -nc '{type:"PullRequestReviewEvent", payload:{pull_request:{number:42}, review:{state:"approved"}}}')"
check "PullRequestReviewEvent APPROVED" "merge" "$(build_action "$event")"

event="$(jq -nc '{type:"PullRequestReviewEvent", payload:{pull_request:{number:42}, review:{state:"changes_requested"}}}')"
check "PullRequestReviewEvent CHANGES_REQUESTED" "followup" "$(build_action "$event")"

event="$(jq -nc '{type:"PullRequestReviewEvent", payload:{pull_request:{number:42}, review:{state:"commented"}}}')"
check "PullRequestReviewEvent COMMENTED" "followup" "$(build_action "$event")"

event="$(jq -nc '{type:"PullRequestReviewEvent", payload:{pull_request:{number:42}, review:{state:"pending"}}}')"
check "PullRequestReviewEvent PENDING" "skip" "$(build_action "$event")"

event="$(jq -nc '{type:"PullRequestReviewEvent", payload:{review:{state:"approved"}}}')"
check "PullRequestReviewEvent missing pr_number" "skip" "$(build_action "$event")"

# --- IssueCommentEvent ---
event="$(jq -nc '{type:"IssueCommentEvent", payload:{action:"created", issue:{number:42, pull_request:{url:"https://github.com/org/repo/pull/42"}}}}')"
check "IssueCommentEvent created with PR url" "followup" "$(build_action "$event")"

event="$(jq -nc '{type:"IssueCommentEvent", payload:{action:"created", issue:{number:42}}}')"
check "IssueCommentEvent created no PR url (plain issue)" "skip" "$(build_action "$event")"

event="$(jq -nc '{type:"IssueCommentEvent", payload:{action:"edited", issue:{number:42, pull_request:{url:"https://github.com/org/repo/pull/42"}}}}')"
check "IssueCommentEvent edited" "skip" "$(build_action "$event")"

event="$(jq -nc '{type:"IssueCommentEvent", payload:{action:"created", issue:{pull_request:{url:"https://github.com/org/repo/pull/42"}}}}')"
check "IssueCommentEvent missing pr_number" "skip" "$(build_action "$event")"

# --- PullRequestReviewCommentEvent ---
event="$(jq -nc '{type:"PullRequestReviewCommentEvent", payload:{action:"created", pull_request:{number:42}}}')"
check "PullRequestReviewCommentEvent created" "followup" "$(build_action "$event")"

event="$(jq -nc '{type:"PullRequestReviewCommentEvent", payload:{action:"edited", pull_request:{number:42}}}')"
check "PullRequestReviewCommentEvent edited" "skip" "$(build_action "$event")"

event="$(jq -nc '{type:"PullRequestReviewCommentEvent", payload:{action:"created"}}')"
check "PullRequestReviewCommentEvent missing pr_number" "skip" "$(build_action "$event")"

# --- CheckSuiteEvent ---
event="$(jq -nc '{type:"CheckSuiteEvent", payload:{action:"completed", check_suite:{pull_requests:[{number:42}]}}}')"
check "CheckSuiteEvent completed with PR" "approve" "$(build_action "$event")"

event="$(jq -nc '{type:"CheckSuiteEvent", payload:{action:"pending", check_suite:{pull_requests:[{number:42}]}}}')"
check "CheckSuiteEvent pending" "skip" "$(build_action "$event")"

event="$(jq -nc '{type:"CheckSuiteEvent", payload:{action:"completed", check_suite:{pull_requests:[]}}}')"
check "CheckSuiteEvent completed no pull_requests" "skip" "$(build_action "$event")"

# --- CheckRunEvent ---
event="$(jq -nc '{type:"CheckRunEvent", payload:{action:"completed", check_run:{pull_requests:[{number:42}]}}}')"
check "CheckRunEvent completed with PR" "approve" "$(build_action "$event")"

event="$(jq -nc '{type:"CheckRunEvent", payload:{action:"pending", check_run:{pull_requests:[{number:42}]}}}')"
check "CheckRunEvent pending" "skip" "$(build_action "$event")"

event="$(jq -nc '{type:"CheckRunEvent", payload:{action:"completed", check_run:{pull_requests:[]}}}')"
check "CheckRunEvent completed no pull_requests" "skip" "$(build_action "$event")"

# --- Unknown event type ---
event="$(jq -nc '{type:"UnknownEvent", payload:{action:"created"}}')"
check "Unknown event type" "skip" "$(build_action "$event")"

echo "Results: pass=$pass fail=$fail"
[[ "$fail" -eq 0 ]]
