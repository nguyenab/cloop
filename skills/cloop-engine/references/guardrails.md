# Guardrails: circuit breaker, stall detection, re-anchor

An unattended loop fails quietly: it retries the same broken step, commits nothing, or drifts off
the goal while its state still reads "running." These guardrails catch those three without a
watchdog process — just counters in state and a few rules read at the top of each iteration. Read
this as step 0.5, after the quota gate and before planning. Everything here degrades to nothing when
the counters are absent, so an older loop simply never trips a breaker.

## Counters (in state.json)

State's `iteration` counts completed iterations, so the fire in progress is number `iteration + 1`.
The checks below read state as it stands at step 0.5, before step 7 increments it. Step 7 runs on
every iteration, passing or failing — a fail path that skips it leaves the breakers dead.

- `consecutive_qa_failures` — integer. Increment on every `qa: fail`; reset to 0 on any `qa: pass`.
- `last_progress_iteration` — integer. The last iteration that flipped a criteria box, or — when no
  ledger exists — landed a non-trivial commit. When progress lands, set it at step 7 to the
  just-incremented `iteration` value.
- `stalled_reason` — string or null. Null while healthy; set to the diagnosis when the loop lands
  stalled.

## Breaker rules (checked before planning)

- `consecutive_qa_failures >= 3` → stall landing.
- Continuous mode only: `iteration - last_progress_iteration >= 5` → stall landing.

Strict mode already stops at `max_iterations`, so the plateau rule is a continuous-mode guard.

## Stall landing (mirrors the quota wrap-up landing)

When a breaker trips, land the loop cleanly rather than burn more iterations on a broken trajectory:

1. Leave the tree coherent: commit safe in-flight work or revert it, as on a QA fail.
2. Write a diagnosis ADR: what kept failing, the grounded evidence from the last Handoffs (the
   failing checks and their output), one or two hypotheses, and a suggested narrower scope to try.
   Commit it, like every other ADR.
3. Set state: `status: stalled`, `stalled_reason` (e.g. `3 consecutive QA fails on the auth step`),
   `last_adr` to the diagnosis ADR. A landing is not a new iteration: leave `iteration` unchanged.
4. `CronDelete` the timer — a stalled loop burns no further iterations.
5. `PushNotification`: stalled, why, and what to do next (`/cloop:cloop-fix` reads the diagnosis and
   can restart with the narrower scope).

## Re-anchor (every 5th iteration)

When the fire in progress is a positive multiple of 5 — `(iteration + 1) % 5 == 0` at step 0.5, so
fires 5, 10, 15, never the first — the Planner re-reads the plan's Goal and the criteria ledger
verbatim before scoping, and records one line in the ADR Context: whether the recent trajectory
still serves the goal, and anything that drifted. A deterministic counter, not a similarity score.

## Immutability

The plan's Goal and Scope prose are human-owned, like the criterion text (see
`${CLAUDE_PLUGIN_ROOT}/skills/cloop-engine/references/criteria-template.md` for what the loop may
touch in the ledger): the loop never edits them. If an iteration believes a criterion is wrong, it
says so in the ADR and leaves the criterion intact.
