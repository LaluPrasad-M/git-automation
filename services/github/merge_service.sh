#!/usr/bin/env bash

gh_merge_pr() {
  local repo="$1" pr="$2" method="$3" body="$4"
  gh pr merge "$pr" --repo "$repo" --"$method" --body "$body"
}
