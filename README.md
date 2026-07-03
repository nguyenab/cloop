# cloop

Continuous, autonomous improvements to your project while you're on the go. You set a loop up once
and it keeps working toward a goal, one iteration at a time, writing down why it did each thing and
committing as it goes.

It runs on Claude Code's built-in `/loop` and adds the parts `/loop` is missing: context and
direction. Each interval it plans the next step, does it, checks it against your goal, writes a
short ADR, and makes a commit with that reasoning in the message. You choose which roles do the work
and whether it runs strict (stop when done) or continuous.

## Read this first

cloop only runs while a Claude Code session is open and sitting idle. Close the terminal and it
stops. If the harness persisted the timer, the loop can pick back up when you reopen that same
session with `claude --resume` (within 7 days) — but timers are often registered session-only and
do not survive a close, so don't count on it. If the loop is quiet after reopening, restart it with
`/cloop:cloop-execute` or `/cloop:cloop-fix`. So "leave it going overnight" means leaving a session
open and idle, not closing the laptop.

## Install

```
claude plugin marketplace add nguyenab/cloop
/plugin install cloop@cloop-marketplace
```

## Use it

Run `/cloop:cloop` and answer a few questions: what to work on, whether there's a spec to measure
against, how often, how long, which roles, and the commit style. It writes a plan and asks if you
want to start. Check in with `/cloop:cloop-status`, stop with `/cloop:cloop-stop`. If it ever goes
quiet, `/cloop:cloop-fix` works out why and restarts it.

| Command | What it does |
|---|---|
| `/cloop:cloop` | Set up a loop and start it |
| `/cloop:cloop-plan` | Write the plan only, do not start |
| `/cloop:cloop-execute` | Start a loop from an existing plan |
| `/cloop:cloop-status` | See what is running and what it has done |
| `/cloop:cloop-stop` | Stop a loop |
| `/cloop:cloop-fix` | Diagnose and restart a stalled loop |
| `/cloop:cloop-config` | Set your defaults |

## What one iteration does

Plan the next step, do it, check it against your goal (and your spec, if you gave one) — running your
check command and ticking off the criteria ledger as it goes — write a short ADR explaining the
decision, and make one commit on the current branch with the reasoning in the message. It never
pushes. It counts iterations, not minutes, so a late or skipped tick does not throw it off.

## Roles and modes

You pick the roles in setup. A normal loop uses Planner (scopes the next step), Worker (does it), QA
(checks it against your goal), and Scribe (writes the ADR and commit). Innovator is optional and
heavier: it researches direction and runs a small council to vet an idea before the Planner takes
it. Modes are strict (stop when the goal is met or after a set number of iterations) or continuous
(until you stop it).

## How it stays on track

If your project has tests, give the loop a check command at setup. Every iteration runs it first, and
a non-zero exit fails QA before any judgment is spent, so a change that breaks the build never counts
as done.

Setup also writes a criteria ledger next to the plan: a short checklist, one line per requirement,
each with a concrete way to verify it. The loop ticks a box only when that check holds, so
`N of M criteria met` in `/cloop:cloop-status` is a real count, and a strict loop is done when every
box is ticked rather than when the model feels finished.

Each iteration ends its ADR with a short handoff note — what happened, and if QA failed, the exact
check that failed and what the next iteration should avoid. The next fire reads the last few of these
as feedback, so a dead end is not retried the same way twice.

If a loop does get stuck — three QA fails in a row, or a long stretch with no progress — it stops
itself instead of grinding. It writes a diagnosis ADR, marks itself stalled, and cancels its timer;
`/cloop:cloop-fix` reads that diagnosis and can restart it with a narrower scope.

## Write a plan by hand

You do not need the interview. A plan is a small markdown file. Copy
`skills/cloop-engine/references/plan-template.md` to `.claude/cloop/plans/<name>.md`, fill in the
goal, mode, interval, roles, and commit style, then run `/cloop:cloop-execute <name>`. Or run
`/cloop:cloop-plan` and let it write the file for you.

## Where it keeps things

```
.claude/cloop/plans/<name>.md      your plan
.claude/cloop/criteria/<name>.md   the criteria ledger
.claude/cloop/adr/<name>/          one ADR per iteration
.claude/cloop/<name>.state.json    progress, ignored by git
```

## License

MIT. See [LICENSE](LICENSE).
