---
name: cloop-engine
description: How a cloop loop works. Shared instructions the /cloop-* commands read by path. Not a user command and not auto-invoked.
disable-model-invocation: true
---

# How a cloop loop works

cloop is a consistent, repeatable way to run Claude Code's `/loop`. You capture the goal and cadence
once (a plan, plus optional config defaults), and the loop runs on a timer, carries its own
direction forward in a notes file, and writes a summary when it is done. The point is that you do
not re-dump all your context every time you want a good `/loop`.

This file is shared instructions the `/cloop-*` commands read. Follow the part that applies.

## Files (in the project being worked on)

```
.claude/cloop/plans/<slug>.md     the goal and cadence, written once (committed)
.claude/cloop/<slug>.notes.md     the loop's running "where I am / what's next" memory (committed)
.claude/cloop/<slug>.state.json   small runtime state (gitignored)
.claude/scheduled_tasks.json      the durable timer, managed by Claude Code
```

On first use, make sure `.gitignore` ignores `.claude/cloop/*.state.json` (read it, append the line
if it is missing).

The notes file follows `${CLAUDE_PLUGIN_ROOT}/skills/cloop-engine/references/notes-template.md`, and
commit messages follow `${CLAUDE_PLUGIN_ROOT}/skills/cloop-engine/references/commit-templates.md`.

## Plan frontmatter the loop reads

- `slug` short name for the loop
- `interval` how often it fires, in whole minutes (e.g. 20m)
- `run_for` how long to keep going: a duration (4h), a count (12 iterations), or "until <condition>"
- `commit_style` conventional or plain (default conventional)

Everything below the frontmatter is the goal in plain language.

## State (keep it small)

```json
{
  "slug": "<slug>",
  "status": "running",
  "iteration": 0,
  "started_at": "<ISO>",
  "stop_after": "<the run_for value, resolved to a time or count>",
  "cron_job_id": "<id>"
}
```

`status` is running, stopped, or done. Write it atomically: write `<slug>.state.json.tmp`, then
rename it over the real file.

## What one iteration does (run by /cloop-iterate, one per fire)

It runs unattended, so it never asks you anything. It works only from the plan and the notes file.
If something is genuinely unclear, it writes that into the summary and stops, rather than guessing
forever.

1. Read the plan (the goal) and the notes file (where things stand, what is next).
2. Do the next step. On the first iteration, work it out from the goal.
3. Work out what comes next: scope it, plan it, and research it if that helps, then write it into
   the notes file so the next fire starts with direction. This is the part plain `/loop` does not do.
4. Commit the work. One commit, staging only what this iteration changed, using `commit_style`.
   Never push.
5. Increment `iteration`. If `run_for` is reached or the goal is met, write the summary, cancel the
   timer (`CronDelete`), and set `status` to done.

Iterations are counted, not pinned to the clock, so a late or skipped tick does not matter.

## Starting a loop (used by /cloop and /cloop-execute)

Read the plan. Build a 5-field cron expression from `interval` (whole minutes; pick a minute that
is not :00 or :30 to avoid scheduler pileups). Create a durable, recurring timer whose prompt is:
`Run one cloop iteration: /cloop:cloop-iterate <slug>`. Save the returned job id, the start time,
and the resolved `stop_after` in state. Tell the user the cadence, how long it will run, and the
job id.

## Summary (at the end, and for /cloop-status)

A short plain rundown: the goal, how many iterations ran, the main things that changed (read from
`git log`), and anything left over or unresolved. This is the "what happened while I was away"
readout.

## If it stops firing (/cloop-fix)

Check in order: is `CLAUDE_CODE_DISABLE_CRON` set; is the session actually idle (the timer only
fires between turns, never mid-response); is the durable job still there (look in
`.claude/scheduled_tasks.json` and `CronList`); has the `run_for` window already passed. If the job
is missing and the loop is not done, recreate it the same way Starting a loop does, and update
`cron_job_id`.
