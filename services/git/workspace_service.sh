#!/usr/bin/env bash
set -euo pipefail

_svc_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_logging="$_svc_dir/../../utils/logging.sh"
# shellcheck source=utils/logging.sh
# shellcheck disable=SC1091
source "$_logging"
# shellcheck disable=SC1091
source "$_svc_dir/../github/pr_service.sh"

trap 'log ERROR "workspace_service.sh failed at line $LINENO (exit $?)"' ERR

log INFO "Setting up workspace for ${TARGET_REPO}#${PR_NUMBER:-<no PR>}"

[[ -n "${GH_TOKEN:-}" ]]            || { log ERROR "GH_TOKEN is required";           exit 1; }
[[ -n "${MY_GITHUB_USERNAME:-}" ]]  || { log ERROR "MY_GITHUB_USERNAME is required"; exit 1; }

work_dir="${WORK_DIR:-/tmp/sentinel-workspace}"
target_dir="$work_dir/target"

# Compute fetch depth from PR commit count upfront so all git operations use the correct depth.
fetch_depth=2
if [[ -n "${PR_NUMBER:-}" ]]; then
  commit_count="$(gh_get_pr "$TARGET_REPO" "$PR_NUMBER" "commits" | jq '.commits | length')"
  [[ "$commit_count" =~ ^[0-9]+$ ]] || { log WARN "Could not fetch commit count for PR#$PR_NUMBER — using default depth"; commit_count=1; }
  fetch_depth=$(( commit_count + 1 ))
fi

if [[ -d "$target_dir/.git" ]]; then
  existing_remote="$(git -C "$target_dir" remote get-url origin 2>/dev/null || true)"
  expected_remote="https://x-access-token:${GH_TOKEN}@github.com/${TARGET_REPO}.git"
  if [[ "$existing_remote" == "$expected_remote" ]]; then
    log INFO "Workspace exists for $TARGET_REPO — fetching latest"
    git -C "$target_dir" fetch --depth="$fetch_depth" origin
  else
    log INFO "Workspace exists but for different repo — re-cloning"
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
    log INFO "Checked out PR branch $pr_checkout_branch for ${TARGET_REPO}#${PR_NUMBER}"
  else
    log WARN "Pull ref fetch failed for PR#${PR_NUMBER} — falling back to detached HEAD"
    head_sha="$(gh_get_pr "$TARGET_REPO" "$PR_NUMBER" "headRefOid" | jq -r '.headRefOid // empty')"
    if [[ -z "$head_sha" ]]; then
      log ERROR "Unable to resolve PR head SHA for ${TARGET_REPO}#${PR_NUMBER}"
      exit 1
    fi
    git fetch --depth="$fetch_depth" origin "$head_sha"
    git checkout --detach FETCH_HEAD
    log INFO "Checked out detached HEAD at $head_sha for ${TARGET_REPO}#${PR_NUMBER}"
  fi
fi

echo "WORKSPACE=$target_dir" >> "${GITHUB_ENV:-/dev/null}"
