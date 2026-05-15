# Claude Git Sentinel

Policy-first PR automation for teams that want faster reviews without giving up control.

Claude Git Sentinel is a control-plane repository that automates pull request review, follow-up, approval, and merge decisions across one or more target repositories.

It is designed for practical engineering teams: auditable, configurable, and safe by default.

## Why This Exists

Most PR automation tools are either too rigid or too risky.

Claude Git Sentinel is built to solve that gap:

- Keep humans in control of policy
- Automate repetitive review operations
- Preserve traceability of every decision
- Support both central GitHub Actions orchestration and local Docker operation

## What You Get

- Automated PR review comments based on prompts and repository policy
- Follow-up thread processing for developer replies
- Conditional approval with CI and thread-gating checks
- Conditional merge with label, CI, approval, and mergeability gates
- Multi-repository support with per-repo policy and prompt overrides
- Author whitelist for automatic review without explicit reviewer assignment
- Exception learning capture through a central registry issue

## What Makes It Different

- Policy-first architecture: behavior is driven by yaml policy, not hidden defaults
- Guardrails by design: self-filtering, rate limits, dry-run path, and skip logic
- Exact prompt routing: repo-specific prompts resolve by owner/repo path match
- No-settings-access local mode: run automation through Docker when repo settings are restricted

## Supported Actions

| Action   | Purpose                                         |
| -------- | ----------------------------------------------- |
| review   | Generate structured review findings             |
| followup | Process replies on unresolved sentinel threads  |
| approve  | Approve only when policy and quality gates pass |
| merge    | Merge only when policy and safety checks pass   |

## How It Works

1. Event is received from repository dispatch or local listener flow.
2. scripts/classify.sh resolves target repo, PR number, and action.
3. scripts/load-policy.sh resolves policy file and prompt directory.
4. scripts/guards.sh enforces safety checks and skip rules.
5. Action runner executes one of:
   - scripts/review.sh
   - scripts/thread-followup.sh
   - scripts/approve.sh
   - scripts/merge.sh

## Quick Start

### Prerequisites

- Docker and Docker Compose
- GitHub CLI authenticated
- Anthropic API key
- .env file created from .env.example

### Start in one command

```bash
make run
```

This starts the listener container.

Optionally verify GitHub CLI auth:

```bash
make git
```

### Useful operations

```bash
make build          # build Docker image
make up             # start listener container (no rebuild)
make run            # build + start + show startup logs
make down           # stop listener container
make restart        # stop then rebuild and start
make logs           # follow listener logs
make ps             # show container status
make git            # verify gh CLI auth
make test           # run shell test suite
make typecheck      # type-check all tracked scripts
make typecheck-staged  # type-check staged files only
make install-hooks  # enable pre-commit hook via .githooks/
```

## Configuration Model

### Core env values for local mode

| Variable                          | Required | Purpose                                                                                                                                  |
| --------------------------------- | -------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `GH_TOKEN`                        | Yes      | GitHub API access                                                                                                                        |
| `ANTHROPIC_API_KEY`               | Yes      | Claude API access                                                                                                                        |
| `MY_GITHUB_USERNAME`              | Yes      | Bot account used for self-filter and thread resolution                                                                                   |
| `TARGET_REPOS_JSON`               | Yes      | Allow-list of repos the sentinel can act on                                                                                              |
| `WORKSPACE`                       | Yes      | Absolute path to this repo on your machine                                                                                               |
| `GITHUB_REPOSITORY`               | Yes      | Control-plane repo for rate-limit checks and audit logging                                                                               |
| `AUTO_REVIEW_AUTHORS`             | No       | Author rules for auto-review. Supports `username1,username2` (global) and scoped rules like `all:username1,org/repo:username2,username3` |
| `EXCEPTION_REGISTRY_ISSUE_NUMBER` | No       | Issue number in `GITHUB_REPOSITORY` for exception-learning log (thread-followup)                                                         |
| `AUDIT_ISSUE_NUMBER`              | No       | Issue number in `GITHUB_REPOSITORY` for pipeline run audit log (notify)                                                                  |
| `DRY_RUN`                         | No       | Set to `true` to suppress all write operations — useful for testing                                                                      |
| `MAX_ACTIONS_PER_HOUR`            | No       | Rate limit cap, default 20                                                                                                               |
| `POLL_INTERVAL_SECONDS`           | No       | Listener poll interval, default 60                                                                                                       |

`GITHUB_WORKSPACE` is auto-derived from `WORKSPACE` — no need to set it separately.

### TARGET_REPOS_JSON format

Both formats are accepted:

```bash
# JSON array (preferred)
TARGET_REPOS_JSON=["Zipstorm/spot-v2","Zipstorm/other-repo"]

# Comma-separated
TARGET_REPOS_JSON=Zipstorm/spot-v2,Zipstorm/other-repo
```

### Review trigger modes

The sentinel triggers a review when:

1. **Reviewer assignment** — `MY_GITHUB_USERNAME` is explicitly added as a reviewer on a PR.
2. **Author rules** — A PR is opened or reopened by a matching author from `AUTO_REVIEW_AUTHORS`, regardless of reviewer assignment. Use global rules (`username1,username2`) or scoped rules (`all:username1,org/repo:username2,username3`).

### Policy resolution

- Repo-specific: config/repos/\<owner-repo\>.yml
- Fallback: config/sentinel.yml

### Prompt resolution

- Preferred: config/prompts/repos/\<owner\>/\<repo\>/
- Fallback: config/prompts/defaults/

Prompt override lookup is exact-match only.

## Audit and Exception Logging

Two separate optional issue trackers are supported:

- **`EXCEPTION_REGISTRY_ISSUE_NUMBER`** — receives entries when a developer's non-fix rationale is accepted during follow-up. Used for exception learning.
- **`AUDIT_ISSUE_NUMBER`** — receives a one-line entry after every sentinel pipeline run (action, status, PR, run URL). Used for operational audit trail.

Both default to no-op if not configured.

## Safety and Governance

- CI-aware approval and merge gating
- Unresolved thread checks before approval and merge
- Do-not-merge label support in merge flow
- Self-filter prevents the bot from reviewing its own PRs
- Local runtime state stored under .state/ and kept out of git tracking

## Repository Structure

```
.github/workflows/   workflow orchestration and scheduled check
config/              policy and prompt configuration
scripts/             execution engine
  lib.sh             shared utilities (resolve_control_path, read_policy)
tests/               shell-based test suite and payload fixtures
docs/                setup, troubleshooting, and decision references
```

## Documentation

- SETUP_GUIDE.md
- docs/TROUBLESHOOTING.md
- docs/decision-flows/review_and_approve.md
- docs/decision-flows/reply_followup.md
- docs/decision-flows/merge.md
- docs/ROADMAP.md

## Community

- CONTRIBUTING.md
- SECURITY.md
- .github/ISSUE_TEMPLATE/bug_report.md
- .github/ISSUE_TEMPLATE/feature_request.md

## Contributing

Contributions are welcome.

If you are evaluating this project, start with SETUP_GUIDE.md and run make test locally before proposing changes.
