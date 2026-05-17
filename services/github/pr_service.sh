#!/usr/bin/env bash

gh_get_pr() {
  local repo="$1" pr="$2" fields="${3:-title,author,state}"
  gh pr view "$pr" --repo "$repo" --json "$fields"
}

gh_get_pr_diff() {
  local repo="$1" pr="$2"
  gh pr diff "$pr" --repo "$repo"
}

gh_pr_list_for_branch() {
  local repo="$1" branch="$2"
  gh pr list --repo "$repo" --head "$branch" --state open \
    --json number,author,isDraft 2>/dev/null || echo '[]'
}
