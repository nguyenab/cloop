---
id: 0003
iteration: 3
date: 2026-06-10T08:40:00Z
plan_slug: fable-evolution
qa: pass
---

## Context

Iteration 2's council amended the quota plan: gate on the binding window (max of 5h and weekly),
pause honestly by reset horizon, and land with a tiny wrap-up iteration instead of a silent
skip. The parser (iteration 1) was shipped but nothing consumed it; cloop-iterate also lacked
CronCreate, so a paused loop could never re-arm its own timer.

## Decision

Wired the gate end to end as markdown instructions, no new machinery. quota.md gained "The
gate" (step 0: empty output = unknown = proceed; binding > 90 = wrap-up landing) and "Wrap-up
landing and pause" (coherent tree, handoff ADR, paused-quota state with resume_at from the
binding window, heartbeat only when the binding reset is within ~6h, PushNotification; a real
429 takes the same landing immediately). SKILL.md gained step 0, a Quota awareness section,
four new state fields (resume_at, paused_reason, last_quota, slow_cron_job_id) and the
paused-quota status. cloop-iterate.md now allows CronCreate and points at the gate. The 90
threshold lives in exactly one place (quota.md).

## Alternatives

- Implementing the original plan's 5h-only gate: rejected by the council with live evidence
  (5h 56% vs weekly 90% tonight — it would never fire).
- Always arming the heartbeat on pause: rejected — a session-only timer against a multi-day
  weekly reset is a false promise; the horizon branch keeps the promise honest.
- A shell helper encoding the gate logic: rejected — the branch logic reads fine as skill
  instructions; only the fragile text parse deserves a tested script (cloop stays lean).

## Consequences

Every loop now spends a cheap local check before each fire and parks itself cleanly at the
wall. QA's schema cross-check also surfaced a latent bug: state.schema.json had
additionalProperties:false but was never taught the `cron` key from commit d0038bc, so every
real state file violated the schema — fixed here. Next: quota-delta accounting and surfacing
pause state in cloop-status/cloop-fix (amendment 4), then README.

## Links

- files: skills/cloop-engine/references/quota.md, skills/cloop-engine/SKILL.md,
  commands/cloop-iterate.md, test/schemas/state.schema.json
