# cloop

Continuous, autonomous improvements and enhancements to your project while you're on the go. You
give cloop a goal once and it keeps working on it, one small step at a time, leaving a clear trail
of what it changed and why.

It runs on Claude Code's built-in `/loop` and adds the parts `/loop` is missing: context and
direction. cloop interviews you for the goal, writes a plan, then each interval does one piece of
work, records the decision behind it, and commits. It stays agnostic about the work itself, so you
can point it at tests, docs, refactors, cleanup, or anything else.

## Read this first

cloop only runs while a Claude Code session is open and sitting idle. Close the terminal and it
stops. Marking a loop durable means it picks back up when you reopen that same session with
`claude --resume`, as long as it has been less than 7 days. So "leave it going overnight" means
leaving a session open and idle, not closing the laptop.

## Install

```
claude plugin marketplace add nguyenab/cloop
/plugin install cloop@cloop-marketplace
```

## Use it

Run `/cloop:cloop` and answer a few questions: what to work on, how often, when to stop. It writes
a plan and asks if you want to start. Check in later with `/cloop:cloop-status`, stop with
`/cloop:cloop-stop`. If it ever goes quiet, `/cloop:cloop-fix` works out why and restarts it.

| Command | What it does |
|---|---|
| `/cloop:cloop` | Set up a loop and start it |
| `/cloop:cloop-plan` | Write the plan only, do not start |
| `/cloop:cloop-execute` | Start a loop from an existing plan |
| `/cloop:cloop-status` | See what is running and what it has done |
| `/cloop:cloop-stop` | Stop a loop |
| `/cloop:cloop-fix` | Diagnose and restart a stalled loop |
| `/cloop:cloop-config` | Set your defaults |

## What one interval does

Pick the next chunk of work, do it, check it against your goal, write a short decision record under
`.claude/cloop/adr/`, and make one commit on a `cloop/<name>` branch. It never pushes or rewrites
history. It counts iterations, not minutes, so a late or skipped tick does not throw it off.

## Write a plan by hand

You do not need the interview. A plan is a small markdown file. Copy
`skills/cloop-engine/references/plan-template.md` to `.claude/cloop/plans/<name>.md`, fill in the
goal and interval, and run `/cloop:cloop-execute <name>`. Or run `/cloop:cloop-plan` and let it
write the file for you.

## Where it keeps things

```
.claude/cloop/plans/<name>.md          your plan
.claude/cloop/adr/<name>/              one decision record per iteration
.claude/cloop/state/<name>.state.json  progress, ignored by git
```

## License

MIT. See [LICENSE](LICENSE).
