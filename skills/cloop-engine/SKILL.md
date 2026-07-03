---
name: cloop-engine
description: Shared instructions for how a cloop loop runs. The /cloop-* commands read this by path. Not a user command and not auto-invoked.
disable-model-invocation: true
---

# How a cloop loop works

cloop runs Claude Code's `/loop` with a real process around it. You set a loop up once: a goal, how
often it runs, how long, and which roles do the work. Then each interval it plans the next step,
does it, checks it, writes a short ADR explaining the decision, and commits with that reasoning in
the message. You come back to a set of small commits that each say why they happened, plus a summary
at the end.

This file is the shared instructions the `/cloop-*` commands read. Follow the part that applies.

## Files (in the project being worked on)

```
.claude/cloop/plans/<slug>.md      the plan: goal, cadence, mode, roles (committed)
.claude/cloop/criteria/<slug>.md   the criteria ledger: one checkbox per criterion (committed)
.claude/cloop/adr/<slug>/NNNN-*.md  one ADR per iteration (committed)
.claude/cloop/<slug>.state.json    small runtime state (gitignored)
.claude/scheduled_tasks.json       the timer, when the harness persists it (often session-only)
```

On first use, make sure `.gitignore` ignores `.claude/cloop/*.state.json` and the scheduler's
runtime files `.claude/scheduled_tasks.json` and `.claude/scheduled_tasks.lock`, so timer state never
lands in a commit. ADRs follow
`${CLAUDE_PLUGIN_ROOT}/skills/cloop-engine/references/adr-template.md`, commit messages follow
`${CLAUDE_PLUGIN_ROOT}/skills/cloop-engine/references/commit-templates.md`, the criteria ledger
follows `${CLAUDE_PLUGIN_ROOT}/skills/cloop-engine/references/criteria-template.md`, and the roles
are described in `${CLAUDE_PLUGIN_ROOT}/skills/cloop-engine/references/roles.md`.

## Plan frontmatter

- `slug` short name
- `mode` strict or continuous
- `interval` how often it fires, in whole minutes (e.g. 20m)
- `max_iterations` stop after this many (required for strict; an optional cap for continuous)
- `roles` which roles are active, e.g. `[planner, worker, qa, scribe]` (add `innovator` for the council)
- `commit_style` conventional-context, brief-context, or custom
- `criteria_ref` optional path to a PRD or user-stories file the loop measures "done" against
- `check` optional shell command that must exit 0 for an iteration to pass QA; null by default

Below the frontmatter is the goal in plain language.

## State (keep it small)

```json
{
  "slug": "<slug>",
  "status": "running",
  "iteration": 0,
  "mode": "continuous",
  "interval": "20m",
  "max_iterations": 50,
  "roles": ["planner", "worker", "qa", "scribe"],
  "commit_style": "conventional-context",
  "criteria_ref": null,
  "check": null,
  "cron": "<expr>",
  "cron_job_id": "<id>",
  "started_at": "<ISO>",
  "last_adr": null,
  "resume_at": null,
  "paused_reason": null,
  "last_quota": null,
  "slow_cron_job_id": null,
  "consecutive_qa_failures": 0,
  "last_progress_iteration": 0,
  "stalled_reason": null
}
```

`status` is running, stopped, completed, paused-quota, or stalled. `check` is carried from the plan
so /cloop-status and the guardrails can see it without re-parsing. The quota fields (`resume_at`,
`paused_reason`, `last_quota`, `slow_cron_job_id`) stay null until the quota gate pauses a loop (see
`${CLAUDE_PLUGIN_ROOT}/skills/cloop-engine/references/quota.md`); the three counters back the
guardrails (see `${CLAUDE_PLUGIN_ROOT}/skills/cloop-engine/references/guardrails.md`). Write the
file atomically (write a `.tmp`, rename over).

## Roles (you choose these in setup; see references/roles.md)

A normal loop uses Planner, Worker, QA, and Scribe. Innovator is opt-in and heavier.
- Planner scopes the next one or two iterations (or sketches the whole arc).
- Worker does the implementation.
- QA checks the result against the goal and `criteria_ref`.
- Scribe writes the ADR and the commit message in your chosen style.
- Innovator researches direction and runs a 5-agent council via the Workflow tool to vet an idea
  before it reaches the Planner. Use it occasionally, not every iteration.

## Modes

- Strict: run until the goal/criteria are met or `max_iterations` is hit, then stop. With a criteria
  ledger, done means every box — original and Discovered — is checked and the `check` command (if
  set) exits 0, not when the model feels done. Without a ledger (a plan predating it), fall back to
  goal-prose judgment as before.
- Continuous: keep going until you stop it; `max_iterations` is an optional safety cap.

## What one iteration does (run by /cloop-iterate, one per fire)

It runs unattended, so it never asks you anything. It works from the plan, the criteria, and the
recent ADRs. If it genuinely cannot tell what to do, it writes that into the summary and stops.

0. Quota gate: run the check in `${CLAUDE_PLUGIN_ROOT}/skills/cloop-engine/references/quota.md`
   (a cheap local call). If the binding window (the higher of 5h and weekly) is over the
   threshold, run that file's wrap-up landing instead of a normal iteration. Empty output means
   quota unknown: proceed normally.
0.5 Guardrails: run the breaker, stall, re-anchor, and immutability rules in
   `${CLAUDE_PLUGIN_ROOT}/skills/cloop-engine/references/guardrails.md`. If a breaker has tripped,
   run that file's stall landing instead of a normal iteration. Older loops without the counters
   never trip one.
