#!/usr/bin/env bash
set -euo pipefail

pass=0
fail=0

check() {
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

running_json='{"statusCheckRollup":[{"name":"build","state":"PENDING"}]}'
running_count="$(jq -r '
  [.statusCheckRollup[]?
   | ((.conclusion // .state // "") | ascii_upcase) as $s
   | select(
       $s == "PENDING" or
       $s == "IN_PROGRESS" or
       $s == "QUEUED" or
       $s == "EXPECTED" or
       $s == "WAITING" or
       $s == "REQUESTED"
     )
  ] | length
' <<<"$running_json")"
check "ci running detected" "1" "$running_count"

allowed_json='{"statusCheckRollup":[{"name":"build","conclusion":"SUCCESS"},{"name":"lint","conclusion":"SKIPPED"},{"name":"qa","conclusion":"NEUTRAL"}]}'
failed_count_allowed="$(jq -r '
  [.statusCheckRollup[]?
   | ((.conclusion // .state // "") | ascii_upcase) as $s
   | select($s != "SUCCESS" and $s != "NEUTRAL" and $s != "SKIPPED")
  ] | length
' <<<"$allowed_json")"
check "ci success-neutral-skipped allowed" "0" "$failed_count_allowed"

failed_json='{"statusCheckRollup":[{"name":"test","conclusion":"FAILURE"}]}'
failed_count="$(jq -r '
  [.statusCheckRollup[]?
   | ((.conclusion // .state // "") | ascii_upcase) as $s
   | select($s != "SUCCESS" and $s != "NEUTRAL" and $s != "SKIPPED")
  ] | length
' <<<"$failed_json")"
check "ci failure detected" "1" "$failed_count"

label_json='{"labels":[{"name":"Do-Not-Merge"}]}'
do_not_merge="$(jq -r '[.labels[]? | (.name // "") | ascii_downcase | select(. == "do-not-merge")] | length > 0' <<<"$label_json")"
check "do-not-merge label detected case-insensitive" "true" "$do_not_merge"

threads_json='{"reviewThreads":[{"isResolved":false},{"isResolved":true}]}'
unresolved="$(jq -r '[.reviewThreads[]? | select(.isResolved == false)] | length' <<<"$threads_json")"
check "unresolved thread count" "1" "$unresolved"

echo "Results: pass=$pass fail=$fail"
[[ "$fail" -eq 0 ]]
