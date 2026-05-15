#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
workspace="${WORKSPACE:-$repo_root}"

if [[ ! -d "$workspace" ]]; then
  if [[ -d "$repo_root" ]]; then
    workspace="$repo_root"
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

if [[ -z "${TARGET_REPOS_JSON:-}" ]]; then
  echo "TARGET_REPOS_JSON is required" >&2
  exit 1
fi

poll_interval="${POLL_INTERVAL_SECONDS:-60}"
state_dir="${STATE_DIR:-$workspace/.state/event-listener}"
mkdir -p "$state_dir"

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
        if [[ -n "${AUTO_REVIEW_AUTHORS:-}" ]]; then
          pr_author="$(jq -r '.payload.pull_request.user.login // empty' <<<"$event_json")"
          IFS=',' read -ra whitelist <<< "$AUTO_REVIEW_AUTHORS"
          for author in "${whitelist[@]}"; do
            if [[ "$pr_author" == "${author// /}" ]]; then
              jq -nc --arg repo "$repo" --arg pr "$pr_number" --arg t "review requested on PR #$pr_number" '{event_type:"pr_review_requested", client_payload:{target_repo:$repo, pr_number:$pr, feed_title:$t, action:"review", source:"docker-listener"}}'
              return 0
            fi
          done
        fi
      fi
      return 1
      ;;
    PullRequestReviewEvent)
      pr_number="$(jq -r '.payload.pull_request.number // empty' <<<"$event_json")"
      state="$(jq -r '.payload.review.state // "" | ascii_upcase' <<<"$event_json")"
      if [[ -z "$pr_number" ]]; then return 1; fi
      if [[ "$state" == "APPROVED" ]]; then
        jq -nc --arg repo "$repo" --arg pr "$pr_number" --arg t "approved PR #$pr_number" '{event_type:"pr_approval_received", client_payload:{target_repo:$repo, pr_number:$pr, feed_title:$t, action:"merge", source:"docker-listener"}}'
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
    *)
      return 1
      ;;
  esac
}

while true; do
  mapfile -t repos < <(jq -r '.[]' <<<"$TARGET_REPOS_JSON")

  for repo in "${repos[@]}"; do
    [[ -z "$repo" ]] && continue

    state_file="$state_dir/${repo//\//__}.last"
    last_id=""
    [[ -f "$state_file" ]] && last_id="$(cat "$state_file")"

    events_json="$(env GH_PAGER=cat gh api "repos/$repo/events?per_page=100" 2>/dev/null || echo '[]')"
    newest_id="$(jq -r '.[0].id // ""' <<<"$events_json")"

    if [[ -z "$newest_id" ]]; then
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
        payload="$(build_payload "$event" "$repo" || true)"
        if [[ -n "$payload" ]]; then
          bash scripts/run-dispatch-local.sh "$payload" || true
        fi
      done < <(tac "$new_events_file")
    fi

    rm -f "$new_events_file"
    printf '%s' "$newest_id" > "$state_file"
  done

  sleep "$poll_interval"
done
