# Reply Follow-up Decision Flow

This document captures the runtime flow for reply follow-up in the current Git Sentinel implementation.

## State Machine

1. `COMMENT_EVENT` -> classifier maps comment events to `followup`.
2. `FOLLOWUP_PENDING` -> wait for external replies on sentinel finding threads.
3. `FOLLOWUP_VERIFY` -> verify claimed fixes or validate rationale.
4. `FOLLOWUP_RESOLVE` -> resolve accepted threads or post keep-open response.
5. `FOLLOWUP_COUNT` -> publish remaining unresolved sentinel-thread count.

## Shared Entry Path

1. GitHub receives `repository_dispatch` and triggers [sentinel workflow](../../.github/workflows/sentinel.yml).
2. `classify` runs [scripts/classify.sh](../../scripts/classify.sh), [scripts/load-policy.sh](../../scripts/load-policy.sh), and [scripts/guards.sh](../../scripts/guards.sh).
3. If `should_skip != true`, workflow routes:
   - `followup` -> `auto-followup`

## How Action Is Chosen For Comment Events

Classifier logic in [scripts/classify.sh](../../scripts/classify.sh):

1. If `client_payload.action` exists, it wins.
2. Else if title includes `commented` or `requested changes`, set `action=followup`.
3. If PR state is not OPEN, set `action=skip`.

## Follow-up Flow

### When It Runs

1. Workflow condition: `action == followup` on `auto-followup` in [sentinel workflow](../../.github/workflows/sentinel.yml).
2. Script entrypoint: [scripts/thread-followup.sh](../../scripts/thread-followup.sh).

### Thread Selection

1. Query review threads from GitHub GraphQL.
2. Keep unresolved threads only.
3. Keep only threads containing bot marker `SENTINEL:FINDING`.
4. Keep only threads where latest comment is from non-bot author.

### Per-Thread Decision

1. Detect reply type with keyword heuristics:
   - positive/resolution replies: `fixed`, `addressed`, `updated`, `resolved`, etc.
   - decline/defer replies: `won't fix`, `later`, `defer`, `partial`, etc.
2. Positive reply path:
   - build verify prompt with finding, developer reply, file path, and diff excerpt
   - expect JSON: `{ "fixed": true|false, "reason": "..." }`
   - if `fixed=true`, resolve thread
   - else post thread reply explaining unresolved gap
3. Non-positive reply path:
   - build rationale-validation prompt
   - expect JSON: `{ "accepted": true|false, "reason": "...", "learning": "..." }`
   - if `accepted=true`, record exception and resolve thread
   - else post thread reply and keep thread open
4. If output is not parseable JSON, post fallback reply requesting clearer context.

### Exception Recording

1. If `EXCEPTION_REGISTRY_ISSUE_NUMBER` is configured, accepted exceptions are written as issue comments in control repo.
2. If not configured, bot posts a PR-level exception note.

### Output Contract

1. Script writes `remaining_sentinel_threads` to GitHub outputs.
2. Value equals unresolved bot-owned sentinel finding threads after processing.
