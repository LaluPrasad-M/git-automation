#!/usr/bin/env bash
set -euo pipefail

_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$_root/utils/logging.sh"
# shellcheck disable=SC1091
source "$_root/utils/authors.sh"
# shellcheck disable=SC1091
source "$_root/services/github/pr_service.sh"
# shellcheck disable=SC1091
source "$_root/services/github/events_service.sh"

workspace="${WORKSPACE:-$_root}"

if [[ ! -d "$workspace" ]]; then
  if [[ -d "$_root" ]]; then
    workspace="$_root"
  elif [[ -d "/app" ]]; then
    workspace="/app"
  else
    echo "Valid WORKSPACE not found: $workspace" >&2
    exit 1
  fi
fi

cd "$workspace"

if ! command -v gh >/dev/null 2>&1; then
  echo "gh is required" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 1
fi

if [[ -z "${TARGET_REPOS:-}" ]]; then
  echo "TARGET_REPOS is required" >&2
  exit 1
fi

parse_target_repos() {
  local raw="$1"
  tr ',' '\n' <<<"$raw" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed '/^$/d'
}

state_dir="${STATE_DIR:-$workspace/.state/event-listener}"
mkdir -p "$state_dir"

startup_repos=()
while IFS= read -r repo; do
  [[ -z "$repo" ]] && continue
  startup_repos+=("$repo")
done < <(parse_target_repos "$TARGET_REPOS")

repo_count="${#startup_repos[@]}"
poll_interval="${POLL_INTERVAL_SECONDS:-60}"

log INFO "Sentinel started — watching $repo_count repo(s), polling every ${poll_interval}s"
for _r in "${startup_repos[@]}"; do
  log INFO "  → $_r"
done

