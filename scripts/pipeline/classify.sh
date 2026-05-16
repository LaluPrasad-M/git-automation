#!/usr/bin/env bash
set -euo pipefail
_lib="$(dirname "${BASH_SOURCE[0]}")/../shared/lib.sh"
# shellcheck source=scripts/shared/lib.sh
# shellcheck disable=SC1091
source "$_lib"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 '<client_payload_json>'" >&2
  exit 2
fi

payload="$1"

feed_title="$(jq -r '.feed_title // ""' <<<"$payload")"
feed_link="$(jq -r '.feed_link // ""' <<<"$payload")"
explicit_action="$(jq -r '.action // ""' <<<"$payload")"
pr_number="$(jq -r '.pr_number // ""' <<<"$payload")"
approved_by="$(jq -r '.approved_by // ""' <<<"$payload")"

target_repo="$(jq -r '.target_repo // ""' <<<"$payload")"
if [[ -z "$target_repo" && -n "$feed_link" ]]; then
  target_repo="$(sed -nE 's|https://github.com/([^/]+/[^/]+)/pull/[0-9]+.*|\1|p' <<<"$feed_link" | head -n1)"
fi
if [[ -z "$target_repo" ]]; then
  target_repo="${TARGET_REPO:-}"
fi

if [[ -z "$pr_number" && -n "$feed_link" ]]; then
  pr_number="$(sed -nE 's|.*/pull/([0-9]+).*|\1|p' <<<"$feed_link" | head -n1)"
fi
if [[ -z "$pr_number" && -n "$feed_title" ]]; then
  pr_number="$(sed -nE 's|.*#([0-9]+).*|\1|p' <<<"$feed_title" | head -n1)"
fi

if [[ -z "$target_repo" || -z "$pr_number" ]]; then
  log ERROR "Unable to resolve target_repo/pr_number from payload"
  exit 1
fi

pr_url="https://github.com/$target_repo/pull/$pr_number"

pr_json="$(gh pr view "$pr_number" --repo "$target_repo" --json author,state,title,reviewRequests 2>/dev/null || echo '{}')"
pr_author="$(jq -r '.author.login // "unknown"' <<<"$pr_json")"
pr_state="$(jq -r '.state // "unknown"' <<<"$pr_json")"
pr_title="$(jq -r '.title // "unknown"' <<<"$pr_json")"

if [[ "$pr_state" != "OPEN" ]]; then
  action="skip"
else
  action="unknown"
  if [[ -n "$explicit_action" ]]; then
    if [[ "$explicit_action" == "review" || "$explicit_action" == "followup" || "$explicit_action" == "approve" || "$explicit_action" == "merge" ]]; then
      action="$explicit_action"
    fi
  elif grep -Eqi 'review requested|requested your review' <<<"$feed_title"; then
    action="review"
  elif grep -Eqi 'commented|requested changes' <<<"$feed_title"; then
    action="followup"
  elif grep -Eqi 'approved' <<<"$feed_title"; then
    action="merge"
  elif grep -Eqi 'checks|status|ci|build|test' <<<"$feed_title"; then
    action="approve"
  else
    is_requested="$(jq -r --arg me "${MY_GITHUB_USERNAME:-}" '.reviewRequests[]?.login | select(. == $me)' <<<"$pr_json" || true)"
    if [[ -n "$is_requested" ]]; then
      action="review"
    fi
  fi
fi

{
  echo "action=$action"
  echo "pr_number=$pr_number"
  echo "pr_author=$pr_author"
  echo "pr_title=$pr_title"
  echo "target_repo=$target_repo"
  echo "pr_url=$pr_url"
  echo "approved_by=$approved_by"
} >> "$GITHUB_OUTPUT"

log INFO "Classified $target_repo#$pr_number => $action by $pr_author (trigger: $feed_title) | $pr_url"
