---
id: 0004
iteration: 4
date: 2026-06-02T08:45:49Z
plan_slug: self-improve
qa: pass
---

## Context

This very turn surfaced the gap: five "Run one cloop iteration" timer fires were delivered at
once after the session sat idle. `cloop-iterate.md` says "Do exactly one iteration, then stop,"
which is right for a single fire but silent on what to do when the harness hands over several at
once. Without guidance a loop might run one and silently drop the other four, under-counting
iterations, or fold them into one big commit and lose the small-commit audit trail.

## Decision

Added a "Catching up on batched fires" note to SKILL.md's "What one iteration does": run each
queued fire as its own iteration in sequence, one coherent step and one commit each, stop the
moment `max_iterations` is reached, and never collapse them into a single commit. This codifies
the behavior this run is already following.

## Alternatives

- Collapse batched fires into one larger iteration: rejected — defeats the small, individually
  reasoned commits that are cloop's core value.
- Drop all but the first fire: rejected — wastes scheduled work and makes progress lag the clock.

## Consequences

Batched fires now have defined, auditable behavior. The cap is still respected: fires past
`max_iterations` are dropped rather than run.

## Links
- files: skills/cloop-engine/SKILL.md
