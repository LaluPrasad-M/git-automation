# Troubleshooting

## Workflow does not trigger

- Check event type in `repository_dispatch` matches workflow `types`.
- Verify webhook endpoint targets the control repo.

## Repo rejected by policy loader

- Ensure the repo exists in `TARGET_REPOS_JSON`.
- Ensure repo format is `owner/repo`.

## Auto-approve never happens

- Check required checks in repo policy exist in PR checks.
- Confirm all CI checks are successful.

## Merge held unexpectedly

- Verify `min_approvals` is met.
- Confirm there are no unresolved review comment threads.
- Confirm PR is not labeled `do-not-merge`.
- Confirm CI has no failing terminal checks; running checks are re-polled every 3 minutes.
- Check `mergeable` status from GitHub.

## Claude execution fails

- Confirm `ANTHROPIC_API_KEY` is set and valid.
- Confirm `@anthropic-ai/claude-code` installed in runner.
