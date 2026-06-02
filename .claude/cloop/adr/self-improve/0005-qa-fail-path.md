---
id: 0005
iteration: 5
date: 2026-06-02T08:45:49Z
plan_slug: self-improve
qa: pass
---

## Context

Reviewing "What one iteration does", QA records pass or fail (step 4) but step 6 commits
unconditionally, and nothing said what to do when QA fails. The ADR template already offers a
`qa: fail` value, so failures were expected, yet the loop had no defined response — risking a
broken working tree bleeding into the next fire, or a failing change committed as if fine.

## Decision

Added a QA-fail rule to SKILL.md: fix within the iteration if possible; otherwise revert this
iteration's code change so the next fire starts clean, but still write the ADR with `qa: fail`
explaining what broke, and commit that (plus any revert) so the audit trail stays intact. Never
hand a broken or half-finished tree to the next fire.

## Alternatives

- Commit failing changes as-is and "fix next time": rejected — violates the plan's rule that each
  iteration leaves the repo working, and risks compounding breakage across fires.
- Skip the commit entirely on fail: rejected — loses the ADR record of the failed attempt, which
  the next iteration needs in order to learn from it.

## Consequences

QA failures are now non-destructive and self-documenting: the repo stays runnable and the next
iteration inherits a clear note of what failed.

## Links
- files: skills/cloop-engine/SKILL.md
