# Claude Git Sentinel

> Automated PR review, follow-up, approval, and merge — powered by Claude, governed by policy.

A self-hosted control plane that watches your repositories and acts as an always-on senior reviewer. It reviews PRs using domain-specific skill files, follows up on thread replies, approves when CI passes, and merges your own PRs when everything is green — all without touching your repo settings.

---

## How It Works

```
GitHub Event → classify → guard → policy → action
```

| Action     | What it does |
|------------|-------------|
| `review`   | Reads the diff, applies relevant skill files, posts inline findings |
| `followup` | Verifies developer fixes or validates decline rationale on open threads |
| `approve`  | Approves when CI passes and no unresolved threads remain |
| `merge`    | Merges your own PRs when all gates clear — fully deterministic, no Claude |

**Review triggers:** added as reviewer, PR opened/pushed by a whitelisted author, or your own PR opened/pushed  
**Own PR behaviour:** always posts a comment (never approves or requests changes on your own PRs)  
**Merge scope:** only your own PRs (`MY_GITHUB_USERNAME` is the PR author)

---

## Get Started

```bash
git clone https://github.com/your-username/git-automation
cd git-automation
cp .env.example .env    # fill in credentials and TARGET_REPOS
make init               # scaffold config for each repo
make run                # start the Docker listener
```

See [SETUP_GUIDE.md](SETUP_GUIDE.md) for full setup instructions.

---

## Configuration

### Environment

| Variable | Required | Purpose |
|---|---|---|
| `GH_TOKEN` | Yes | GitHub PAT with repo write access |
| `ANTHROPIC_API_KEY` | Yes | Anthropic API key (default provider) |
| `MY_GITHUB_USERNAME` | Yes | Your GitHub username |
| `TARGET_REPOS` | Yes | Comma-separated repos to watch (`owner/repo,owner/repo2`) |
| `AUTO_REVIEW_AUTHORS` | No | Auto-review PRs by these authors without reviewer assignment |
| `DRY_RUN` | No | `true` to suppress all write operations |
| `POLL_INTERVAL_SECONDS` | No | Override poll interval (default: 60s) |
| `LLM_PROVIDER` | No | `anthropic` (default) or `openai` |
| `ANTHROPIC_MODEL` | No | Anthropic model, default `claude-sonnet-4-6` |
| `MAX_TURNS` | No | Max LLM tool-call turns per review (default: 5) |
| `MAX_DIFF_LINES` | No | Skip review if PR exceeds this many changed lines (default: 2500) |
| `MAX_MERGE_POLLS` | No | Max CI poll attempts before merge times out (default: 20) |
| `STATE_DIR` | No | Override state/checkpoint directory |
| `WORK_DIR` | No | Override git workspace clone directory |
| `SENTINEL_LOG` | No | Override audit log file path |
| `OPENAI_API_KEY` | No | Required when `LLM_PROVIDER=openai` |
| `OPENAI_MODEL` | No | OpenAI model, default `gpt-4o` |

### Per-repo config (`git-listeners/`)

`make init` scaffolds this structure for every repo in `TARGET_REPOS`:

```
git-listeners/
└── owner/repo/
    ├── policy.yml          # override sentinel.yml defaults
    └── review/
        └── skills/         # skill files — Claude reads the relevant ones
            └── frontend-reviewer.md
```

`git-listeners/` is gitignored. Re-running `make init` is safe — existing files are never overwritten.

**Skill files:** Claude sees all skill descriptions, then reads only the ones relevant to the changed files. Add a `description:` line to each skill file so Claude can decide:

```markdown
description: Frontend reviewer for React and TypeScript changes
```

---

## Commands

```bash
make run              # build + start listener
make logs             # follow live logs
make restart          # rebuild and restart
make down             # stop
make init             # scaffold git-listeners/ for all TARGET_REPOS
make test             # run test suite (no API calls)
make git-auth-check   # verify gh CLI auth
make build            # build Docker image only
make ps               # container status
```

---

## Structure

```
commands/                         # entry points (listen.sh, init.sh)
workflows/                        # orchestration (review, approve, merge, followup)
services/                         # external calls (github/, ai/, git/)
utils/                            # shared helpers (logging, policy, guards)
config/
  sentinel.yml                    # global defaults (policy)
  prompts/
    review/template/review.md     # review prompt template (always used)
    review/skills/                # default skill files (fallback when repo has none)
    approve/template/approve.md   # approve prompt template
services/ai/
  anthropic_service.sh            # call_llm() via claude CLI
  openai_service.sh               # call_llm() via OpenAI API
git-listeners/                    # per-repo config (gitignored)
docs/                             # decision flows, troubleshooting, performance
tests/                            # shell test suite
```

---

## Safety

- **Self-filter** — own PRs are reviewed (comment-only); never approves or requests changes on your own work; followup/approve skipped on own PRs
- **Dry-run mode** — suppress all writes for safe testing
- **do-not-merge label** — respected unconditionally
- **CI gating** — approve and merge only when checks pass
- **Thread gating** — won't approve while unresolved sentinel threads exist

---

## Docs

- [Setup Guide](SETUP_GUIDE.md)
- [Docker Setup](docs/setup-docker.md)
- [GitHub Actions Setup](docs/setup-github-actions.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Review & Approve Flow](docs/decision-flows/review_and_approve.md)
- [Merge Flow](docs/decision-flows/merge.md)
- [Contributing](CONTRIBUTING.md)
