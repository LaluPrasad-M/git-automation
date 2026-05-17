#!/usr/bin/env bash
set -euo pipefail

gh_post_pr_comment() {
  local repo="$1" pr="$2" body="$3"
  gh pr comment "$pr" --repo "$repo" --body "$body"
}
