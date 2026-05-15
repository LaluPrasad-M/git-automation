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
  pr_checkout_branch="sentinel-pr-${PR_NUMBER}-head"

  # Use pull/<number>/head so checkout works for both same-repo and fork PRs.
  if git fetch --depth=1 origin "pull/${PR_NUMBER}/head:${pr_checkout_branch}"; then
    git checkout "$pr_checkout_branch"
  else
    # Fallback to detached checkout by head SHA when pull ref fetch is unavailable.
    head_sha="$(gh pr view "$PR_NUMBER" --repo "$TARGET_REPO" --json headRefOid --jq '.headRefOid // empty')"
    if [[ -z "$head_sha" ]]; then
      echo "Unable to resolve PR head SHA for ${TARGET_REPO}#${PR_NUMBER}" >&2
      exit 1
    fi
    git fetch --depth=1 origin "$head_sha"
    git checkout --detach FETCH_HEAD
  fi
fi

echo "WORKSPACE=$work_dir/target" >> "$GITHUB_ENV"