1. Read the plan, `criteria_ref` and the criteria ledger if present, the last three ADRs, and
   `git log`. Treat each ADR's Handoff as external feedback from the prior QA, not your own prior
   reasoning. If no ledger exists yet, the Planner writes one first from the goal and `criteria_ref`
   in the shape of `${CLAUDE_PLUGIN_ROOT}/skills/cloop-engine/references/criteria-template.md`.
2. Plan: the Planner scopes one coherent step for this iteration and notes what likely comes next.
   The step ends with one explicit `Done when: <a check QA can perform this iteration>` line before
   the Worker starts — one step, one verifiable sub-goal — recorded in the ADR's Decision.
3. Work: the Worker implements it.
4. Check: QA runs two tiers, cheap before costly so a failing check rejects before judgment tokens
   are spent.
   - Tier 1, deterministic: run the plan's `check` command if set (it must exit 0) and confirm the
     iteration produced a non-empty diff scoped to the planned step. Any Tier-1 failure is
     `qa: fail` immediately.
   - Tier 2, judgment (only if Tier 1 passed): verify the step's `Done when` line, flip any criteria
     boxes this iteration satisfied, and check spirit over letter — the implementation must achieve
     the criterion's intent, and the loop never deletes, weakens, or edits tests or criteria to make
     a check pass.
   Record pass/fail in the ADR.
5. Write: the Scribe writes `.claude/cloop/adr/<slug>/NNNN-title.md` (NNNN = last ADR number in the
   slug's adr dir + 1, zero-padded to 4) and the commit message in `commit_style`, embedding the
   ADR's reasoning.
6. Commit: stage this iteration's changes plus the ADR and make one commit. Never push.
7. Increment `iteration`, set `last_adr`, and update the guardrail counters per
   `${CLAUDE_PLUGIN_ROOT}/skills/cloop-engine/references/guardrails.md`. If strict and the
   goal/criteria are met or `max_iterations` is reached, write the summary, cancel the timer
   (`CronDelete`), set status completed.

On a QA fail: fix it within the same iteration if you can. If you can't, revert this iteration's
code change so the next fire starts from a working tree, but still write the ADR with `qa: fail`
recording what broke and why, and commit that (plus any revert) so the trail stays intact. A failed
iteration still completes step 7: increment `iteration`, set `last_adr` to the fail ADR, and update
the counters per guardrails.md — otherwise the breakers can never trip. The next
fire retries fresh with a narrower scope — it never patches the rejected attempt in place. Never
hand a broken or half-finished working tree to the next fire.

If `innovator` is active, run its council once every several iterations (not every time) and feed
its conclusion to the Planner. Iterations are counted, not pinned to the clock.

Catching up on batched fires: when the session was busy and then goes idle, several timer fires can
arrive together in one turn. Treat each as its own iteration — run them in sequence, one coherent
step and one commit per fire, and stop the moment `max_iterations` is reached (drop any extra fires
past the cap). Do not fold them into a single commit; the small, individually-reasoned commits are
the whole point.

## ADR and commits

Each iteration leaves one ADR (Context, Decision, Alternatives, Consequences, Links) per
`references/adr-template.md`, committed with the change. The commit message uses `commit_style` per
`references/commit-templates.md` and embeds the why plus a pointer to the ADR, so `git log` alone
tells the story.

## Quota awareness

cloop reads remaining Claude capacity from the `ccs` proxy before spending an iteration, gates
each fire on the binding limit (5h or weekly, whichever is higher), and parks itself cleanly
with a handoff ADR when capacity runs out — pausing honestly based on whether the reset is
session-plausible. The check, the parse, the threshold, and the wrap-up landing are all in
`${CLAUDE_PLUGIN_ROOT}/skills/cloop-engine/references/quota.md`. If `ccs` is absent the gate is
a no-op and loops behave as before.

## Starting a loop (used by /cloop and /cloop-execute)

Read the plan. Run the quota gate first — starting a loop into an exhausted account just
schedules failures. Build a 5-field cron expression from `interval` (whole minutes; pick a minute that is
not :00 or :30). Translate the interval honestly: `*/N` only steps evenly when N divides 60 (5, 10,
12, 15, 20, 30), and step-from-offset forms like `7/18` are rejected by the scheduler. For an
interval that does not divide 60, use an evenly-spaced comma list of minutes instead (18m becomes
`7,25,43`, which accepts one wider gap per hour). Ask for a durable, recurring timer whose prompt is:
`Run one cloop iteration: /cloop:cloop-iterate <slug>`. Save the cron expression, job id, and start
time in state.
Tell the user the cadence, mode, roles, and job id.

Heads up on persistence: even when you request a durable timer, the harness may register it
session-only — it will not write `.claude/scheduled_tasks.json` and the timer dies when Claude exits.
Check the tool's response. If it came back session-only, tell the user plainly: the loop only runs
while this session stays open and idle between turns; closing it stops the loop, and they can restart
it with `/cloop:cloop-execute` or `/cloop:cloop-fix`.

## Summary (at the end, and for /cloop-status)

A short plain rundown: the goal, the mode, how many iterations ran, the main changes (from `git log`
and the ADRs), and anything left over. The "what happened while I was away" readout.

## If it stops firing (/cloop-fix)

Check in order: is `CLAUDE_CODE_DISABLE_CRON` set; is the session actually idle (the timer only
fires between turns); was the session closed and reopened (a session-only timer does not survive
that, and `.claude/scheduled_tasks.json` will be absent); is the job still in `CronList`; has the
loop already completed. Recreate the timer from the saved `cron` expression if it is missing and the
loop is not done — reusing it keeps the schedule identical instead of re-deriving and drifting — then
update `cron_job_id`.

## Workflows

The Innovator council uses the Workflow tool to get several independent takes on a direction before
the loop commits to it. You can also point an iteration at your own Workflow if you want it to drive
the work; otherwise the roles above handle each iteration.
