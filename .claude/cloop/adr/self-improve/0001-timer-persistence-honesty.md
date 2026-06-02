---
id: 0001
iteration: 1
date: 2026-06-02T07:09:55Z
plan_slug: self-improve
qa: pass
---

## Context

This is the first dogfooding iteration. The meta-observation came straight from setting
the loop up: SKILL.md's Files section called `.claude/scheduled_tasks.json` "the durable
timer, managed by Claude Code," and "Starting a loop" said to "create a durable, recurring
timer." But when the timer for this very loop was created with `durable: true`, the harness
reported it session-only and `.claude/scheduled_tasks.json` was never written (verified: the
file does not exist). So the engine docs over-promised persistence, while the README's "Read
this first" already told users the loop is session-only. The two were out of sync.

## Decision

Made SKILL.md honest about timer persistence, aligning it with the README:
- Files section: the timer file is written "when the harness persists it (often session-only)."
- Starting a loop: added a persistence heads-up — the harness may register the timer
  session-only despite the request; check the tool response and, if so, tell the user plainly
  that the loop only runs while the session stays open, and how to restart it.
- /cloop-fix checklist: added the "session was closed and reopened" case, which a session-only
  timer does not survive (and the scheduled_tasks.json file will be absent).

## Alternatives

- Change behavior to force durability: rejected — persistence is the harness's call, not the
  docs', and cloop stays a lean wrapper rather than fighting the platform.
- Leave docs as-is and rely on the README: rejected — the engine instructions are what the
  /cloop-* commands read, so the inaccuracy was load-bearing.

## Consequences

Setup will now warn users when a timer is session-only, matching real behavior. Next likely
step: the cron-building instruction in "Starting a loop" should note that step-from-offset
expressions like `7/18` are rejected by the scheduler (observed during setup) — use a comma
list or `*/N`. Left for a later iteration to keep this commit small.

## Links
- files: skills/cloop-engine/SKILL.md
