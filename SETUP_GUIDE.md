# Setup Guide

## 1. Prerequisites

- GitHub CLI (`gh`) access
- Private control repository
- Fine-grained PAT with repo write access to each managed repo
- Anthropic API key

## 2. Configure secrets

- `MY_PAT`
- `ANTHROPIC_API_KEY`
- `NOTIFICATION_FEED_URL`

## 3. Configure variables

- `MY_GITHUB_USERNAME`
- `TARGET_REPOS_JSON` as JSON array, for example:
  - `["Zipstorm/spot-v2"]`
- Optional: `EXCEPTION_REGISTRY_ISSUE_NUMBER` for storing accepted follow-up rationale as persistent learning entries

## 4. Configure policies

- Set defaults in `config/sentinel.yml`
- Add repo-specific files in `config/repos/`
- Optionally add prompt overrides in `config/prompts/repos/<owner>/<repo>/`
- Prompt overrides are exact-match only; if no exact directory exists, `config/prompts/defaults/` is used

## 5. Validate

- Run workflow: `Self Test`
- Manually dispatch an event with `target_repo` and `pr_number`

## 6. Enable bridge

- Configure Zapier/IFTTT RSS trigger
- POST to `repos/{owner}/{control_repo}/dispatches`
- Include `client_payload.target_repo` in the webhook body

## 7. Local .env setup (no repo settings access)

If you cannot set GitHub Actions secrets/variables in the control repo, run locally with a `.env` file.

1. Copy `.env.example` to `.env` and fill values.
2. Load variables into your shell:

```bash
set -a
source .env
set +a
```

3. Run scripts directly, for example:

```bash
export PR_NUMBER=751
export TARGET_REPO=Zipstorm/spot-v2
repo_slug="${TARGET_REPO//\//-}"
export POLICY_FILE="config/repos/${repo_slug}.yml"
if [ ! -f "$POLICY_FILE" ]; then export POLICY_FILE="config/sentinel.yml"; fi
export PROMPT_DIR="config/prompts/repos/${TARGET_REPO}"
if [ ! -d "$PROMPT_DIR" ]; then export PROMPT_DIR="config/prompts/defaults"; fi
export WORKSPACE="$PWD"
export GITHUB_WORKSPACE="$PWD"
bash scripts/setup-workspace.sh
bash scripts/review.sh
```

4. For multiple repositories, keep `TARGET_REPOS_JSON` as the full allow-list in `.env`, and change only `TARGET_REPO` (plus derived `POLICY_FILE` and `PROMPT_DIR`) per run.

For Docker listener mode, you do not need to change `TARGET_REPO` per run. The listener continuously scans every repository listed in `TARGET_REPOS_JSON`.

Notes:

- `.env` is already ignored by git.
- Keep `.env.example` as the non-secret template.

## 8. Docker 24/7 listener mode (no Zapier/IFTTT)

Run a long-lived container that polls GitHub repo events and executes local review/follow-up/approve/merge flows.

1. Ensure `.env` is populated.
2. For Docker mode, set `GH_TOKEN` in `.env` (container cannot use your host keychain `gh auth` session).
3. Docker mode uses `/app` as workspace inside the container (host absolute paths are ignored).
4. Start listener:

```bash
docker compose up -d --build
```

Or use the Makefile shortcut:

```bash
make run
```

5. View logs:

```bash
docker compose logs -f sentinel-listener
```

6. Stop listener:

```bash
docker compose down
```

Implementation files:

- `scripts/event-listener.sh` (poller)
- `scripts/run-dispatch-local.sh` (local dispatcher)
- `Dockerfile`
- `docker-compose.yml`
