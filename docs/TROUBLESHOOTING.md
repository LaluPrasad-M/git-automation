# Troubleshooting

## No logs after startup

The sentinel initialises its checkpoint on first run and sleeps for `POLL_INTERVAL_SECONDS` (default 60s) before the first poll. Logs only appear when new events arrive after the checkpoint is set.

To force a replay: delete `.state/event-listener/<owner>/<repo>.last` and restart. The sentinel will reinitialise from the current head event and pick up anything newer from that point.

## Review not triggered

- Confirm `MY_GITHUB_USERNAME` matches your GitHub login exactly (case-sensitive).
- For own PRs: review triggers on `opened`, `reopened`, and branch push — not on draft PRs.
- For other PRs: you must be added as a reviewer, or the author must be in `AUTO_REVIEW_AUTHORS`.
- Check logs for `SKIP` lines that explain why the event was not acted on.

## "Dispatch failed" in logs

Look for an `[ERROR]` line immediately before the `[WARN] Dispatch failed` — it will include the script name and line number. Common causes:

- **`review.sh failed at line N`** — LLM call failed or timed out. Check `ANTHROPIC_API_KEY` is set and valid. Increase `MAX_TURNS` if reviews are hitting the turn limit.
- **`workspace_service.sh failed at line N`** — clone or checkout failed. Verify `GH_TOKEN` has `contents: read` on the target repo.
- **`load_policy: repo not in allowlist`** — repo is not in `TARGET_REPOS`.

## Review OOM / container killed (exit 137)

The LLM call loaded too much into memory. Options:
- Add `deploy.resources.limits.memory` to `docker-compose.yml` to set a higher limit.
- Lower `MAX_TURNS` (default 5) to reduce context size.
- Lower `review.max_diff_lines` in the repo's `policy.yml` (default 2500).

## Review already in progress

If you see `SKIP — Review already in progress for owner/repo#N`, a background worker is already handling that PR. The lock file lives at `.state/event-listener/<owner>/<repo>/pr-<number>.lock` and is removed when the worker finishes. If a worker crashed without cleaning up, delete the lock file manually.

## Repo rejected by policy loader

- Ensure the repo is listed in `TARGET_REPOS` in `.env`.
- Format must be `owner/repo` (no trailing slash, no spaces).

## Auto-approve never happens

- Check `required_checks` in `git-listeners/<owner>/<repo>/policy.yml` match the actual check names on the PR.
- Confirm all required CI checks have passed (not just completed).

## Merge held unexpectedly

- `min_approvals` in policy not met.
- Unresolved review threads exist on the PR.
- PR has a `do-not-merge` label.
- CI checks are still running — the sentinel re-polls every 3 minutes.
- Check `mergeable` status on GitHub (rebase conflicts block merge).

## Claude execution fails

- Confirm `ANTHROPIC_API_KEY` is set and valid in `.env`.
- Confirm `@anthropic-ai/claude-code` is installed — the Docker image installs it via `npm install -g @anthropic-ai/claude-code`.
- Override the model with `ANTHROPIC_MODEL` if the default (`claude-sonnet-4-6`) is unavailable on your API plan.

## State file location

Checkpoints are stored at:

```
.state/event-listener/<owner>/<repo>.last
```

For example: `.state/event-listener/Zipstorm/spot-v2.last`
