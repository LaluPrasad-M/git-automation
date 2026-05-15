# Roadmap

## Near Term

- Add dedicated tests for multi-repo allow-list parsing.
- Add action-level metrics (counts by review/followup/approve/merge).
- Improve troubleshooting with copy-paste diagnostics commands.

## Mid Term

- Add optional chat/webhook notifications for key decisions.
- Add configurable backoff and retry strategy for transient GitHub API failures.
- Add a dry-run summary report per processed event.

## Long Term

- Add pluggable event source adapters (dispatch, listener, inbox bridge).
- Add policy linting command to validate repo config consistency.
- Add optional dashboard view for processed events and outcomes.
