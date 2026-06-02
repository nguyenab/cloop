---
id: 0002
iteration: 2
date: 2026-06-02T08:45:49Z
plan_slug: self-improve
qa: pass
---

## Context

While surveying the repo for this batch of iterations, `git status` showed
`.claude/scheduled_tasks.lock` as untracked. The scheduler writes both that lock and
`.claude/scheduled_tasks.json` at runtime, but `.gitignore` only covered
`.claude/cloop/*.state.json`. So a careless `git add -A` during a loop would commit the
scheduler's transient runtime files. SKILL.md's "On first use" note also only mentioned the
state file.

## Decision

Added `.claude/scheduled_tasks.json` and `.claude/scheduled_tasks.lock` to `.gitignore`, and
widened the SKILL.md "On first use" instruction to call out those scheduler runtime files
alongside the state file. Verified with `git check-ignore` that both are now ignored and the
lock no longer shows as untracked.

## Alternatives

- Ignore all of `.claude/` : rejected — plans and ADRs under `.claude/cloop/` are meant to be
  committed; a blanket ignore would lose the audit trail.

## Consequences

Loop commits stay clean even with broad `git add`. Pairs with iteration 1: that one made the
docs honest about session-only timers; this one keeps those timers' runtime files out of git.

## Links
- files: .gitignore, skills/cloop-engine/SKILL.md
