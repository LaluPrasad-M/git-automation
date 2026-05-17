#!/usr/bin/env bash
set -euo pipefail

gh_post_pr_review_approve() {
  local repo="$1" pr="$2" body="$3"
  gh pr review "$pr" --repo "$repo" --approve --body "$body"
}

gh_post_pr_review_request_changes() {
  local repo="$1" pr="$2" body="$3"
  gh pr review "$pr" --repo "$repo" --request-changes --body "$body"
}

gh_post_inline_comment() {
  local repo="$1" pr="$2" sha="$3" path="$4" line="$5" body="$6"
  gh api "repos/$repo/pulls/$pr/comments" \
    -f body="$body" \
    -f commit_id="$sha" \
    -f path="$path" \
    -F line="$line" \
    -f side="RIGHT"
}

gh_reply_to_review_comment() {
  local repo="$1" pr="$2" in_reply_to="$3" body="$4"
  gh api "repos/$repo/pulls/$pr/comments" \
    -f body="$body" \
    -F in_reply_to="$in_reply_to" >/dev/null
}
