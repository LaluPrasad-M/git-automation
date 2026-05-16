# PR Review

You are reviewing PR #{{PR_NUMBER}} in {{TARGET_REPO}}.

## Context

- Title: {{PR_TITLE}}
- Author: {{PR_AUTHOR}}
- Files changed: {{FILES_CHANGED}} ({{LINES_ADDED}} added, {{LINES_REMOVED}} removed)

## Process

1. The full diff is provided below under **PR Diff** — do not run `gh pr diff`
2. If skill files are provided below, use them as your review checklist — they define what to look for and how to evaluate it
3. If no skill files are provided, apply general engineering judgment across correctness, security, and test coverage
4. Prioritise findings by severity: critical → major → minor → nit
5. Be specific — reference file and line where possible

## Output Format (mandatory)

Return ONLY valid JSON:

```json
{
  "summary": "string",
  "verdict": "APPROVE_READY|NEEDS_CHANGES|NEEDS_DISCUSSION",
  "test_gaps": ["string"],
  "findings": [
    {
      "severity": "critical|major|minor|nit",
      "path": "string",
      "line": 1,
      "title": "string",
      "details": "string",
      "recommendation": "string"
    }
  ]
}
```
