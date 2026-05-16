# Docker Setup

The Docker listener polls GitHub Events API continuously and handles the full pipeline — review, follow-up, approve, and merge.

## Prerequisites

- Docker and Docker Compose
- GitHub CLI (`gh`) authenticated on your machine
- Fine-grained PAT with repo write access to each managed repo
- Anthropic API key (or OpenAI)

## 1. Configure

```bash
cp .env.example .env
```

Fill in `.env`:

```bash
GH_TOKEN=ghp_...              # fine-grained PAT with repo write access
ANTHROPIC_API_KEY=sk-ant-...  # Anthropic API key
MY_GITHUB_USERNAME=your-login # your GitHub username
TARGET_REPOS=owner/repo1,owner/repo2
```

## 2. Scaffold and run

```bash
make init   # create git-listeners/ config per repo
make run    # build and start the listener container
```

## 3. Verify

```bash
make logs             # follow live logs
make git-auth-check   # verify gh CLI is authenticated
make test             # run test suite
```

## Commands

```bash
make run      # build + start
make logs     # follow logs
make restart  # rebuild and restart
make down     # stop
make ps       # container status
```

## How it works

The listener polls GitHub Events API every ~45 seconds (auto-calculated based on repo count). When it detects a relevant event it runs:

```
event → classify → guard → policy → action (review / followup / approve / merge)
```

Logs are written to `.state/logs/<owner>__<repo>.log`.

## Review triggers

- You are added as a reviewer on a PR
- A PR is opened by an author in `AUTO_REVIEW_AUTHORS`

## Merge

Only merges PRs you authored (`MY_GITHUB_USERNAME`). Fully deterministic — no Claude involved.
