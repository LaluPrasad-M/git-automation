# Merge Decision Flow

This document captures the current merge flow implemented by the workflow and scripts.

## Entry Conditions

1. `repository_dispatch` triggers [sentinel workflow](../../.github/workflows/sentinel.yml).
2. Classifier sets `action=merge` in [scripts/classify.sh](../../scripts/classify.sh) (explicit action or approval-style feed title).
3. Workflow runs `auto-merge` only when:
   - `action == merge`
   - `should_skip != true`

## Merge Runner

The merge job executes [scripts/merge.sh](../../scripts/merge.sh).

## Hard Gates (Skip On Failure)

Merge exits early (no merge) when any of the following is true:

1. `merge.enabled` is not `true` in policy.
2. `merge.require_ci_pass` is not `true` in policy.
3. PR has label `do-not-merge` (case-insensitive match).
4. Any unresolved review thread exists (open comment threads).
5. Any CI check has a terminal non-passing state (for example `FAILURE`, `ERROR`, `CANCELLED`, `TIMED_OUT`).
6. Approval count is below `merge.min_approvals`.
7. GitHub reports PR `mergeable` status as anything other than `MERGEABLE`.

## CI Waiting Behavior

1. If CI checks are still running (`PENDING`, `IN_PROGRESS`, `QUEUED`, `EXPECTED`, `WAITING`, `REQUESTED`), merge waits 3 minutes.
2. After 3 minutes, merge re-fetches PR state and re-checks all gates.
3. This loop continues until CI reaches terminal states.
4. If terminal CI is failing, merge is skipped.
5. `do-not-merge` and unresolved-thread checks are evaluated on every poll and skip immediately (no waiting) when present.

## Prompt Construction

When all hard gates pass, merge prompt is built from:

1. `<PROMPT_DIR>/merge/merge.md`
2. `<PROMPT_DIR>/merge.md`
3. `config/prompts/defaults/merge/merge.md`
4. `config/prompts/defaults/merge.md` (legacy fallback)

Prompt variables include:

- `PR_NUMBER`
- `TARGET_REPO`
- `APPROVAL_COUNT`
- `MIN_APPROVALS`
- `CI_STATUS`
- `UNRESOLVED_THREADS`
- `MERGE_METHOD`

Optional merge guidance is appended from merge `index.md` and sibling skill files.

## Decision Contract

Claude returns a final decision line:

1. `DECISION: MERGE`
2. `DECISION: HOLD - <reason>`

## Final Actions

1. If `DECISION: MERGE`:
   - Post PR comment: merge is proceeding.
   - Execute `gh pr merge` using configured `merge.method`.
2. If `DECISION: HOLD - ...`:
   - Post PR comment with hold reason.
   - Do not merge.

## Policy Source

Default merge policy values are defined in [config/sentinel.yml](../../config/sentinel.yml), and can be overridden per repository in [config/repos](../../config/repos).
