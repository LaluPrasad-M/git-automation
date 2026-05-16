# GitHub Actions Setup

The GitHub Actions mode runs on GitHub's infrastructure. Reviews are triggered by a scheduled workflow that polls for pending review requests every 15 minutes.

> **Note:** Out of the box, only the review flow is fully covered. Follow-up, approve, and merge require additional webhook wiring to dispatch events to this control repo.

## Prerequisites

- This repo forked/cloned to your GitHub account
- Fine-grained PAT with repo write access to each managed repo
- Anthropic API key (or OpenAI)

## 1. Set repo secrets and variables

In your fork's Settings → Secrets and variables → Actions:

**Secrets:**
| Name | Value |
|---|---|
| `MY_PAT` | Fine-grained PAT with repo write access |
| `ANTHROPIC_API_KEY` | Anthropic API key |

**Variables:**
| Name | Value |
|---|---|
| `MY_GITHUB_USERNAME` | Your GitHub username |
| `TARGET_REPOS` | Comma-separated repos, e.g. `owner/repo1,owner/repo2` |

## 2. Commit your per-repo config

Unlike Docker mode, GitHub Actions checks out your repo — so `git-listeners/` must be committed (it is gitignored by default).

Either remove `git-listeners/` from `.gitignore`, or commit selectively:

```bash
git add -f git-listeners/
git commit -m "add per-repo sentinel config"
git push
```

## 3. How it works

`scheduled-check.yml` runs every 15 minutes:
1. Polls each repo in `TARGET_REPOS` for open PRs where `MY_GITHUB_USERNAME` is a requested reviewer
2. Dispatches a `pr_review_requested` event to this control repo
3. `sentinel.yml` picks it up and runs the review pipeline on a GitHub runner

## 4. Full pipeline (all actions)

To also handle follow-up, approve, and merge, you need something to dispatch events when:
- A comment is posted on a PR → `pr_comment_received`
- CI completes → `pr_ci_completed`
- A PR is approved → `pr_approval_received`

This typically requires a webhook receiver (e.g. a small server or Zapier) that listens to target repo webhooks and POSTs to:

```
POST https://api.github.com/repos/<your-org>/git-automation/dispatches
```

## Limitations vs Docker mode

| | Docker | GitHub Actions |
|---|---|---|
| Full pipeline | ✅ | Review only (without webhook wiring) |
| Always on | ✅ Container | ⏱ Every 15 min |
| Custom config | ✅ Local gitignored | Requires committing git-listeners/ |
| Setup complexity | Low | Higher |
