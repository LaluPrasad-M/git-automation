description: Comprehensive language-neutral engineering review checklist — correctness, security, regressions, completeness, scope, edge cases, performance, concurrency, observability, dead code

# General Engineering Review Checklist

Review every changed file in full. Cite file and line for every finding.

## Correctness
- All branch conditions, loop bounds, and index access are correct
- Every value from an external source or optional field is guarded before use
- Errors are propagated or handled — not silently ignored

## Regressions and Breaking Changes
- Changes to shared code are verified against all call sites, not just those in the diff
- Any change to a function signature, API, event format, or config key has all consumers updated
- New or changed env vars and config keys are reflected in docs and example files
- Code that is moved or renamed during a refactor is verified for correctness — pre-existing bugs in moved code are not automatically acceptable

## Completeness
- Related types, constants, and sibling files are updated alongside logic changes
- New behaviour has tests; changed behaviour has updated tests
- No TODOs, stubs, or placeholder values left in the diff

## Scope
- All changes serve the stated PR purpose — unrelated modifications are flagged
- Refactors and formatting changes are not mixed with logic changes

## Code Quality
- Naming, structure, and patterns are consistent with the surrounding codebase
- No new abstractions, dependencies, or complexity introduced beyond what the task requires

## Security
- External input is sanitised or parameterised before use in commands, queries, paths, or output
- No hardcoded secrets, tokens, or credentials anywhere in the diff
- No PII or internal details in logs, error responses, or external output

## Edge Cases
- Empty, null, and missing values are explicitly handled
- External calls have timeouts; partial failure is handled — no all-or-nothing assumptions

## Performance
- No network, file, or database calls inside loops
- All loops, queues, and collections have an explicit upper bound

## Concurrency
- No shared state is read or written concurrently without coordination
- Multi-step operations on shared state are atomic or explicitly coordinated

## Observability
- Significant operations (start, complete, skip, fail) produce a log entry
- Error messages include enough context to diagnose the failure

## Dead Code
- No unreachable branches, unused variables, or unused imports
- No commented-out code — delete it, version history preserves it
