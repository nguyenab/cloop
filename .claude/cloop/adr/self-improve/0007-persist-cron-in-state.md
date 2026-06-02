---
id: 0007
iteration: 7
date: 2026-06-02T09:08:52Z
plan_slug: self-improve
qa: pass
---

## Context

State stored `interval` ("18m") and `cron_job_id`, but not the actual cron expression the timer
runs. `/cloop-fix` recreates a missing timer by re-deriving cron from the interval — and since an
18m interval has no canonical 5-field form (ADR 0003), the rebuilt schedule could land on
different minutes than the loop originally fired on. A diagnose-and-restart that silently changes
the cadence is a subtle correctness bug.

## Decision

Added a `cron` field to the state schema in SKILL.md, told "Starting a loop" to save the cron
expression alongside the job id and start time, and told "If it stops firing" to recreate the
timer from that saved expression so the schedule stays identical. Backfilled this loop's own
state.json with `"cron": "7,25,43 * * * *"` so the running loop matches the new schema.

## Alternatives

- Keep re-deriving from `interval`: rejected — non-divisor intervals have no stable derivation, so
  restart would drift the cadence.
- Store only the minute list, not the full expression: rejected — the full 5-field string is what
  CronCreate needs; storing it whole avoids any reassembly step.

## Consequences

`/cloop-fix` now restores the exact original schedule. Pairs with ADR 0003 (how the expression is
built) and ADR 0001 (why timers go missing in the first place).

## Links
- files: skills/cloop-engine/SKILL.md, .claude/cloop/self-improve.state.json
