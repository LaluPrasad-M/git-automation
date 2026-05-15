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
- Exception learning capture through a central registry issue

## What Makes It Different

- Policy-first architecture: behavior is driven by yaml policy, not hidden defaults
- Guardrails by design: self-filtering, rate limits, dry-run path, and skip logic
- Exact prompt routing: repo-specific prompts resolve by owner/repo path match
- No-settings-access local mode: run automation through Docker when repo settings are restricted

## Supported Actions

| Action | Purpose |
|---|---|
| review | Generate structured review findings |
| followup | Process replies on unresolved sentinel threads |
| approve | Approve only when policy and quality gates pass |
| merge | Merge only when policy and safety checks pass |

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
make logs
make ps
make restart
make down
make test
```

## Configuration Model

### Core env values for local mode

- GH_TOKEN
- ANTHROPIC_API_KEY
- MY_GITHUB_USERNAME
- TARGET_REPOS_JSON
- GITHUB_REPOSITORY
- EXCEPTION_REGISTRY_ISSUE_NUMBER (optional, recommended)

### Policy resolution

- Repo-specific: config/repos/<owner-repo>.yml
- Fallback: config/sentinel.yml

### Prompt resolution

- Preferred: config/prompts/repos/<owner>/<repo>/
- Fallback: config/prompts/defaults/

Prompt override lookup is exact-match only.

## Learning and Exceptions

When EXCEPTION_REGISTRY_ISSUE_NUMBER is configured, accepted non-fix follow-up rationales are written to the configured issue in GITHUB_REPOSITORY.

If not configured, follow-up falls back to PR comments without central registry persistence.

## Safety and Governance

- CI-aware approval and merge gating
- Unresolved thread checks before approval and merge
- Do-not-merge label support in merge flow
- Local runtime state stored under .state/ and kept out of git tracking

## Repository Structure

- .github/workflows/sentinel.yml: workflow orchestration
- config/: policy and prompt configuration
- scripts/: execution engine
- tests/: shell-based test suite and payload fixtures
- docs/: setup, troubleshooting, and decision references

## Documentation

- SETUP_GUIDE.md
- docs/TROUBLESHOOTING.md
- docs/decision-flows/review_and_approve.md
- docs/decision-flows/reply_followup.md
- docs/decision-flows/merge.md

## Contributing

Contributions are welcome.

If you are evaluating this project, start with SETUP_GUIDE.md and run make test locally before proposing changes.
