#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 '<client_payload_json>'" >&2
  exit 2
fi

payload="$1"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
workspace="${WORKSPACE:-$repo_root}"

if [[ ! -d "$workspace" ]]; then
  if [[ -d "$repo_root" ]]; then
    workspace="$repo_root"
  elif [[ -d "/app" ]]; then
    workspace="/app"
  else
    echo "Valid WORKSPACE not found: $workspace" >&2
    exit 1
  fi
fi

export WORKSPACE="$workspace"
export GITHUB_WORKSPACE="${GITHUB_WORKSPACE:-$workspace}"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

classify_out="$tmp_dir/classify.out"
policy_out="$tmp_dir/policy.out"
guard_out="$tmp_dir/guard.out"
policy_env="$tmp_dir/policy.env"

export GITHUB_OUTPUT="$classify_out"
bash scripts/classify.sh "$(jq -c '.client_payload // .' <<<"$payload")"

action="$(grep -E '^action=' "$classify_out" | tail -n1 | cut -d= -f2-)"
pr_number="$(grep -E '^pr_number=' "$classify_out" | tail -n1 | cut -d= -f2-)"
pr_author="$(grep -E '^pr_author=' "$classify_out" | tail -n1 | cut -d= -f2-)"
target_repo="$(grep -E '^target_repo=' "$classify_out" | tail -n1 | cut -d= -f2-)"

if [[ "$action" == "skip" ]]; then
  exit 0
fi

if [[ -z "$action" || "$action" == "unknown" ]]; then
  echo "No runnable action for payload (action=${action:-empty})"
  exit 0
fi

export GITHUB_OUTPUT="$policy_out"
export GITHUB_ENV="$policy_env"
bash scripts/load-policy.sh "$target_repo"

policy_file="$(grep -E '^policy_file=' "$policy_out" | tail -n1 | cut -d= -f2-)"
prompt_dir="$(grep -E '^prompt_dir=' "$policy_out" | tail -n1 | cut -d= -f2-)"

export TARGET_REPO="$target_repo"
export POLICY_FILE="$policy_file"
export GITHUB_OUTPUT="$guard_out"
bash scripts/guards.sh \
  --author "$pr_author" \
  --bot-user "${MY_GITHUB_USERNAME:-}" \
  --action "$action" \
  --pr-number "$pr_number"

should_skip="$(grep -E '^should_skip=' "$guard_out" | tail -n1 | cut -d= -f2-)"
if [[ "$should_skip" == "true" ]]; then
  echo "Guard requested skip for $target_repo#$pr_number action=$action"
  exit 0
fi

export PR_NUMBER="$pr_number"
export PROMPT_DIR="$prompt_dir"

bash scripts/setup-workspace.sh

case "$action" in
  review)
    bash scripts/review.sh
    ;;
  followup)
    bash scripts/thread-followup.sh
    ;;
  approve)
    bash scripts/approve.sh
    ;;
  merge)
    bash scripts/merge.sh
    ;;
  *)
    echo "Unsupported action: $action"
    ;;
esac
