#!/usr/bin/env bash
set -euo pipefail

pass=0
fail=0

_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$_root/services/ai/response_parser.sh"

check() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo "PASS: $name"; pass=$((pass+1))
  else echo "FAIL: $name expected='$expected' actual='$actual'"; fail=$((fail+1)); fi
}

# ---------------------------------------------------------------------------
# Group 1: severity_label
# ---------------------------------------------------------------------------

check "severity critical" "Critical" "$(severity_label "critical")"
check "severity major" "Major" "$(severity_label "major")"
check "severity minor" "Minor" "$(severity_label "minor")"
check "severity nit" "Nit" "$(severity_label "nit")"
check "severity unknown defaults to Minor" "Minor" "$(severity_label "unknown")"
check "severity empty defaults to Minor" "Minor" "$(severity_label "")"

# ---------------------------------------------------------------------------
# Group 2: extract_json_payload
# ---------------------------------------------------------------------------

valid_json='{"verdict":"APPROVE_READY","findings":[]}'
check "valid JSON returned as-is" "$valid_json" "$(extract_json_payload "$valid_json")"

fenced_input='Some preamble text
```json
{"verdict":"NEEDS_CHANGES","findings":[]}
```
Some trailing text'
expected_fenced='{"verdict":"NEEDS_CHANGES","findings":[]}'
check "fenced JSON extracted from markdown" "$expected_fenced" "$(extract_json_payload "$fenced_input")"

check "plain text returns exit code 1" "failed" "$(extract_json_payload "this is not json at all" || echo "failed")"
check "empty string returns exit code 1" "failed" "$(extract_json_payload "" || echo "failed")"

# ---------------------------------------------------------------------------
# Group 3: decide_action (mirrors the if/elif/else at the end of review.sh)
# ---------------------------------------------------------------------------

decide_action() {
  local is_own_pr="$1" critical_count="$2" major_count="$3"
  if [[ "$critical_count" -gt 0 ]]; then
    [[ "$is_own_pr" == "true" ]] && echo "comment" || echo "request-changes"
  elif [[ "$major_count" -gt 0 || "$is_own_pr" == "true" ]]; then
    echo "comment"
  else
    echo "approve"
  fi
}

check "own PR 0 critical 0 major → comment (never approve own)" "comment" "$(decide_action "true" 0 0)"
check "own PR 1 critical 0 major → comment (never request-changes own)" "comment" "$(decide_action "true" 1 0)"
check "own PR 0 critical 1 major → comment" "comment" "$(decide_action "true" 0 1)"
check "own PR 1 critical 1 major → comment" "comment" "$(decide_action "true" 1 1)"
check "other PR 0 critical 0 major → approve" "approve" "$(decide_action "false" 0 0)"
check "other PR 1 critical 0 major → request-changes" "request-changes" "$(decide_action "false" 1 0)"
check "other PR 0 critical 1 major → comment" "comment" "$(decide_action "false" 0 1)"
check "other PR 1 critical 1 major → request-changes (critical takes priority)" "request-changes" "$(decide_action "false" 1 1)"

echo "Results: pass=$pass fail=$fail"
[[ "$fail" -eq 0 ]]
