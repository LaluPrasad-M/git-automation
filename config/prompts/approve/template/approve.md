# PR Approval Decision

You are deciding whether PR #{{PR_NUMBER}} in {{TARGET_REPO}} should be approved.

## Preconditions (already verified by pipeline)

- CI checks passed: {{CI_STATUS}}
- No unresolved sentinel review threads

## Process

1. Read the diff: `gh pr diff {{PR_NUMBER}} --repo {{TARGET_REPO}}`
2. If skill files are provided below, use them to assess approval risk
3. If no skill files are provided, apply general judgment: block only on clear regressions, security flaws, or data loss risk
4. Do not block for style or minor concerns — use COMMENT instead

## Output (mandatory)

Print exactly one line:

- `DECISION: APPROVE`
- `DECISION: COMMENT - <reason>`
- `DECISION: BLOCK - <reason>`
