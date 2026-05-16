# Setup Guide

## 1. Prerequisites

- Docker and Docker Compose
- GitHub CLI (`gh`) authenticated
- Fine-grained PAT with repo write access to each managed repo
- Anthropic API key

## 2. Clone and configure

```bash
git clone https://github.com/your-username/git-automation
cd git-automation
cp .env.example .env
```

Fill in `.env`:

| Variable | Required | Description |
|---|---|---|
| `GH_TOKEN` | Yes | GitHub PAT with repo write access |
| `ANTHROPIC_API_KEY` | Yes | Anthropic API key |
| `MY_GITHUB_USERNAME` | Yes | Your GitHub username |
| `TARGET_REPOS` | Yes | Comma-separated repos to watch, e.g. `owner/repo,owner/repo2` |
| `WORKSPACE` | Yes | Absolute path to this repo on your machine |
| `GITHUB_REPOSITORY` | Yes | This control repo in `owner/repo` format |

## 3. Scaffold per-repo config

```bash
make init
```

This reads `TARGET_REPOS` from `.env` and creates for each repo:

```
git-listeners/
└── owner/
    └── repo/
        ├── policy.yml       ← override defaults from config/sentinel.yml
        └── prompts/
            ├── review/      ← drop skill files here (e.g. frontend-reviewer.md)
            └── approve/     ← drop skill files here
```

`git-listeners/` is gitignored — your configs stay local. Re-running `make init` is safe; existing files are never overwritten.

## 4. Customise

### Policy

Edit `git-listeners/<owner>/<repo>/policy.yml` to override defaults — diff size limit, required CI checks, merge method, min approvals, etc.

### Review and approve instructions

By default `config/prompts/defaults/review/review.md` and `config/prompts/defaults/approve/approve.md` are used. To override for a specific repo, create:

```
git-listeners/<owner>/<repo>/prompts/review/review.md
git-listeners/<owner>/<repo>/prompts/approve/approve.md
```

### Skill files

Skill files define domain-specific review checklists (e.g. React, Python, security). Drop them in the repo's `prompts/review/` folder:

```
git-listeners/<owner>/<repo>/prompts/review/
├── frontend-reviewer.md
├── python-reviewer.md
└── review-security.md
```

Each skill file should have a `description:` line near the top — Claude uses this to decide which skills are relevant before reading them:

```markdown
description: Expert frontend reviewer for React and TypeScript changes
```

Claude reads the diff first, then reads only the skill files relevant to what changed.

## 5. Start the listener

```bash
make run
```

The listener polls GitHub Events API for each repo in `TARGET_REPOS` and triggers review, follow-up, approve, or merge flows automatically.

```bash
make logs      # follow logs
make restart   # restart after config changes
make down      # stop
```

## 6. Validate

```bash
make test      # run shell test suite (no API calls)
make git-auth-check      # verify gh CLI auth
```

## 7. Add more repos

1. Add the repo to `TARGET_REPOS` in `.env`
2. Run `make init` — scaffolds config only for repos that don't have it yet
3. Restart the listener: `make restart`
