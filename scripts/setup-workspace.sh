#!/usr/bin/env bash
set -euo pipefail

work_dir="${WORK_DIR:-/tmp/sentinel-workspace}"
rm -rf "$work_dir"
mkdir -p "$work_dir"

git clone --depth=50 "https://x-access-token:${GH_TOKEN}@github.com/${TARGET_REPO}.git" "$work_dir/target"

cd "$work_dir/target"
git config user.name "Claude Git Sentinel"
git config user.email "${MY_GITHUB_USERNAME}@users.noreply.github.com"

if [[ -n "${PR_NUMBER:-}" ]]; then
  gh pr checkout "$PR_NUMBER" --repo "$TARGET_REPO" || {
    head_ref="$(gh pr view "$PR_NUMBER" --repo "$TARGET_REPO" --json headRefName --jq '.headRefName')"
    git fetch origin "$head_ref"
    git checkout "$head_ref"
  }
fi

echo "WORKSPACE=$work_dir/target" >> "$GITHUB_ENV"