build_payload() {
  local event_json="$1"
  local repo="$2"

  local type action pr_number state
  type="$(jq -r '.type // ""' <<<"$event_json")"
  action="$(jq -r '.payload.action // ""' <<<"$event_json")"

  case "$type" in
    PullRequestEvent)
      pr_number="$(jq -r '.payload.number // empty' <<<"$event_json")"
      if [[ -z "$pr_number" ]]; then return 1; fi
      if [[ "$action" == "review_requested" ]]; then
        requested_login="$(jq -r '.payload.requested_reviewer.login // empty' <<<"$event_json")"
        if [[ -n "${MY_GITHUB_USERNAME:-}" && "$requested_login" != "$MY_GITHUB_USERNAME" ]]; then return 1; fi
        jq -nc --arg repo "$repo" --arg pr "$pr_number" --arg t "review requested on PR #$pr_number" '{event_type:"pr_review_requested", client_payload:{target_repo:$repo, pr_number:$pr, feed_title:$t, action:"review", source:"docker-listener"}}'
        return 0
      fi
      if [[ "$action" == "opened" || "$action" == "reopened" ]]; then
        pr_author="$(jq -r '(.payload.pull_request.user.login // .actor.login) // empty' <<<"$event_json")"
        is_draft="$(jq -r '.payload.pull_request.draft // false' <<<"$event_json")"
        [[ "$is_draft" == "true" ]] && return 1
        if [[ -n "${MY_GITHUB_USERNAME:-}" && "$pr_author" == "$MY_GITHUB_USERNAME" ]]; then
          jq -nc --arg repo "$repo" --arg pr "$pr_number" --arg t "review requested on PR #$pr_number" '{event_type:"pr_review_requested", client_payload:{target_repo:$repo, pr_number:$pr, feed_title:$t, action:"review", source:"docker-listener"}}'
          return 0
        fi
        if [[ -n "${AUTO_REVIEW_AUTHORS:-}" ]]; then
          if is_auto_review_author_for_repo "$repo" "$pr_author" "$AUTO_REVIEW_AUTHORS"; then
            jq -nc --arg repo "$repo" --arg pr "$pr_number" --arg t "review requested on PR #$pr_number" '{event_type:"pr_review_requested", client_payload:{target_repo:$repo, pr_number:$pr, feed_title:$t, action:"review", source:"docker-listener"}}'
            return 0
          fi
        fi
      fi
      return 1
      ;;
    PullRequestReviewEvent)
      pr_number="$(jq -r '.payload.pull_request.number // empty' <<<"$event_json")"
      state="$(jq -r '.payload.review.state // "" | ascii_upcase' <<<"$event_json")"
      if [[ -z "$pr_number" ]]; then return 1; fi
      if [[ "$state" == "APPROVED" ]]; then
        approver="$(jq -r '.payload.review.user.login // "unknown"' <<<"$event_json")"
        jq -nc --arg repo "$repo" --arg pr "$pr_number" --arg t "approved PR #$pr_number" --arg approver "$approver" '{event_type:"pr_approval_received", client_payload:{target_repo:$repo, pr_number:$pr, feed_title:$t, action:"merge", approved_by:$approver, source:"docker-listener"}}'
        return 0
      fi
      if [[ "$state" == "CHANGES_REQUESTED" || "$state" == "COMMENTED" ]]; then
        jq -nc --arg repo "$repo" --arg pr "$pr_number" --arg t "review commented on PR #$pr_number" '{event_type:"pr_comment_received", client_payload:{target_repo:$repo, pr_number:$pr, feed_title:$t, source:"docker-listener"}}'
        return 0
      fi
      return 1
      ;;
    IssueCommentEvent)
      if [[ "$(jq -r '.payload.action // ""' <<<"$event_json")" != "created" ]]; then return 1; fi
      if [[ "$(jq -r '.payload.issue.pull_request.url // empty' <<<"$event_json")" == "" ]]; then return 1; fi
      pr_number="$(jq -r '.payload.issue.number // empty' <<<"$event_json")"
      if [[ -z "$pr_number" ]]; then return 1; fi
      jq -nc --arg repo "$repo" --arg pr "$pr_number" --arg t "commented on PR #$pr_number" '{event_type:"pr_comment_received", client_payload:{target_repo:$repo, pr_number:$pr, feed_title:$t, source:"docker-listener"}}'
      return 0
      ;;
    PullRequestReviewCommentEvent)
      if [[ "$(jq -r '.payload.action // ""' <<<"$event_json")" != "created" ]]; then return 1; fi
      pr_number="$(jq -r '.payload.pull_request.number // empty' <<<"$event_json")"
      if [[ -z "$pr_number" ]]; then return 1; fi
      jq -nc --arg repo "$repo" --arg pr "$pr_number" --arg t "review comment on PR #$pr_number" '{event_type:"pr_comment_received", client_payload:{target_repo:$repo, pr_number:$pr, feed_title:$t, source:"docker-listener"}}'
      return 0
      ;;
    CheckSuiteEvent)
      if [[ "$action" != "completed" ]]; then return 1; fi
      pr_number="$(jq -r '.payload.check_suite.pull_requests[0].number // empty' <<<"$event_json")"
      if [[ -z "$pr_number" ]]; then return 1; fi
      jq -nc --arg repo "$repo" --arg pr "$pr_number" --arg t "checks completed on PR #$pr_number" '{event_type:"pr_ci_completed", client_payload:{target_repo:$repo, pr_number:$pr, feed_title:$t, action:"approve", source:"docker-listener"}}'
      return 0
      ;;
    CheckRunEvent)
      if [[ "$action" != "completed" ]]; then return 1; fi
      pr_number="$(jq -r '.payload.check_run.pull_requests[0].number // empty' <<<"$event_json")"
      if [[ -z "$pr_number" ]]; then return 1; fi
      jq -nc --arg repo "$repo" --arg pr "$pr_number" --arg t "checks completed on PR #$pr_number" '{event_type:"pr_ci_completed", client_payload:{target_repo:$repo, pr_number:$pr, feed_title:$t, action:"approve", source:"docker-listener"}}'
      return 0
      ;;
    PushEvent)
      ref="$(jq -r '.payload.ref // ""' <<<"$event_json")"
      branch="${ref#refs/heads/}"
      [[ -z "$branch" || "$branch" == "$ref" ]] && return 1
      if [[ -z "${MY_GITHUB_USERNAME:-}" ]]; then return 1; fi
      pr_json="$(gh_pr_list_for_branch "$repo" "$branch")"
      pr_number="$(jq -r '.[0].number // empty' <<<"$pr_json")"
      [[ -z "$pr_number" ]] && return 1
      pr_author="$(jq -r '.[0].author.login // empty' <<<"$pr_json")"
      is_draft="$(jq -r '.[0].isDraft // false' <<<"$pr_json")"
      [[ "$pr_author" != "$MY_GITHUB_USERNAME" ]] && return 1
      [[ "$is_draft" == "true" ]] && return 1
      jq -nc --arg repo "$repo" --arg pr "$pr_number" --arg t "code pushed to PR #$pr_number" \
        '{event_type:"pr_notification", client_payload:{target_repo:$repo, pr_number:$pr, feed_title:$t, action:"review", source:"docker-listener"}}'
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

