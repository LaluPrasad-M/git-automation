#!/usr/bin/env bash
set -euo pipefail

work_dir="${WORK_DIR:-/tmp/sentinel-workspace}"
target_dir="$work_dir/target"

commit_count="$(gh pr view "$PR_NUMBER" --repo "$TARGET_REPO" --json commits --jq '.commits | length')"
fetch_depth=$(( ${commit_count:-1} + 1 ))

if [[ -d "$target_dir/.git" ]]; then
  existing_remote="$(git -C "$target_dir" remote get-url origin 2>/dev/null || true)"
  expected_remote="https://x-access-token:${GH_TOKEN}@github.com/${TARGET_REPO}.git"
  if [[ "$existing_remote" == "$expected_remote" ]]; then
    echo "Workspace exists for $TARGET_REPO — fetching latest"
    git -C "$target_dir" fetch --depth="$fetch_depth" origin
  else
    echo "Workspace exists but for different repo — re-cloning"
    rm -rf "$target_dir"
  fi
fi

if [[ ! -d "$target_dir/.git" ]]; then
  mkdir -p "$work_dir"
  git clone --depth=1 "https://x-access-token:${GH_TOKEN}@github.com/${TARGET_REPO}.git" "$target_dir"
fi

cd "$target_dir"
git config user.name "Claude Git Sentinel"
git config user.email "${MY_GITHUB_USERNAME}@users.noreply.github.com"

if [[ -n "${PR_NUMBER:-}" ]]; then
  pr_checkout_branch="sentinel-pr-${PR_NUMBER}-head"

  # Use pull/<number>/head so checkout works for both same-repo and fork PRs.
  if git fetch --depth="$fetch_depth" origin "pull/${PR_NUMBER}/head:${pr_checkout_branch}"; then
    git checkout "$pr_checkout_branch"
  else
    # Fallback to detached checkout by head SHA when pull ref fetch is unavailable.
    head_sha="$(gh pr view "$PR_NUMBER" --repo "$TARGET_REPO" --json headRefOid --jq '.headRefOid // empty')"
    if [[ -z "$head_sha" ]]; then
      echo "Unable to resolve PR head SHA for ${TARGET_REPO}#${PR_NUMBER}" >&2
      exit 1
    fi
    git fetch --depth="$fetch_depth" origin "$head_sha"
    git checkout --detach FETCH_HEAD
  fi
fi

echo "WORKSPACE=$target_dir" >> "$GITHUB_ENV"
