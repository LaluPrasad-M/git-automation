# Review and Approve Decision Flows

---

## Review Flow

### Trigger

A review runs when `MY_GITHUB_USERNAME` is added as a reviewer on a PR, or when the PR is opened by an author listed in `AUTO_REVIEW_AUTHORS`.

### Execution Order

```
classify → guards (self-filter) → reviewer/whitelist check → policy → review.sh (clone → diff check → Claude → post findings)
```

### Hard Gates

1. PR state is not `OPEN` → skip.
2. `MY_GITHUB_USERNAME` is not in the PR's reviewer list AND PR author is not in `AUTO_REVIEW_AUTHORS` → skip.
3. PR author is `MY_GITHUB_USERNAME` → skip (self-filter).
4. Diff line count exceeds `review.max_diff_lines` (default 2500) → post comment asking to split the PR into smaller tasks, stop.

### What Happens

1. Check reviewer/whitelist eligibility via GitHub API.
2. Clone target repo if not already present, otherwise fetch latest.
3. Check diff size against policy limit.
4. Fetch PR metadata (title, author, file count, additions, deletions).
5. Load review template from `config/prompts/review/template/review.md` (global; not overridable per repo).
6. If skill files exist in `git-listeners/<owner>/<repo>/review/skills/`, use them as the review checklist. If none, fall back to `config/prompts/review/skills/` defaults. Claude reads relevant ones using `cat`.
7. Call Claude with tools: `gh, git, cat, grep, find, head, tail, wc` (max 10 turns).
8. Parse JSON response: `summary`, `verdict`, `test_gaps`, `findings[]`.
9. Post each finding as an inline PR comment (path + line) where possible; fall back to summary comment.
10. Apply severity policy:
   - Any `critical` finding → `REQUEST_CHANGES`
   - Only `major` findings → comment-only (no block, no approval)
   - No critical or major → approve

### Finding Comment Format

```
Review Comment(Severity:Critical|Major|Minor|Nit)
<title>

<details>

<!-- SENTINEL:FINDING id=<hash> severity=<level> -->

Recommendation: <recommendation>
```

---

## Approve Flow

### Trigger

Approve runs when CI completes on a PR (`CheckSuiteEvent` or `CheckRunEvent` with action `completed`).

### Execution Order

```
classify → guards (skip own PRs) → policy → approve.sh (API checks only, no clone)
```

### Hard Gates

1. PR author is `MY_GITHUB_USERNAME` → skip (self-filter).
2. Any CI check is not passing (`SUCCESS`, `NEUTRAL`, `SKIPPED`) → post blocking comment, stop.
3. Any unresolved sentinel review thread exists → post deferral comment, stop.
4. Any configured `approve.required_checks` check is missing from the rollup → post blocking comment, stop.

### What Happens

1. Fetch `statusCheckRollup` for the PR.
2. Check all CI checks pass.
3. Query review threads via GraphQL, check for unresolved sentinel threads.
4. Validate required checks are present.
5. Load approve template from `config/prompts/approve/template/approve.md` (global; not overridable per repo).
6. Call Claude with tools: `gh, cat, grep` (default 5 turns).
8. Apply decision:
   - `DECISION: APPROVE` → post GitHub approval review
   - `DECISION: COMMENT - <reason>` → post non-blocking comment, leave PR unapproved
   - `DECISION: BLOCK - <reason>` → post blocking comment

---

## Follow-up Flow

### Trigger

Follow-up runs when a comment is posted on a PR. It is a **continuation of a previous review** — no reviewer/whitelist check is needed since the sentinel already established involvement when it reviewed the PR.

### Execution Order

```
classify → guards (skip own PRs) → policy →
  thread check (API, no clone) →
  if no threads: exit →
  clone (reuse if exists, fetch if not) → per-thread: verify fix or validate rationale
```

The workspace clone only happens if there are actually threads to process.

### Thread Selection

Threads are included only if:
1. Thread is unresolved.
2. Thread contains a `SENTINEL:FINDING` marker comment from the bot.
3. The latest reply on the thread is from a non-bot author.

If no threads match, the flow exits immediately with no further action.

### Per-Thread Decision

**Positive reply** (keywords: `fixed`, `addressed`, `done`, `updated`, `resolved`, `implemented`):
1. Build verify prompt with the original finding, developer reply, file path, and diff excerpt.
2. Claude returns `{ "fixed": true|false, "reason": "..." }`.
3. If `fixed=true` → resolve thread.
4. If `fixed=false` → reply explaining what still needs to be addressed.

**Non-positive reply** (keywords: `won't fix`, `defer`, `partial`, `decline`):
1. Build rationale-validation prompt with original finding and developer reply.
2. Claude returns `{ "accepted": true|false, "reason": "...", "learning": "..." }`.
3. If `accepted=true` → record exception, resolve thread.
4. If `accepted=false` → reply and keep thread open.

If Claude output cannot be parsed, a fallback reply asks the developer for clearer context.

### Exception Recording

- Accepted exceptions are written to `.state/logs/<owner>__<repo>.log` for persistent learning.
- If not set: a plain PR comment is posted acknowledging the exception.
