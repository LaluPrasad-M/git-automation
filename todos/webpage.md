# Web UI — Config & Dashboard

## Idea

Add a lightweight web interface so repos and configuration can be managed through a browser instead of editing `.env` and `policy.yml` files directly.

## What it would expose

- Edit `.env` variables — `TARGET_REPOS`, `GH_TOKEN`, `ANTHROPIC_API_KEY`, `MAX_TURNS`, `MAX_DIFF_LINES`, `POLL_INTERVAL_SECONDS`, etc.
- Per-repo settings — view and edit each repo's `policy.yml` (diff limit, merge method, required checks, min approvals)
- Skill file editor — add/edit/delete skill files under `git-listeners/<owner>/<repo>/review/skills/`
- Live log stream — tail the sentinel logs in the browser
- Status — which PRs have active locks, last poll time per repo, container health

## Security note

`.env` contains `GH_TOKEN` and `ANTHROPIC_API_KEY`. The UI must be **localhost-only** or behind authentication — never exposed to the public internet.

## Implementation options

### Option A — Thin Node.js server in the same container
- Add a small Express server that runs alongside `listen.sh`
- Mounts the same working directory, reads/writes `.env` and `git-listeners/` directly
- No extra Docker setup — single container, single `make run`
- Node.js is already installed in the Docker image (for Claude Code)

### Option B — Separate container in docker-compose.yml
- Cleaner separation — UI container mounts the same volumes as the sentinel
- Optional: `make up-ui` to start it, `make run` stays unchanged
- Easier to disable or replace independently

## Decision needed

- Which option (A or B)?
- Minimum viable UI to start — env editor only, or also logs and status?
