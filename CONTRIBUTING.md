# Contributing

Thanks for your interest in improving Claude Git Sentinel.

## Quick Start

1. Fork the repository.
2. Create a branch: `git checkout -b feat/your-change`.
3. Run local checks:
   - `make test`
4. Update docs when behavior changes.
5. Open a pull request with a clear summary and motivation.

## Contribution Guidelines

- Keep changes focused and minimal.
- Prefer policy/config updates over hardcoded behavior.
- Preserve safety guardrails (self-filter, dry-run).
- Add or update tests for non-trivial behavior changes.

## Pull Request Checklist

- [ ] Scripts pass bash syntax checks.
- [ ] Relevant tests pass (`make test`).
- [ ] README or setup docs updated if required.
- [ ] No secrets or local runtime state committed.

## Commit Style

Use clear, scoped commit messages, for example:

- `feat: add multi-repo allow-list parsing`
- `fix: handle missing check suite PR mappings`
- `docs: clarify docker listener behavior`

## Reporting Issues

When opening issues, include:

- Expected behavior
- Actual behavior
- Reproduction steps
- Logs or command output (redacted)
- Environment details (OS, shell, local vs GitHub Actions mode)
