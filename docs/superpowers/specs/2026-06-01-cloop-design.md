# C Loop — Design Spec

**Date:** 2026-06-01
**Status:** Approved design, pre-implementation
**Author:** Abraham Nguyen (with Claude)

---

## 1. Summary

**C Loop (`cloop`)** is a Claude Code **plugin** that wraps Claude Code's built-in
`/loop` to run **structured, self-documenting continuous loops**. You set it up once
through a short interview, it iterates while you're away (e.g. overnight), and every
iteration leaves behind an **ADR** (Architecture Decision Record) and a **verbose
commit** explaining *why* the change was made. You wake up to a clean, reviewable git
trail instead of an opaque pile of changes.

C Loop is **not** an agent-orchestration framework and has nothing to do with the
"Ralph" technique. It is a thin, robust, *neat* wrapper around the native `/loop`
(cron) mechanism.

### Design goals

1. **Robust** — survives session restarts; diagnoses and self-heals the common
   "loop didn't fire" failures.
2. **Agnostic** — the engine is fixed; *what* the loop works on is fully pluggable via
   a per-loop plan file. Another dev points it at their own kind of work without
   touching the engine.
3. **Cross-platform** — identical on Windows and macOS (primary: macOS). No shell hooks,
   no OS cron daemon; driven purely by Claude tools.
4. **Reviewable** — small iterations, one commit each, one ADR each.

---

## 2. Background: how Claude Code's `/loop` actually works

These facts are ground-truthed against the `CronCreate`/`ScheduleWakeup` tool schemas in
this harness and against real `.claude/scheduled_tasks.json` files on disk. They are the
constraints the design is built around.

- **Two engines, chosen by whether an interval is given:**
  - Interval → `CronCreate` (standard 5-field cron, **local timezone**).
  - No interval → `ScheduleWakeup` (model self-paces, delay clamped 60–3600s).
- **`durable` flag is decisive:**
  - `durable: false` (default) → **in-memory only; dies when the session exits.**
    This is the primary cause of "my loop stopped firing."
  - `durable: true` → **persisted to project-local `.claude/scheduled_tasks.json`**,
    restored on `--resume`/`--continue` if unexpired. **Overnight loops require this.**
- **`.claude/scheduled_tasks.json`** schema root is `{ "tasks": [ ... ] }`. Created even
  when empty. A wrapper can read it to confirm a job exists.
- **Idle-only firing** — a tick fires *between* turns, never mid-response. If an
  iteration runs long, the next tick waits. **No catch-up** for missed fires.
- **7-day auto-expiry** on recurring jobs — fires one final time, then self-deletes.
- **Jitter** — recurring jobs fire late by up to ~10% of period (cap ~15 min). Loops
  must **never assume exact wall-clock timing**.
- **Prompt-cache 5-min TTL** — waking past 300s pays a full cache miss. Cheap intervals
  are either `<270s` (cache stays warm) or `>=1200s` (amortized); **`5m` is the
  worst case.** Avoid `:00`/`:30` minutes to dodge fleet-wide jitter pileups.
- **`CLAUDE_CODE_DISABLE_CRON=1`** disables all cron tools and `/loop` entirely.
- **Pure Claude-tool implementation** — no shell, no system cron → identical on
  Windows and macOS.

**Design consequence:** iterations are keyed off an **iteration counter**, never a
clock. Jitter and missed fires become irrelevant — each fire simply runs "the next
iteration," whenever it lands.

---

## 3. Architecture

### 3.1 Two layers (the agnostic split)

| Layer | Changes? | Contents |
|---|---|---|
| **Engine** | Fixed | Read plan → run iteration lifecycle → write ADR → commit → update state → check stop condition. Lives in `skills/cloop/SKILL.md` + the `/cloop-iterate` command. |
| **Loop plan** | Per-loop, pluggable | Goals, done-criteria, active roles, commit style, interval/mode, and *optionally* a custom Workflow script as the iteration body. A Markdown file. |

A dev makes C Loop do something new by **writing a plan**, never by editing the engine.

### 3.2 On-disk layout (project-local)

```
.claude/cloop/
  plans/<slug>.md              # the pluggable plan (committed)
  state/<slug>.state.json      # runtime: iteration #, status, cron job id, last ADR (gitignored)
  adr/<slug>/NNNN-title.md      # one ADR per iteration (committed)
.claude/scheduled_tasks.json   # native durable cron store (managed by Claude, not us)
```

