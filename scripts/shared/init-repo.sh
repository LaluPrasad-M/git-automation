#!/usr/bin/env bash
set -euo pipefail

# Scaffolds git-listeners/<owner>/<repo>/ for every repo in TARGET_REPOS,
# or for a single repo passed as argument.
# Safe to re-run — skips files that already exist.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$script_dir/.." && pwd)"

scaffold_repo() {
  local repo="$1"
  local owner="${repo%/*}"
  local name="${repo#*/}"
  local dir="$root/git-listeners/${owner}/${name}"

  echo "Initialising $repo → git-listeners/${owner}/${name}/"
  mkdir -p "$dir/prompts/review" "$dir/prompts/approve"

  # --- Policy file ---
  local policy_file="$dir/policy.yml"
  if [[ -f "$policy_file" ]]; then
    echo "  policy.yml already exists — skipping"
  else
    cat > "$policy_file" <<EOF
repo: $repo

review:
  max_diff_lines: 2500

approve:
  # required_checks:
  #   - ci

merge:
  method: squash
  min_approvals: 1
EOF
    echo "  created policy.yml"
  fi

  # --- Prompt stubs ---
  echo "  created prompts/review/ and prompts/approve/ — add skill files here to extend the defaults"

  echo "Done: $repo"
}

if [[ $# -gt 0 ]]; then
  scaffold_repo "$1"
else
  if [[ -z "${TARGET_REPOS:-}" ]]; then
    echo "Usage: $0 <owner/repo>  OR set TARGET_REPOS and run with no args" >&2
    exit 1
  fi
  while IFS= read -r repo; do
    [[ -z "$repo" ]] && continue
    scaffold_repo "$repo"
  done < <(tr ',' '\n' <<<"$TARGET_REPOS" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed '/^$/d')
fi
