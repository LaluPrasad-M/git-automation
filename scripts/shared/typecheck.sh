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
yaml_lint_needed=0
yaml_lint_files=()
shellcheck_files=()

fallback_yaml_lint() {
  local file first_non_comment first_line_num first_line line_num line line_len
  local has_errors=0
  local printed_header=0

  for file in "$@"; do
    [[ -f "$file" ]] || continue
    printed_header=0

    first_non_comment="$(awk '
      /^[[:space:]]*$/ { next }
      /^[[:space:]]*#/ { next }
      { print NR":"$0; exit }
    ' "$file")"

    if [[ -n "$first_non_comment" ]]; then
      first_line_num="${first_non_comment%%:*}"
      first_line="${first_non_comment#*:}"
      if [[ "$first_line" != "---" ]]; then
        if [[ "$printed_header" -eq 0 ]]; then
          echo "$file"
          printed_header=1
        fi
        echo "  Warning: ${first_line_num}:1 [document-start] missing document start \"---\""
      fi
    fi

    line_num=0
    while IFS= read -r line || [[ -n "$line" ]]; do
      line_num=$((line_num + 1))

      if [[ "$line" =~ ^[[:space:]]*on:[[:space:]]*($|#) ]]; then
        if [[ "$printed_header" -eq 0 ]]; then
          echo "$file"
          printed_header=1
        fi
        echo "  Warning: ${line_num}:1 [truthy] truthy value should be one of [false, true]"
      fi

      line_len=${#line}
      if [[ "$line_len" -gt 80 ]]; then
        if [[ "$printed_header" -eq 0 ]]; then
          echo "$file"
          printed_header=1
        fi
        echo "  Error: ${line_num}:81 [line-length] line too long (${line_len} > 80 characters)"
        has_errors=1
      fi
    done < "$file"
  done

  return "$has_errors"
}

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
      if [[ "$file" == scripts/* ]]; then
        shellcheck_files+=("$file")
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
      if [[ "$file" == .github/workflows/* || "$file" == config/* ]]; then
        yaml_lint_needed=1
        yaml_lint_files+=("$file")
      fi
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

if [[ "${#shellcheck_files[@]}" -gt 0 ]]; then
  echo "Type-check (shell lint): shellcheck"
  if command -v shellcheck >/dev/null 2>&1; then
    for file in "${shellcheck_files[@]}"; do
      run_check "$file (shellcheck)" shellcheck "$file"
    done
  elif command -v docker >/dev/null 2>&1; then
    echo "INFO: shellcheck not found locally; using Docker image koalaman/shellcheck:stable"
    for file in "${shellcheck_files[@]}"; do
      run_check "$file (shellcheck docker)" docker run --rm -v "$PWD:/mnt" -w /mnt koalaman/shellcheck:stable "$file"
    done
  else
    echo "FAILED: shellcheck is required (install shellcheck or docker for fallback)" >&2
    failures=1
  fi
fi

if [[ "$yaml_lint_needed" -eq 1 ]]; then
  echo "Type-check (yaml lint): workflow/config files"
  if command -v yamllint >/dev/null 2>&1; then
    run_check "yamllint files" yamllint "${yaml_lint_files[@]}"
  else
    echo "WARN: yamllint not found; using fallback YAML lint rules" >&2
    echo "WARN: install yamllint for full parity (example: pipx install yamllint)" >&2
    if ! fallback_yaml_lint "${yaml_lint_files[@]}"; then
      failures=1
    fi
  fi
fi

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