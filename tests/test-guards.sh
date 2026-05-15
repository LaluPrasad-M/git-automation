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

author="botuser"
bot="botuser"
if [[ "$author" == "$bot" ]]; then res="true"; else res="false"; fi
check "self filter" "true" "$res"

author="contributor"
if [[ "$author" == "$bot" ]]; then res="true"; else res="false"; fi
check "non self" "false" "$res"

recent=21
max=20
if [[ "$recent" -ge "$max" ]]; then res="true"; else res="false"; fi
check "rate limited" "true" "$res"

recent=5
if [[ "$recent" -ge "$max" ]]; then res="true"; else res="false"; fi
check "not rate limited" "false" "$res"

echo "Results: pass=$pass fail=$fail"
[[ "$fail" -eq 0 ]]
