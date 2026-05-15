# Claude Git Sentinel

Claude Git Sentinel is a private control-plane repository that automates PR review, approval, follow-up, and merge workflows across one or more target repositories.

## What is included

- Dispatch-driven workflow orchestration in GitHub Actions
- Optional Docker-based local event listener (`docker compose up`) for no-settings-access mode
- Multi-repo policy resolution and prompt overrides
- Safety guards (self-filter, rate limit, dry-run)
- Auto review/follow-up/approve/merge pipelines
- Test fixtures and shell-based sanity tests

## Required secrets and variables

### Secrets

- `MY_PAT`
- `ANTHROPIC_API_KEY`
- `NOTIFICATION_FEED_URL`

### Variables

- `MY_GITHUB_USERNAME`
- `TARGET_REPOS_JSON` (recommended)
- `TARGET_REPO` (optional fallback)
- `EXCEPTION_REGISTRY_ISSUE_NUMBER` (optional, recommended for persistent follow-up learning)

## Quick setup

1. Configure secrets and variables in the control repository.
2. Update `config/sentinel.yml` defaults.
3. Add per-repo files under `config/repos/` (for example `Zipstorm-spot-v2.yml`).
4. (Optional) Add per-repo prompt overrides under `config/prompts/repos/<owner>/<repo>/`.
5. Prompt directory resolution is exact-match only. If `config/prompts/repos/<owner>/<repo>/` is missing, defaults are used.
6. Trigger `.github/workflows/self-test.yml`.
7. Send a test `repository_dispatch` event.

See docs in `docs/SETUP_GUIDE.md` and `docs/TROUBLESHOOTING.md`.
