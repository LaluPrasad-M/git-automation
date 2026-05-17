#!/usr/bin/env bash
set -euo pipefail

gh_repo_events() {
  local repo="$1"
  env GH_PAGER=cat gh api "repos/$repo/events?per_page=100" 2>/dev/null || echo '[]'
}
