#!/usr/bin/env bash
set -euo pipefail

mode="${1:-staged}"
if [[ "$mode" != "staged" && "$mode" != "all" ]]; then
  echo "Usage: $0 [staged|all]" >&2
  exit 2
fi

files=()
if [[ "$mode" == "staged" ]]; then
  while IFS= read -r file; do
    files+=("$file")
  done < <(git diff --cached --name-only --diff-filter=ACMR)
else
  while IFS= read -r file; do
    files+=("$file")
  done < <(git ls-files)
fi

if [[ "${#files[@]}" -eq 0 ]]; then
  echo "No files to type-check ($mode)."
  exit 0
fi

failures=0
ts_detected=0

run_check() {
  local label="$1"
  shift
  if ! "$@"; then
    echo "FAILED: $label" >&2
    failures=1
  fi
}

for file in "${files[@]}"; do
  [[ -f "$file" ]] || continue
  case "$file" in
    *.sh)
      echo "Type-check (shell syntax): $file"
      run_check "$file (bash -n)" bash -n "$file"
      if command -v shellcheck >/dev/null 2>&1; then
        run_check "$file (shellcheck)" shellcheck "$file"
      fi
      ;;
    *.py)
      echo "Type-check (python compile): $file"
      if command -v python3 >/dev/null 2>&1; then
        run_check "$file (py_compile)" python3 -m py_compile "$file"
      else
        echo "FAILED: python3 is required to check $file" >&2
        failures=1
      fi
      ;;
    *.json)
      echo "Type-check (json parse): $file"
      if command -v jq >/dev/null 2>&1; then
        run_check "$file (jq empty)" jq empty "$file"
      else
        echo "FAILED: jq is required to check $file" >&2
        failures=1
      fi
      ;;
    *.yml|*.yaml)
      if command -v yq >/dev/null 2>&1; then
        echo "Type-check (yaml parse): $file"
        run_check "$file (yq e)" yq e '.' "$file" >/dev/null
      fi
      ;;
    *.ts|*.tsx)
      ts_detected=1
      ;;
  esac
done

if [[ "$ts_detected" -eq 1 ]]; then
  echo "Type-check (typescript): project"
  if [[ -f tsconfig.json ]] && command -v npx >/dev/null 2>&1; then
    run_check "typescript project (tsc --noEmit)" npx --yes tsc --noEmit
  else
    echo "FAILED: TypeScript files detected but tsconfig.json or npx is unavailable" >&2
    failures=1
  fi
fi

if [[ "$failures" -ne 0 ]]; then
  echo "Type-check failed." >&2
  exit 1
fi

echo "Type-check passed."