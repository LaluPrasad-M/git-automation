# Performance & Limits

All numbers are derived from the actual code — nothing is estimated.

---

## Recommended Values

These are practical starting points. Adjust based on your repo activity and API tier.

| Variable | Default | Recommended | Why |
|---|---|---|---|
| `POLL_INTERVAL_SECONDS` | 60 | **60–300** | 20s burns ~180 GitHub API calls/hour just polling, before any reviews. 60s is fine for active repos. 300s for low-traffic repos. GitHub Events API has a 60s cache anyway — polling faster than that returns stale data. |
| `MAX_TURNS` | 5 | **5–8** | 5 is enough for small-to-medium PRs. Increase to 8 for PRs with many skill files where Claude needs more turns to read them. Beyond 10 rarely improves results and significantly increases cost and latency. |
| `MAX_DIFF_LINES` | 2500 | **1000–2000** | 2500 lines means a very large prompt — expect 2–5 min LLM latency and high token cost. 1000–1500 is a better balance. Encourage smaller PRs rather than raising this. |
| `MAX_MERGE_POLLS` | 20 | **20** | 20 × 3 min = 1 hour max wait for CI. Increase only if your CI regularly takes longer than an hour. |

---

## GitHub API

**Rate limit:** 5,000 requests/hour per authenticated PAT. The sentinel uses a single `GH_TOKEN` for all calls.

### Per poll cycle

One call per watched repo every `POLL_INTERVAL_SECONDS` (default 60s):

- `GET /repos/{owner}/{repo}/events?per_page=100` — fetch recent events (`events_service.sh`)

### Per PR review

**Fixed calls — always happen:**

1. `gh pr view author,state,title,reviewRequests` — classify the event, determine action type (`classify.sh`)
2. `gh pr view reviewRequests,author` — check reviewer eligibility (`review.sh`)
3. `gh pr view reviews` — skip if already approved (`review.sh`)
4. `gh pr view commits` — set git fetch depth to cover all PR commits (`workspace_service.sh`)
5. `gh pr view title,author,additions,deletions,changedFiles` — build LLM prompt context and check diff size limit (`review.sh`)
6. `gh pr diff` — fetch the full diff to embed in the prompt (`review.sh`)
7. `gh pr view headRefOid` — resolve commit SHA to anchor inline comments (`review.sh`)
8. One verdict call: `gh pr comment` / `gh pr review --request-changes` / `gh pr review --approve` (`review.sh`)

**Fixed total: 8 calls** for an own PR via `PullRequestEvent`.

**Conditional calls:**

- **+1** if non-own PR — `gh pr view reviewRequests` in `dispatch.sh` (verify sentinel is assigned reviewer)
- **+1** if `PushEvent` trigger — `gh pr list --head $branch` in `listen.sh` (resolve which PR the branch belongs to)
- **+1** if git fallback checkout — `gh pr view headRefOid` in `workspace_service.sh` (when `pull/$N/head` ref fetch fails)
- **+N** for inline findings — one `gh api pulls/$pr/comments` per finding the LLM returns

**Practical range:** 8–10 fixed calls + 1 per finding.
A review with 5 findings on an own PR = **13 calls total**.

### Per merge

`merge.sh` re-checks the PR every 180s, up to `MAX_MERGE_POLLS` (default 20) times. Each poll iteration:

- `gh pr view reviews,reviewThreads,statusCheckRollup,mergeable,title,labels` — full gate check

On success (2 more calls):
- `gh pr comment` — notify that merge is starting
- `gh pr merge` — execute the merge

**Worst case: 22 calls** (20 polls + 2 final). Best case (CI already green): **3 calls**.

### Known redundancy

`reviewRequests` is fetched 3 times for non-own PR reviews across `classify.sh`, `dispatch.sh`, and `review.sh`. These are separate scripts with no shared state, so each fetches independently.

### Pagination limits

These are silent truncation points — no error is raised if a PR exceeds them:

- Events API: **100 events** per poll (`per_page=100` in `events_service.sh`)
- GraphQL review threads: **100 threads** per PR (`first:100` in `graphql_service.sh`)
- GraphQL thread comments: **50 comments** per thread (`first:50` in `graphql_service.sh`)

---

## Anthropic API

The sentinel uses the **Claude Code CLI** (`claude`), not the raw HTTP API. Each `call_llm` invocation is one multi-turn session.

**Calls per workflow:**

- `review.sh` — 1 call, up to `MAX_TURNS` (default 5) turns, tools: `cat,grep,find,head,tail`
- `approve.sh` — 1 call, up to `MAX_TURNS` turns, tools: `gh,cat,grep`
- `followup.sh` — up to 2 calls per unresolved thread (one to verify fix, one to validate rationale), tools: `cat,grep`

Each turn is one round-trip to the model. A 5-turn review makes up to 5 Anthropic requests internally.

**Token consumption:**

The review prompt contains the template + skill files + the full PR diff + the response schema. A 2,500-line diff can consume 50,000–150,000 input tokens depending on line length. Each finding adds output tokens.

**On rate limit failure:** `call_llm` exits non-zero, `|| true` catches it, and the PR gets a comment: `"Auto-review skipped: LLM call returned no output."` No retry is attempted.

**Model default:** `claude-sonnet-4-6` — override with `ANTHROPIC_MODEL` in `.env`.

**OpenAI stub:** Single-turn only. Tools and `max_turns` are not implemented. The response will be raw text and the JSON parser will fail, falling back to a raw-text PR comment.

---

## Git Operations

Git uses HTTPS with `GH_TOKEN` embedded in the URL. Not counted against GitHub's API rate limit.

- **First review of a repo:** `git clone --depth=1` into `/tmp/sentinel-workspace/target`
- **Every review:** `git fetch --depth=N pull/$PR/head` (N = commit count + 1)
- **Fallback:** `git fetch $head_sha` if the pull ref fetch fails

The workspace is reused — clone happens once per repo, fetch on every subsequent review.

---

## Docker / Memory

Memory pressure points in the container:

- **Large diffs:** `$diff_output` is a bash string variable. A 2,500-line diff is ~200KB.
- **LLM response:** `$raw_output` is typically 5–50KB.
- **Concurrent dispatches:** each background subshell forks the parent process, duplicating its memory.

If the container exits with code **137**, it was OOM-killed. Mitigation: lower `MAX_DIFF_LINES` or `MAX_TURNS`, or set `deploy.resources.limits.memory` in `docker-compose.yml`.

---

## End-to-end summary (own PR, review to merge)

| Phase | GitHub API | Anthropic |
|---|---|---|
| Poll cycle | 1 | — |
| Review (5 findings) | ~13 | 1 session (up to 5 turns) |
| Merge (CI passes first poll) | 3 | — |
| **Total** | **~17** | **1** |
