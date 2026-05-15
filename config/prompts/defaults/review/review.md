# PR Review Task

You are conducting a high-signal code review for PR #{{PR_NUMBER}} in {{TARGET_REPO}}.

## Context

- PR Title: {{PR_TITLE}}
- PR Author: {{PR_AUTHOR}}
- Files Changed: {{FILES_CHANGED}}
- Lines Added: {{LINES_ADDED}}
- Lines Removed: {{LINES_REMOVED}}

## Review Goals

1. Identify correctness bugs, security vulnerabilities, behavioral regressions, and missing tests.
2. Prioritize findings by severity: critical, major, minor, nit.
3. Ignore style-only comments unless they create maintainability risk.
4. Be precise and actionable; reference file and line when possible.

## Required Process

1. Read full diff: `gh pr diff {{PR_NUMBER}} --repo {{TARGET_REPO}}`.
2. Cross-check changed areas for edge cases and failure handling.
3. Verify compatibility and migration safety for public interfaces.
4. Call out risk concentration (auth, data, payments, infra, migrations).

## Output Contract

Post a review comment that contains exactly these sections:

- Summary: 1-3 sentences.
- Findings:
  - critical
  - major
  - minor
  - nit
- Verdict: APPROVE_READY / NEEDS_CHANGES / NEEDS_DISCUSSION
- Test Gaps: explicit list or "none"

Do not approve or request changes in this step.
