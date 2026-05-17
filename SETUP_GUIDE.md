# Setup Guide

## Choose your mode

| | [Docker mode](docs/setup-docker.md) | [GitHub Actions mode](docs/setup-github-actions.md) |
|---|---|---|
| Runs on | Your machine | GitHub's infrastructure |
| Always on | Yes (container) | Event-driven |
| Setup effort | Low | Higher (webhook wiring needed) |
| Full pipeline | Yes | Review only (out of the box) |

**Docker is recommended** for most cases — simpler, complete, and runs without any GitHub repo settings access.

---

## Common setup (both modes)

### 1. Clone

```bash
git clone https://github.com/your-username/git-automation
cd git-automation
```

### 2. Scaffold per-repo config

```bash
make init
```

This creates for each repo in `TARGET_REPOS`:

```
git-listeners/
└── owner/repo/
    ├── policy.yml       ← override defaults from config/sentinel.yml
    └── prompts/
        ├── review/      ← skill files (e.g. frontend-reviewer.md)
        └── approve/     ← skill files
```

### 3. Customise

**Policy** — edit `git-listeners/<owner>/<repo>/policy.yml` to override diff size limit, required CI checks, merge method, min approvals, etc.

**Instructions** — create `git-listeners/<owner>/<repo>/prompts/review/review.md` to override the default review prompt.

**Skill files** — drop domain-specific review files into `git-listeners/<owner>/<repo>/prompts/review/`. Each needs a `description:` line so Claude knows when to use it:

```markdown
description: Expert frontend reviewer for React and TypeScript changes
```

**LLM provider** — defaults to Anthropic (`claude-sonnet-4-6`). Override model or switch provider in `.env`:

```bash
# Anthropic (default)
ANTHROPIC_MODEL=claude-sonnet-4-6   # change to any supported Claude model
MAX_TURNS=5                         # max tool-call turns per review

# Switch to OpenAI
LLM_PROVIDER=openai
OPENAI_API_KEY=sk-...
OPENAI_MODEL=gpt-4o
```

Provider implementations live in `scripts/providers/`.

### 4. Add more repos

1. Add to `TARGET_REPOS` in `.env`
2. Run `make init`
3. Restart: `make restart`