- **Plans and ADRs are committed** (they're the reviewable trail).
- **State is gitignored** (machine-local runtime). cloop adds the ignore entry on first
  use.

### 3.3 Plan file format (Markdown + YAML frontmatter)

```markdown
---
slug: improve-test-coverage
mode: continuous            # strict | continuous
interval: 20m               # cron interval; omit for self-paced (ScheduleWakeup)
engine: cron                # cron | dynamic   (derived from interval presence)
roles: [planner, worker, qa, scribe]   # innovator optional
commit_style: conventional-context     # conventional-context | brief-context | custom
max_iterations: 200         # hard ceiling (always set, even in continuous mode)
no_progress_limit: 5        # consecutive no-commit iterations → auto-pause
criteria_ref: null          # optional path to PRD.json / user-stories.md
workflow_script: null        # optional: custom Workflow as iteration body
---

# Objective
<prose: what this loop is trying to achieve and what "good" looks like>

# Done criteria
<bullet list, or reference criteria_ref>

# Iteration checklist / guardrails
<repo-specific constraints, what NOT to touch, definition of one iteration's scope>
```

The frontmatter is the only thing the engine parses; the prose is context for the agent.

### 3.4 State file format (`<slug>.state.json`)

```json
{
  "slug": "improve-test-coverage",
  "status": "running",            // running | paused | stopped | completed
  "iteration": 7,
  "cron_job_id": "<id returned by CronCreate>",
  "durable": true,
  "created_at": "<ISO>",
  "expires_at": "<ISO, created_at + 7d>",
  "last_adr": "0007-add-parser-tests.md",
  "consecutive_no_progress": 0,
  "last_commit": "<sha>"
}
```

Timestamps are stamped by the engine when it writes the file (not inside Workflow
scripts, which cannot call `Date.now()`).

---

## 4. Iteration lifecycle

Each cron tick fires **`/cloop-iterate <slug>`**, which runs **exactly one iteration**
as a single agent adopting inline roles (optional fan-out for heavy phases):

1. **Orient** *(Planner)* — read plan + state + last ADR + `git log`; scope this
   iteration to **one coherent change**.
2. **Work** *(Worker)* — implement it.
3. **Check** *(QA)* — verify against done-criteria; if `criteria_ref` set, check against it.
4. **Document** *(Scribe)* — write `adr/<slug>/NNNN-title.md`; compose the commit message.
5. **Commit** — verbose, embedding the ADR reasoning (see §6). **Always commit before
   the iteration ends** (crash-atomicity).
6. **Update state** — increment `iteration`, set `last_adr`/`last_commit`, update
   `consecutive_no_progress`.
7. **Stop check** — see §5.

**Optional Innovator phase / fan-out:** when the plan enables `innovator`, or a phase is
heavy (broad QA sweep, direction research), the iteration spawns a `Workflow` (e.g. a
small council of agents to critique direction) and feeds the result back into the plan.
If `workflow_script` is set, that script *is* the iteration body.

**Why count, not clock:** because fires jitter and can be missed, the engine never reads
timestamps to decide work. It reads `iteration` and does "the next one."

---

## 5. Modes, stop conditions, and safety rails

### Modes
- **Strict** — bounded work. Stops (`CronDelete` + `status: completed`) when done-criteria
  are met **or** `max_iterations` reached.
- **Continuous** — improves until you run `/cloop-stop`. Still bounded by `max_iterations`
  and the no-progress guard.

### Safety rails (always on)
- **Hard ceiling** — `max_iterations` is always set; reaching it stops the loop and notifies.
- **No-progress detector** — `no_progress_limit` consecutive iterations with no committable
  change → `status: paused` + `PushNotification`. Prevents burning the night spinning.
- **Crash-atomicity** — commit-before-end means a mid-iteration death loses at most one
  iteration's uncommitted work; the next fire resumes from git + state + last ADR.
- **7-day expiry → auto re-arm + notify** (chosen default): on the final pre-expiry
  iteration the engine creates a fresh durable job, updates `cron_job_id`/`expires_at`,
  and `PushNotification`s that it re-armed. Loop survives indefinitely until stopped.

---

## 6. ADR and commit specs

### ADR (`adr/<slug>/NNNN-title.md`)

```markdown
---
id: 0007
iteration: 7
date: <ISO>
status: accepted          # proposed | accepted | superseded
plan_slug: improve-test-coverage
---

## Context
<why this iteration did what it did; what state the repo was in>

## Decision
<what was changed and the approach taken>

## Alternatives considered
<options weighed and why rejected>

## Consequences
<effects, follow-ups, risks introduced>

## Links
- commit: <sha>
- files: <touched paths>
```

### Commit message styles (configurable via `commit_style`)

- **`conventional-context`** (default):
  ```
  type(scope): concise summary

  Why: <1–3 sentence rationale lifted from ADR Decision/Context>
  ADR: adr/<slug>/0007-add-parser-tests.md
  Loop: <slug> · iteration 7
  ```
- **`brief-context`** — non-conventional one-line subject + the same `Why:`/`ADR:`/`Loop:`
  trailer.
- **`custom`** — template string supplied in the plan/config.

Commits are **verbose yet concise**: the *what* in the subject, the *why* + ADR pointer
in the body, so `git log` alone tells the story.

---

## 7. Commands

| Command | Behavior |
|---|---|
| `/cloop` | Full interview → writes a plan → offers to start execution. |
| `/cloop-plan` | Planning interview only → writes `plans/<slug>.md`. No execution. |
| `/cloop-execute` | `AskUserQuestion` list of existing plans → arms a **durable** cron loop, records `cron_job_id`. No plans? → redirect to `/cloop-plan`. |
| `/cloop-iterate <slug>` | **Internal.** Runs exactly one iteration (the cron payload). Not meant to be typed by hand. |
| `/cloop-config` | Set **user-wide** defaults (commit style, default interval, roles, mode, no-progress limit) so the interview can skip those questions. Stored in `~/.claude/cloop/config.json`. |
| `/cloop-status` | Show active loops, current iteration, last ADR, "expires in X days", and a **morning report** digest (iterations run, commits, progress vs. criteria). |
| `/cloop-stop` | Stop a running loop (`CronDelete` + `status: stopped`). |
| `/cloop-fix` | Diagnose and re-arm a loop that isn't firing (see §8). |

### Interview (`/cloop`)

Detects fresh vs. existing context, then asks via `AskUserQuestion` (skipping anything
`/cloop-config` already answers):

1. Continue from existing context, or start fresh?
2. *(fresh)* Goals / type of work — suggests: code enhancement, tests, docs, refactor,
   feature planning, etc.
3. Precise criteria (PRD / user stories)? **Yes** → user pastes/drops it, saved and
   referenced via `criteria_ref`. **No** → gather specifics with 1–2 targeted questions.
4. Mode (strict/continuous), interval, active roles, commit style.

Then writes the plan and offers to execute.

---

## 8. `/cloop-fix` — diagnostics (the "didn't fire" cure)

Runs these checks **in order**, then re-arms as needed:

1. **`CLAUDE_CODE_DISABLE_CRON`** set in env? → report; cron is globally disabled.
2. **Job presence** — read `.claude/scheduled_tasks.json` and `CronList`; is the
   `cron_job_id` from state present?
3. **Missing but state says running** → non-durable death or fresh session →
   **re-arm durable** and update `cron_job_id`.
4. **Present but `iteration` not advancing** → session rarely idle (iterations too long
   or session busy) → advise shrinking iteration scope; offer to lower interval.
5. **Near 7-day expiry** → re-arm and reset `expires_at`.
6. **State file corrupt/missing** → rebuild from last ADR + `git log` + plan.
7. **Stop criteria accidentally met / `max_iterations` hit** → report it stopped legitimately.

Ends by printing what it found and what it changed.

---

## 9. Plugin packaging & deployment

### Layout
```
cloop/
  .claude-plugin/plugin.json
  .claude-plugin/marketplace.json     # enables `marketplace add ./cloop` for live dev
  commands/
    cloop.md  cloop-plan.md  cloop-execute.md  cloop-iterate.md
    cloop-config.md  cloop-status.md  cloop-stop.md  cloop-fix.md
  skills/cloop/SKILL.md                # the engine
  skills/cloop/references/
    adr-template.md
    commit-templates.md
    interview.md
    plan-template.md
  README.md
```

### Deploy (any machine, no account required)
- Push repo to GitHub → on each machine: `claude plugin marketplace add <repo-url>` →
  enable in `enabledPlugins`.
- **Live dev** (author == user): `claude plugin marketplace add ./cloop` (local path),
  iterate in-repo, push when stable.

### Cross-platform
No bash hooks, no OS cron. All scheduling via `CronCreate`/`ScheduleWakeup`/`CronList`/
`CronDelete` (Claude tools). Any helper scripts, if ever needed, must be Node or avoided;
the design avoids them entirely. Identical behavior on Windows and macOS.

---

## 10. Out of scope (YAGNI)

- No agent-orchestration framework, no "mission" concept, no Ralph/Stop-hook loop.
- No remote/server execution — relies on a local Claude Code session being resumable.
- No multi-repo central state (project-local only).
- No GUI/morning-email; the "morning report" is `/cloop-status` output in-session.

---

## 11. Open questions / to validate during implementation

1. Confirm a plugin's own slash command (`/cloop-iterate <slug>`) works reliably as a
   cron payload across `--resume`. (Docs imply yes; verify empirically on macOS + Windows.)
2. Confirm `durable: true` jobs in `.claude/scheduled_tasks.json` are restored and keep
   firing after `--resume` without manual re-arm.
3. Decide exact `~/.claude/cloop/config.json` schema during `/cloop-config` implementation.