cycle=0
while true; do
  cycle=$((cycle + 1))

  repos=()
  while IFS= read -r repo; do
    repos+=("$repo")
  done < <(parse_target_repos "$TARGET_REPOS")

  if [[ "${#repos[@]}" -eq 0 ]]; then
    log ERROR "No repositories found in TARGET_REPOS — check your .env"
    sleep "$poll_interval"
    continue
  fi

  for repo in "${repos[@]}"; do
    [[ -z "$repo" ]] && continue

    state_file="$state_dir/$repo.last"
    mkdir -p "$(dirname "$state_file")"
    last_id=""
    [[ -f "$state_file" ]] && last_id="$(cat "$state_file")"

    events_json="$(gh_repo_events "$repo")"
    newest_id="$(jq -r '.[0].id // ""' <<<"$events_json")"

    if [[ -z "$newest_id" ]]; then
      continue
    fi

    # First time watching this repo: initialize checkpoint from current head event
    # to avoid replaying historical backlog entries.
    if [[ -z "$last_id" ]]; then
      printf '%s' "$newest_id" > "$state_file"
      continue
    fi

    new_events_file="$(mktemp)"
    while IFS= read -r event; do
      event_id="$(jq -r '.id // ""' <<<"$event")"
      if [[ -n "$last_id" && "$event_id" == "$last_id" ]]; then
        break
      fi
      printf '%s\n' "$event" >> "$new_events_file"
    done < <(jq -c '.[]' <<<"$events_json")

    if [[ -s "$new_events_file" ]]; then
      while IFS= read -r event; do
        payloads="$(build_payload "$event" "$repo" 2>/dev/null || true)"
        if [[ -n "$payloads" ]]; then
          while IFS= read -r payload; do
            [[ -z "$payload" ]] && continue
            pr_number="$(jq -r '.client_payload.pr_number // ""' <<<"$payload")"
            lock_file="$state_dir/$repo/pr-${pr_number}.lock"
            if [[ -n "$pr_number" && -f "$lock_file" ]]; then
              log SKIP "Review already in progress for $repo#$pr_number — skipping"
              continue
            fi
            if [[ -n "$pr_number" ]]; then mkdir -p "$(dirname "$lock_file")" && touch "$lock_file"; fi
            (
              if ! bash "$_root/workflows/dispatch.sh" "$payload"; then
                log WARN "Dispatch failed for $repo event $(jq -r '.id // "unknown"' <<<"$event")"
              fi
              [[ -n "$pr_number" ]] && rm -f "$lock_file"
            ) &
          done <<<"$payloads"
        fi
      done < <(tac "$new_events_file")
    fi

    rm -f "$new_events_file"
    printf '%s' "$newest_id" > "$state_file"
  done

  sleep "$poll_interval"
done
