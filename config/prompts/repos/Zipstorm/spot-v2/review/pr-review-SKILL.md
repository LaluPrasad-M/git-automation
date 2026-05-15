---
name: pr-review
description: Adversarially review a SPOT V2 PR or branch. Use for teammate PRs, external PRs, hotfixes, re-reviews, or branches that did not go through the plan lifecycle.
argument-hint: [PR number, PR URL, or branch]
---

# PR Review

Review a PR or branch like a strict code reviewer. This skill is read-only.

For PRs that went through `plan-create -> plan-review -> plan-implement -> implement-review -> pr-create`, prefer reading the pipeline and use this only for a whole-branch re-review or external review.

## Resolve The PR

1. If argument is a PR number or URL, use `gh pr view` and `gh pr diff`.
2. If argument is a branch, diff it against `develop` unless a different base is specified.
3. If no argument is provided, review the current branch against `develop`.
4. If `gh` is unavailable, fall back to `git diff` and state that PR metadata/CI were not checked.

## Load Context

Read:

- PR description and CI status when available
- full diff
- changed files in full
- root `AGENTS.md` and `CLAUDE.md`
- app-local guidance for changed paths
- backend nested `CLAUDE.md` files for backend changes
- relevant plan artifacts if changed files indicate an `apps/plans/...` plan

## Review Angles

Find real issues:

- correctness against PR description
- scope creep or unrelated refactors
- deleted or weakened tests
- missing tests for new behavior
- backend layer violations
- missing Pydantic models, `response_model`, `operation_id`, migrations, IDs, soft delete
- frontend semantic-token, accessibility, responsive, SWR, hook, and Vitest Browser Mode issues
- auth, organization scoping, input validation, data exposure, injection, secrets
- performance regressions, N+1 queries, hot path payload growth, cache issues
- dead code, TODOs, debug artifacts, unused exports
- docs that should have changed but did not

## Output

Return all findings in one grouped report:

```markdown
## Findings (N total: X blockers, Y should-fix, Z nits)

1. **[blocker]** `apps/backend/api/foo/router.py:42`: new endpoint has no `response_model`.
   Recommendation: add the domain schema as `response_model` and cover it in the route test.
```

If no issues are found, say so explicitly and list any metadata or tests that could not be checked.

Do not edit files. Do not commit.
