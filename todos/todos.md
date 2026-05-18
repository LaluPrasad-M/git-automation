# Todos

---

## Features

### From todos.txt
1. Web dashboard — API call metrics (calls per hour, total, average per poll) to tune polling values → see `webpage.md`
2. GitHub Actions as alternate to Docker
3. Test with Copilot/OpenAI as alternate to Anthropic
4. PR checks for malicious code pushes

### New
5. **PR description auto-generation** — when a PR is opened with no description, generate one from the diff using the same LLM pipeline
6. **File pattern ignore list in policy.yml** — skip `*.lock`, `*.generated.*`, `**/snapshots/**` etc. so they don't inflate diff counts or clutter reviews
7. **Linked issue context** — if the PR body references a GitHub issue (`#123`, `closes #456`), fetch the issue title/description and include it in the review prompt so Claude understands the intent behind the change
8. **Slack / webhook notification** — post a message when a review is posted, approval happens, or merge completes
9. **Token/cost tracking** — log input + output tokens per LLM call; pairs with the web UI to show cost per repo and per PR
10. **Re-review gate on push** — if a PR already has a `NEEDS_CHANGES` review and a new push comes in, check whether changed files overlap with open findings before triggering a full re-review; skip if it's just a fixup on unrelated files
11. **Draft PR support toggle** — `review.drafts: true` in policy.yml to opt into reviewing draft PRs (currently hardcoded to skip all drafts)
12. **Branch protection wiring** — after sentinel approves, optionally update GitHub branch protection so the approval counts toward required reviews

---

## Bugs / Issues / Improvements

### From todos.txt
1. "Checking for prior approvals" runs for own PRs too — is it needed?
2. Redundant `gh` calls — some fields fetched separately could be batched (e.g. `reviewRequests` fetched 3 times for non-own PRs across classify, dispatch, review)

### New
3. OpenAI provider is a stub — tools and `max_turns` are not implemented; using it will produce raw text that fails JSON parsing

---

## Other Projects / Integrations
1. SonarQube — decided not needed for this project; shellcheck already covers static analysis for this shell-only codebase
