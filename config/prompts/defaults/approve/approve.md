# PR Approval Decision

You are evaluating whether PR #{{PR_NUMBER}} in {{TARGET_REPO}} should be approved.

## Preconditions (already checked by pipeline)

- All CI checks status: {{CI_STATUS}}

## Instructions

1. Read the diff with `gh pr diff {{PR_NUMBER}} --repo {{TARGET_REPO}}`.
2. Block if any critical risk exists: security flaws, data loss, auth bypass, migration breakage, or high-confidence regressions.
3. If there are non-critical concerns (major/minor/nit) that should be addressed via discussion, do not approve and do not block; comment only.
4. Block if test coverage is clearly insufficient for newly introduced risky behavior.
5. Approve only when no material blockers remain and no open non-critical feedback is pending response.
6. Do not block for style-only concerns.

## Output Contract

Print exactly one line:

- `DECISION: APPROVE`
- `DECISION: COMMENT - <reason>`
- `DECISION: BLOCK - <reason>`

Reason must be specific and tied to risk or pending feedback.
