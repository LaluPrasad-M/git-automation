# PR Merge Decision

Evaluate whether PR #{{PR_NUMBER}} in {{TARGET_REPO}} is safe to merge.

## Current State

- Approvals: {{APPROVAL_COUNT}} / {{MIN_APPROVALS}}
- CI Status: {{CI_STATUS}}
- Unresolved Threads: {{UNRESOLVED_THREADS}}
- Merge Method: {{MERGE_METHOD}}

## Decision Criteria

1. No unresolved critical concerns remain.
2. Current state is consistent with policy gates and repository safety.
3. No obvious release-blocking risk is visible from the final PR state.

## Output Contract

Print exactly one line:

- `DECISION: MERGE`
- `DECISION: HOLD - <specific reason>`

Use HOLD when uncertain.
