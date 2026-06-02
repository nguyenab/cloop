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
.claude/cloop/adr/<slug>/NNNN-*.md  one ADR per iteration (committed)
.claude/cloop/<slug>.state.json    small runtime state (gitignored)
.claude/scheduled_tasks.json       the timer, when the harness persists it (often session-only)
```

On first use, make sure `.gitignore` ignores `.claude/cloop/*.state.json` and the scheduler's
runtime files `.claude/scheduled_tasks.json` and `.claude/scheduled_tasks.lock`, so timer state never
lands in a commit. ADRs follow
`${CLAUDE_PLUGIN_ROOT}/skills/cloop-engine/references/adr-template.md`, commit messages follow
`${CLAUDE_PLUGIN_ROOT}/skills/cloop-engine/references/commit-templates.md`, and the roles are
described in `${CLAUDE_PLUGIN_ROOT}/skills/cloop-engine/references/roles.md`.

## Plan frontmatter

- `slug` short name
- `mode` strict or continuous
- `interval` how often it fires, in whole minutes (e.g. 20m)
- `max_iterations` stop after this many (required for strict; an optional cap for continuous)
- `roles` which roles are active, e.g. `[planner, worker, qa, scribe]` (add `innovator` for the council)
- `commit_style` conventional-context, brief-context, or custom
- `criteria_ref` optional path to a PRD or user-stories file the loop measures "done" against

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
  "cron_job_id": "<id>",
  "started_at": "<ISO>",
  "last_adr": null
}
```

`status` is running, stopped, or completed. Write it atomically (write a `.tmp`, rename over).

## Roles (you choose these in setup; see references/roles.md)

A normal loop uses Planner, Worker, QA, and Scribe. Innovator is opt-in and heavier.
- Planner scopes the next one or two iterations (or sketches the whole arc).
- Worker does the implementation.
- QA checks the result against the goal and `criteria_ref`.
- Scribe writes the ADR and the commit message in your chosen style.
- Innovator researches direction and runs a 5-agent council via the Workflow tool to vet an idea
  before it reaches the Planner. Use it occasionally, not every iteration.

## Modes

- Strict: run until the goal/criteria are met or `max_iterations` is hit, then stop.
- Continuous: keep going until you stop it; `max_iterations` is an optional safety cap.

## What one iteration does (run by /cloop-iterate, one per fire)

It runs unattended, so it never asks you anything. It works from the plan, the criteria, and the
last ADR. If it genuinely cannot tell what to do, it writes that into the summary and stops.

1. Read the plan, `criteria_ref` if set, the last ADR, and `git log`.
2. Plan: the Planner scopes one coherent step for this iteration and notes what likely comes next.
3. Work: the Worker implements it.
4. Check: QA verifies it against the goal and criteria, and records pass/fail in the ADR.
5. Write: the Scribe writes `.claude/cloop/adr/<slug>/NNNN-title.md` (NNNN = last ADR number in the
   slug's adr dir + 1, zero-padded to 4) and the commit message in `commit_style`, embedding the
   ADR's reasoning.
6. Commit: stage this iteration's changes plus the ADR and make one commit. Never push.
7. Increment `iteration`, set `last_adr`. If strict and the goal/criteria are met or
   `max_iterations` is reached, write the summary, cancel the timer (`CronDelete`), set status
   completed.

On a QA fail: fix it within the same iteration if you can. If you can't, revert this iteration's
code change so the next fire starts from a working tree, but still write the ADR with `qa: fail`
recording what broke and why, and commit that (plus any revert) so the trail stays intact. Never
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

## Starting a loop (used by /cloop and /cloop-execute)

Read the plan. Build a 5-field cron expression from `interval` (whole minutes; pick a minute that is
not :00 or :30). Translate the interval honestly: `*/N` only steps evenly when N divides 60 (5, 10,
12, 15, 20, 30), and step-from-offset forms like `7/18` are rejected by the scheduler. For an
interval that does not divide 60, use an evenly-spaced comma list of minutes instead (18m becomes
`7,25,43`, which accepts one wider gap per hour). Ask for a durable, recurring timer whose prompt is:
`Run one cloop iteration: /cloop:cloop-iterate <slug>`. Save the job id and start time in state.
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
loop already completed. Recreate the timer if it is missing and the loop is not done, and update
`cron_job_id`.

## Workflows

The Innovator council uses the Workflow tool to get several independent takes on a direction before
the loop commits to it. You can also point an iteration at your own Workflow if you want it to drive
the work; otherwise the roles above handle each iteration.
