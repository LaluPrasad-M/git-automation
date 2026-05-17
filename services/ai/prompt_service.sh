#!/usr/bin/env bash
set -euo pipefail

# build_skill_manifest <dir> <exclude_filename>
# Prints a bullet list of skill files with their descriptions.
build_skill_manifest() {
  local dir="$1"
  local exclude_file="${2:-}"
  local manifest=""
  local skill_file skill_name description
  while IFS= read -r skill_file; do
    [[ -z "$skill_file" ]] && continue
    skill_name="$(basename "$skill_file")"
    description="$(sed -n 's/^description:[[:space:]]*//p' "$skill_file" | head -1 | tr -d '"')"
    [[ -z "$description" ]] && description="$skill_name"
    manifest+="- $skill_name: $description"$'\n'
  done < <(find "$dir" -maxdepth 1 -type f ! -name "$exclude_file" | sort)
  printf '%s' "$manifest"
}
