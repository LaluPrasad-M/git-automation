# Review And Approve Decision Flows

This document captures the exact runtime flow for review and approve actions in the current Git Sentinel implementation.

## State Machine

1. `REVIEW_REQUESTED` -> run review policy and post inline findings.
2. `FOLLOWUP_PENDING` -> wait for external replies on bot-owned threads.
3. `FOLLOWUP_VERIFY` -> verify fixes or rationale for each replied thread.
4. `FOLLOWUP_RESOLVE` -> resolve verified threads or accepted exceptions.
5. `REVIEW_RECHECK` -> when all sentinel threads are resolved, rerun review policy on latest code state.
6. `APPROVE_GATE` -> allow approve runner only when no unresolved sentinel threads remain.

## Review Severity Policy

Review runner applies this policy after posting findings:

1. Critical findings present:
   - post all findings
   - submit `REQUEST_CHANGES`
2. No critical, but major findings present:
   - post all findings
   - do not approve and do not block (comment-only)
3. No critical and no major:
   - if minor/nit findings exist, post findings and approve
   - if no findings, approve directly

## Shared Entry Path

1. GitHub receives a `repository_dispatch` event and triggers [sentinel workflow](../../.github/workflows/sentinel.yml).
2. `classify` job runs:
   - [scripts/classify.sh](../../scripts/classify.sh)
   - [scripts/load-policy.sh](../../scripts/load-policy.sh)
   - [scripts/guards.sh](../../scripts/guards.sh)
3. If `should_skip != true`, workflow routes by action:
   - `review` -> `auto-review`
   - `followup` -> `auto-followup`
   - `approve` -> `auto-approve`

## Review Flow

### How Review Is Decided

The classifier in [scripts/classify.sh](../../scripts/classify.sh) decides `action=review` using this priority order:

1. If `client_payload.action` is present, it is used directly.
2. Else if `feed_title` contains `review requested` or `requested your review`, action is `review`.
3. Else if `feed_title` contains `commented` or `requested changes`:
   - action is `followup`
4. Else if `feed_title` contains approval keywords, action is `merge`.
5. Else if `feed_title` contains CI/check keywords, action is `approve`.
6. Else fallback to GitHub PR metadata: if bot user is in `reviewRequests`, action is `review`.
7. If PR state is not OPEN, action is `skip`.

Routing then happens in [sentinel workflow](../../.github/workflows/sentinel.yml):

1. `auto-review` runs only when `action == review`.
2. Guard rails can still suppress execution when `should_skip == true`.

### Example Payload

```json
{
  "feed_title": "Review requested on PR #42",
  "feed_link": "https://github.com/Zipstorm/spot-v2/pull/42",
  "target_repo": "Zipstorm/spot-v2"
}
```

### Step-by-Step

1. Classifier parses payload and resolves:
   - `target_repo` from `client_payload.target_repo` (or feed link fallback)
   - `pr_number` from payload/link/title
   - `action=review` from explicit action or feed-title heuristics
2. Policy resolver validates target repo allow-list and resolves:
   - `POLICY_FILE`
   - `PROMPT_DIR`
3. Guards evaluate:
   - self-filter
   - dry-run mode
   - rate limit
   - action enabled in policy
4. Review job checks out target PR branch via [scripts/setup-workspace.sh](../../scripts/setup-workspace.sh).
5. Review runner [scripts/review.sh](../../scripts/review.sh):
   - reads `review.max_diff_lines` from policy
   - blocks oversized diffs with PR comment
   - builds review prompt from repo-specific or default prompt
   - injects optional review guidance from `index.md`
   - injects available review skill file names in the review folder
6. Claude returns structured JSON findings.
7. Runner posts findings as inline PR comments (path + line) when possible.
8. Runner applies severity policy (`REQUEST_CHANGES` / comment-only / approve) and posts summary.

### Review Comment Format

All reviewer comments emitted by automation (inline findings and summary review body) use this format:

1. Line 1: `Review Comment(Severity:Critical|Major|Minor|Nit)`
2. Line 2 onward: actual review content

This format is enforced in [scripts/review.sh](../../scripts/review.sh).

### Prompt Resolution Order (Review)

1. `<PROMPT_DIR>/review/review.md`
2. `<PROMPT_DIR>/review.md`
3. `config/prompts/defaults/review/review.md`
4. `config/prompts/defaults/review.md` (legacy fallback)

### Skills Resolution (Review)

1. Skills directory is `<PROMPT_DIR>/review`, else defaults to `config/prompts/defaults/review`.
2. `index.md` is treated as guidance.
3. Every other file in that folder is listed as an optional skill candidate.

## Approve Flow

### Example Payload

```json
{
  "feed_title": "All checks passed on PR #42",
  "feed_link": "https://github.com/Zipstorm/spot-v2/pull/42",
  "target_repo": "Zipstorm/spot-v2",
  "action": "approve"
}
```

### Step-by-Step

1. Classifier parses payload and resolves `action=approve` (explicit action takes precedence).
2. Policy resolver and guard checks are the same as review flow.
3. Approve job checks out target PR branch via [scripts/setup-workspace.sh](../../scripts/setup-workspace.sh).
4. Approve runner [scripts/approve.sh](../../scripts/approve.sh):
   - fetches `statusCheckRollup`
   - blocks if any non-success check exists
   - defers approval if unresolved sentinel review threads still exist
   - validates all configured `approve.required_checks` are present
   - builds approve prompt from repo-specific or default prompt
   - injects optional approve guidance from `index.md`
   - injects available approve skill file names in the approve folder
5. Claude returns one-line decision:
   - `DECISION: APPROVE` -> bot posts GitHub approval review
   - `DECISION: COMMENT - <reason>` -> bot posts a non-blocking comment and leaves PR unapproved
   - `DECISION: BLOCK - <reason>` -> bot posts blocking comment

### Prompt Resolution Order (Approve)

1. `<PROMPT_DIR>/approve/approve.md`
2. `<PROMPT_DIR>/approve.md`
3. `config/prompts/defaults/approve/approve.md`
4. `config/prompts/defaults/approve.md` (legacy fallback)

### Skills Resolution (Approve)

1. Skills directory is `<PROMPT_DIR>/approve`, else defaults to `config/prompts/defaults/approve`.
2. `index.md` is treated as guidance.
3. Every other file in that folder is listed as an optional skill candidate.

## Follow-up Flow (Thread Replies)

Triggered when classifier sets `action=followup` for non-author comment events.

1. Runner [scripts/thread-followup.sh](../../scripts/thread-followup.sh) loads unresolved review threads.
2. It filters to bot-owned sentinel findings (threads containing `SENTINEL:FINDING` marker).
3. For each thread with latest external reply:
   - positive reply path:
     - verify resolution against comment + file diff
     - if fixed, resolve thread
     - if not fixed, reply on same thread with discrepancy
   - non-positive reply path:
     - validate rationale
     - if accepted, record exception and resolve thread
     - if not accepted, reply and keep thread open
4. Exception registry recording:
   - if `EXCEPTION_REGISTRY_ISSUE_NUMBER` is configured, accepted exceptions are persisted as issue comments in control repo
5. Output includes remaining unresolved sentinel thread count.

## Notes

1. Repo-specific prompt directory matching is exact by `owner/repo` path.
2. Policy file matching is by slug format (`owner-repo.yml`).
3. Review and approve jobs use concurrency groups to avoid parallel duplication on the same PR/action.
4. Current implementation supports legacy fallback prompt paths for compatibility, but canonical structure is action-folder based.
5. Thread resolution uses GitHub review-thread GraphQL APIs and is marker-based (`SENTINEL:FINDING`).
