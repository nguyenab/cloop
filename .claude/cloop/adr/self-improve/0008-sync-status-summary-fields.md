---
id: 0008
iteration: 8
date: 2026-06-02T09:26:48Z
plan_slug: self-improve
qa: pass
---

## Context

Final iteration. `cloop-status.md` re-lists the Summary fields inline ("goal, iterations run, the
main changes from `git log`, and anything left over") but had drifted from SKILL.md's Summary
definition, which also includes the mode and, crucially, the ADRs. Surfacing only `git log` and not
the ADRs undersells cloop's main value — the recorded reasoning behind each change.

## Decision

Synced the inline field list in `cloop-status.md` to SKILL.md: added `mode` and changed "from
`git log`" to "from `git log` and the ADRs", so a status readout reflects the why, not just the
what, and the two files no longer disagree.

## Alternatives

- Remove the inline list entirely and only point to SKILL: rejected — the short parenthetical is a
  useful hint at a glance; syncing it is enough to kill the drift without making status open another
  file to know what it produces.

## Consequences

`/cloop-status` now reports mode and pulls reasoning from the ADRs, matching SKILL. This is the last
planned iteration; the loop hits its strict cap of 8 here and finalizes.

## Links
- files: commands/cloop-status.md
