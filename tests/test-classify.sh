#!/usr/bin/env bash
set -euo pipefail

pass=0
fail=0

assert_eq() {
  local name="$1"
  local expected="$2"
  local actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "PASS: $name"
    pass=$((pass + 1))
  else
    echo "FAIL: $name expected='$expected' actual='$actual'"
    fail=$((fail + 1))
  fi
}

feed_link="$(jq -r '.feed_link' tests/payloads/review-requested.json)"
repo_from_link="$(sed -nE 's|https://github.com/([^/]+/[^/]+)/pull/[0-9]+.*|\1|p' <<<"$feed_link" | head -n1)"
assert_eq "repo extraction from feed_link" "owner/repo" "$repo_from_link"

pr_from_link="$(sed -nE 's|.*/pull/([0-9]+).*|\1|p' <<<"$feed_link" | head -n1)"
assert_eq "pr extraction from feed_link" "42" "$pr_from_link"

target_repo="$(jq -r '.target_repo' tests/payloads/ci-passed.json)"
action="$(jq -r '.action' tests/payloads/ci-passed.json)"
assert_eq "payload repo" "owner/repo" "$target_repo"
assert_eq "payload action" "approve" "$action"

approved_by="$(jq -r '.approved_by // ""' tests/payloads/approval-received.json)"
assert_eq "approved_by present in approval payload" "some-reviewer" "$approved_by"

missing_approved_by="$(jq -r '.approved_by // ""' tests/payloads/review-requested.json)"
assert_eq "approved_by absent in non-approval payload" "" "$missing_approved_by"

echo "Results: pass=$pass fail=$fail"
[[ "$fail" -eq 0 ]]
