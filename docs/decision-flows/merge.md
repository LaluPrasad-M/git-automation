# Merge Decision Flow

## Entry Conditions

1. `PullRequestReviewEvent` with state `APPROVED` is detected by the event listener.
2. Classifier sets `action=merge` in [scripts/classify.sh](../../scripts/classify.sh).
3. Guards evaluate. Merge is skipped unless **PR author == `MY_GITHUB_USERNAME`**.

The merge flow only acts on your own PRs. PRs authored by others are skipped at the guard stage regardless of who approved them.

## Execution Order

```
classify → guards (author check) → policy → merge.sh
```

No workspace clone is performed. The entire flow uses GitHub API calls only.

## Hard Gates (exit immediately if any fail)

1. `merge.enabled` is not `true` in policy.
2. `merge.require_ci_pass` is not `true` in policy.
3. PR has a `do-not-merge` label (case-insensitive).
4. Any unresolved review thread exists.
5. Any CI check has a terminal failing state (`FAILURE`, `ERROR`, `CANCELLED`, `TIMED_OUT`).
6. Approval count is below `merge.min_approvals`.
7. GitHub reports `mergeable` status as anything other than `MERGEABLE`.

## CI Waiting Behavior

1. If any CI check is still running (`PENDING`, `IN_PROGRESS`, `QUEUED`, `EXPECTED`, `WAITING`, `REQUESTED`), wait 3 minutes.
2. Re-fetch PR state and re-evaluate all gates.
3. Loop until CI reaches a terminal state.
4. `do-not-merge` label and unresolved thread checks are evaluated on every iteration and exit immediately when present.

## Merge

When all gates pass, the sentinel posts a comment and merges using the configured `merge.method` (default: squash). No Claude prompt or decision is involved — merge is deterministic based on conditions alone.

## Policy Source

Default merge policy is defined in [config/sentinel.yml](../../config/sentinel.yml) and can be overridden per repository in [config/repos](../../config/repos).
