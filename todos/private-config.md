# Private Config for Public Repo

## Problem

The main branch is a public template. Committing `git-listeners/` config (policy.yml, skill files) or any credentials to any branch of a public repo exposes them — all branches are visible, and GitHub actively scans public repos for leaked secrets.

## What needs to stay private

- `git-listeners/<owner>/<repo>/policy.yml` — repo-specific policy overrides
- `git-listeners/<owner>/<repo>/review/skills/` — custom skill files (may contain internal patterns)
- `.env` — `GH_TOKEN`, `ANTHROPIC_API_KEY`, `MY_GITHUB_USERNAME`, `TARGET_REPOS`

## Current workaround

**Docker mode:** `.env` and `git-listeners/` are local-only (both gitignored). Works fine — nothing is ever committed.

**GitHub Actions mode:** Credentials go into repo Secrets/Variables (`Settings → Secrets and variables → Actions`). The `sentinel.yml` already reads from these. But `git-listeners/` still needs to be committed somewhere for Actions to access it during the workflow run.

## Feature: support private config without forking

Options to explore:

1. **Private fork (simplest)** — fork this repo privately, commit `git-listeners/` there, run the workflow from the fork. Main stays a clean public template. No code changes needed.

2. **External config repo** — store `git-listeners/` in a separate private repo, clone it at workflow start using a deploy key or PAT. Keeps the sentinel repo public and the config private.

3. **GitHub Environment secrets** — use GitHub Environments (not just repo-level secrets) to scope config per environment. More granular but still doesn't solve committing `git-listeners/` files.

4. **Config as encrypted secrets** — serialize `policy.yml` and skill file contents as GitHub Secrets (base64 encoded), decode them at workflow start. Hacky but avoids a separate repo.

## Recommendation

Private fork is the pragmatic path — zero code changes, full control, and `git-listeners/` can be committed freely. Option 2 (external config repo) is cleaner long-term if multiple people share one sentinel instance.

## Decision needed

- Should the project officially support and document the private fork pattern?
- Should `sentinel.yml` include a step to optionally clone an external config repo if `CONFIG_REPO` env var is set?
