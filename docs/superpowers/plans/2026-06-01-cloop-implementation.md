# C Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `cloop` Claude Code plugin — a robust, cross-platform wrapper around the built-in `/loop` that runs structured, self-documenting continuous loops (interview → plan → durable cron iterations → per-iteration ADR + verbose commit → diagnostics).

**Architecture:** A single plugin at the repo root. Eight thin `commands/*.md` slash entry points delegate to ONE engine skill (`skills/cloop/SKILL.md`) that defines the iteration lifecycle, state/ADR/commit specs, and safety rails. The loop is driven entirely by the `CronCreate`/`ScheduleWakeup`/`CronList`/`CronDelete` Claude tools (no shell, no OS cron) so behavior is identical on Windows and macOS. Per-loop state and ADRs live under the target project's `.claude/cloop/`.

**Tech Stack:** Claude Code plugin (Markdown + YAML frontmatter + JSON manifests). No runtime language; `python3 -m json.tool` is used only for validating JSON during the build.

**Spec:** `docs/superpowers/specs/2026-06-01-cloop-design.md` — read it before starting.

**Key facts the implementation depends on (from spec §2):**
- Overnight loops MUST use `durable: true` (persisted to project-local `.claude/scheduled_tasks.json`); the default is in-memory and dies on session exit.
- Cron jobs fire only while the session is idle, with jitter, and never catch up missed fires → iterations are keyed off a **counter**, never the clock.
- Recurring jobs auto-expire after 7 days → cloop auto-re-arms + notifies.
- `${CLAUDE_PLUGIN_ROOT}` is the portable path to the plugin root inside command/skill files.

---

## File Structure

Created by this plan (all paths relative to repo root `/Users/abrahamnguyen/Development/cloop`):

```
.claude-plugin/plugin.json            # plugin manifest
.claude-plugin/marketplace.json       # self-marketplace for local + remote install
commands/
  cloop.md            # full interview → plan → offer execute
  cloop-plan.md       # planning interview only → writes plan
  cloop-execute.md    # arm a durable cron loop from a plan
  cloop-iterate.md    # INTERNAL: run exactly one iteration (cron payload)
  cloop-status.md     # active loops + morning report
  cloop-stop.md       # stop a loop (CronDelete)
  cloop-config.md     # user-wide defaults (~/.claude/cloop/config.json)
  cloop-fix.md        # diagnose & re-arm a stalled loop
skills/cloop/SKILL.md                 # the engine (all shared logic)
skills/cloop/references/
  plan-template.md
  adr-template.md
  commit-templates.md
  interview.md
README.md
.gitignore                            # already contains .claude/cloop/state/
```

**Responsibility boundaries:**
- `commands/*.md` — thin: parse `$ARGUMENTS`, then defer to the engine skill. No duplicated logic.
- `skills/cloop/SKILL.md` — the single source of truth for the iteration lifecycle, state schema, stop conditions, safety rails, and `/cloop-fix` checklist.
- `skills/cloop/references/*` — static templates the engine fills in.

---

## Task 1: Plugin scaffold + installable manifest

**Files:**
- Create: `.claude-plugin/plugin.json`
- Create: `.claude-plugin/marketplace.json`

- [ ] **Step 1: Write the plugin manifest**

Create `.claude-plugin/plugin.json`:

```json
{
  "name": "cloop",
  "version": "0.1.0",
  "description": "C Loop: structured, self-documenting continuous loops on top of Claude Code's /loop. Interview-driven setup, pluggable per-loop plans, per-iteration ADRs and verbose commits, durable cron with self-healing diagnostics.",
  "author": {
    "name": "Abraham Nguyen"
  }
}
```

- [ ] **Step 2: Write the self-marketplace manifest**

Create `.claude-plugin/marketplace.json`. `source: "./"` resolves relative to the directory containing `.claude-plugin/` (the repo root), so it points at this plugin:

```json
{
  "$schema": "https://anthropic.com/claude-code/marketplace.schema.json",
  "name": "cloop-marketplace",
  "description": "Marketplace hosting the C Loop plugin.",
  "owner": {
    "name": "Abraham Nguyen"
  },
  "plugins": [
    {
      "name": "cloop",
      "description": "Structured, self-documenting continuous loops on top of Claude Code's /loop.",
      "category": "productivity",
      "source": "./"
    }
  ]
}
```

- [ ] **Step 3: Validate both JSON files**

Run:
```bash
python3 -m json.tool .claude-plugin/plugin.json >/dev/null && echo "plugin.json OK"
python3 -m json.tool .claude-plugin/marketplace.json >/dev/null && echo "marketplace.json OK"
```
Expected: both print `OK`.

- [ ] **Step 4: Commit**

```bash
git add .claude-plugin/
git commit -m "feat(cloop): add plugin + self-marketplace manifests"
```

---

## Task 2: Reference templates

These are static assets the engine fills in. No logic; they define the canonical shapes from spec §3.3, §3.4, §6.

**Files:**
- Create: `skills/cloop/references/plan-template.md`
- Create: `skills/cloop/references/adr-template.md`
- Create: `skills/cloop/references/commit-templates.md`

- [ ] **Step 1: Write the plan template**

Create `skills/cloop/references/plan-template.md`:

````markdown
# C Loop Plan Template

A loop plan is the pluggable "what". The engine parses ONLY the frontmatter; the prose
sections are context for the working agent. Copy this shape when generating a plan.

```markdown
---
slug: <kebab-case-id>
mode: continuous            # strict | continuous
interval: 20m               # cron interval (e.g. 90s, 20m, 2h); omit for self-paced
engine: cron                # cron | dynamic  (dynamic when interval is omitted)
roles: [planner, worker, qa, scribe]   # add "innovator" to enable the research/critique fan-out
commit_style: conventional-context     # conventional-context | brief-context | custom
custom_commit_template: null            # required only when commit_style: custom
max_iterations: 200          # hard ceiling; ALWAYS set, even in continuous mode
no_progress_limit: 5         # consecutive no-commit iterations → auto-pause + notify
criteria_ref: null           # optional path to PRD.json / user-stories.md (relative to repo root)
workflow_script: null        # optional path to a Workflow script used AS the iteration body
---

# Objective
<What this loop is trying to achieve and what "good" looks like.>

# Done criteria
<Bullet list of completion conditions, OR "See criteria_ref.">

# Iteration scope / guardrails
<What ONE iteration should accomplish. What NOT to touch. Repo-specific constraints.>
```

## Interval guidance (cost-aware; from spec §2)
- `< 270s`: prompt cache stays warm but burns tokens fastest. Use only for short bursts.
- `5m`: WORST case — pays a full cache miss without amortizing it. Avoid.
- `>= 20m`: economical for overnight runs. Recommended default.
- Avoid `:00`/`:30` minute marks to dodge fleet-wide jitter pileups (cloop handles this
  automatically when it builds the cron expression).
````

- [ ] **Step 2: Write the ADR template**

Create `skills/cloop/references/adr-template.md`:

````markdown
# C Loop ADR Template

One ADR per iteration, written to `.claude/cloop/adr/<slug>/NNNN-title.md` (NNNN = zero-padded
iteration number). Committed alongside the change.

```markdown
---
id: NNNN
iteration: N
date: <ISO-8601 timestamp>
status: accepted          # proposed | accepted | superseded
plan_slug: <slug>
---

## Context
<Why this iteration did what it did; the repo state going in.>

## Decision
<What was changed and the approach taken.>

## Alternatives considered
<Options weighed and why they were rejected. "None — mechanical change" is acceptable.>

## Consequences
<Effects, follow-ups created, risks introduced.>

## Links
- commit: <sha>            # filled in after committing; may be "(this commit)" pre-commit
- files: <touched paths>
```
````

- [ ] **Step 3: Write the commit templates**

Create `skills/cloop/references/commit-templates.md`:

````markdown
# C Loop Commit Templates

Selected by the plan's `commit_style`. Every style embeds the ADR pointer and loop/iteration
so `git log` alone tells the story (spec §6).

## conventional-context (default)
```
<type>(<scope>): <concise summary>

Why: <1–3 sentence rationale from the ADR Context/Decision>
ADR: .claude/cloop/adr/<slug>/NNNN-title.md
Loop: <slug> · iteration N
```
`<type>` is one of feat, fix, refactor, test, docs, chore, perf, style.

## brief-context
```
<concise non-conventional subject>

Why: <1–3 sentence rationale>
ADR: .claude/cloop/adr/<slug>/NNNN-title.md
Loop: <slug> · iteration N
```

## custom
Use the plan's `custom_commit_template` verbatim. It MAY reference these placeholders, which
the engine substitutes: `{summary}`, `{why}`, `{adr_path}`, `{slug}`, `{iteration}`, `{type}`,
`{scope}`. The template MUST still include `{adr_path}` and `{iteration}` so the trail stays intact.
````

- [ ] **Step 4: Verify the files exist and have the expected headers**

Run:
```bash
for f in plan-template adr-template commit-templates; do
  test -f "skills/cloop/references/$f.md" && head -1 "skills/cloop/references/$f.md"
done
```
Expected: three `# C Loop ...` header lines print.

- [ ] **Step 5: Commit**

```bash
git add skills/cloop/references/
git commit -m "feat(cloop): add plan, ADR, and commit reference templates"
```

---

## Task 3: The engine skill

This is the heart — the single source of truth all commands defer to. It defines the on-disk
layout, state schema, the iteration lifecycle, stop conditions, safety rails, the durable-arming
procedure, and the `/cloop-fix` checklist.

**Files:**
- Create: `skills/cloop/SKILL.md`

- [ ] **Step 1: Write the engine skill**

Create `skills/cloop/SKILL.md`:

````markdown
---
name: cloop
description: C Loop engine — runs structured, self-documenting continuous loops on top of Claude Code's /loop. Use when arming, iterating, inspecting, stopping, or repairing a cloop. Defines the iteration lifecycle, state/ADR/commit specs, durable cron arming, and diagnostics. Invoked by the /cloop-* commands.
---

# C Loop Engine

C Loop wraps Claude Code's built-in `/loop` (cron) to run **structured, self-documenting
continuous loops**. Each iteration produces one ADR and one verbose commit. The engine is
fixed; *what* a loop works on is defined by a pluggable plan file.

This skill is the shared logic for all `/cloop-*` commands. When a command defers here, follow
the relevant section exactly.

## On-disk layout (in the TARGET project, relative to its repo root)

```
.claude/cloop/plans/<slug>.md              # the plan (committed)
.claude/cloop/state/<slug>.state.json      # runtime state (gitignored)
.claude/cloop/adr/<slug>/NNNN-title.md      # one ADR per iteration (committed)
.claude/scheduled_tasks.json               # native durable cron store (managed by Claude Code)
```

On first use in a project, ensure `.claude/cloop/state/` is gitignored: if no `.gitignore`
entry matches it, append a line `.claude/cloop/state/` to the project's `.gitignore`.

## State schema (`.claude/cloop/state/<slug>.state.json`)

```json
{
  "slug": "<slug>",
  "status": "running",
  "iteration": 0,
  "cron_job_id": "<id returned by CronCreate, or null>",
  "durable": true,
  "engine": "cron",
  "interval": "20m",
  "created_at": "<ISO>",
  "expires_at": "<ISO = created_at + 7 days>",
  "last_adr": null,
  "last_commit": null,
  "consecutive_no_progress": 0
}
```

`status` ∈ `running | paused | stopped | completed`. Stamp all timestamps yourself when
writing the file (do not rely on Workflow scripts for time).

## Roles (inline behaviors, single agent)

A single agent plays these per iteration. Spawn subagents/Workflow ONLY for heavy phases.
- **Planner** — reads plan + state + last ADR + `git log`; scopes ONE coherent change.
- **Worker** — implements it.
- **QA** — verifies against done criteria (and `criteria_ref` if set).
- **Scribe** — writes the ADR and composes the commit.
- **Innovator** (opt-in via `roles`) — researches direction / runs a small critique council
  via the `Workflow` tool, feeds conclusions back into the plan. Run at most once every few
  iterations, never every iteration.

## Iteration lifecycle (run by /cloop-iterate, exactly ONE per invocation)

Iterations are keyed off the **counter in state**, never the clock (fires jitter and may be
missed). Procedure:

1. **Load** — read `.claude/cloop/plans/<slug>.md` and `.claude/cloop/state/<slug>.state.json`.
   If state is missing, STOP and tell the caller to run `/cloop-fix <slug>`.
2. **Guard** — if `status` ≠ `running`, STOP (report current status). If `iteration >=
   max_iterations`, finalize (see Stop conditions). If `consecutive_no_progress >=
   no_progress_limit`, set `status: paused`, `PushNotification`, and STOP.
3. **Expiry check** — if `expires_at` is within one interval of now, RE-ARM (see Arming) before
   doing work, update `cron_job_id`/`expires_at`, and `PushNotification` that the loop re-armed.
4. **Orient (Planner)** — decide this iteration's single coherent change from the plan + history.
5. **Work (Worker)** — implement it. If `workflow_script` is set in the plan, run that Workflow
   as the iteration body instead of free-form work.
6. **Check (QA)** — verify against done criteria; note pass/fail in the ADR.
7. **Document (Scribe)** — write `.claude/cloop/adr/<slug>/NNNN-title.md` from the ADR template
   (NNNN = next iteration, zero-padded to 4).
8. **Commit** — stage the change + ADR; commit using the plan's `commit_style` (see
   `references/commit-templates.md`). ALWAYS commit before the iteration ends (crash-atomicity).
   If there was genuinely nothing to change this iteration, do NOT create an empty commit;
   instead increment `consecutive_no_progress`.
9. **Update state** — set `iteration += 1`, `last_adr`, `last_commit` (sha). Reset
   `consecutive_no_progress` to 0 on a real commit, else increment it.
10. **Stop check** — see Stop conditions.

## Stop conditions

- **Strict mode**: when done criteria are met OR `iteration >= max_iterations` → finalize:
  `CronDelete` the `cron_job_id`, set `status: completed`, write a final summary line, and
  `PushNotification` the result.
- **Continuous mode**: keep running until `/cloop-stop`. Still bounded by `max_iterations`
  (→ `completed`) and the no-progress guard (→ `paused`).

## Arming a durable cron loop (used by /cloop-execute and re-arm paths)

1. Read the plan frontmatter. If `interval` is present → cron engine; else → dynamic engine.
2. **Cron engine**: build a 5-field cron expression from `interval`, choosing a non-`:00`/`:30`
   minute to avoid jitter pileups (e.g. for `20m` use `7,27,47 * * * *`; for hourly use `7 * * * *`).
   Call `CronCreate` with `durable: true`, `recurring: true`, and `prompt` set to:
   `Run one C Loop iteration: /cloop-iterate <slug>`
3. **Dynamic engine**: arrange the self-paced loop via the built-in `/loop` with the same payload
   (`/cloop-iterate <slug>`) and no fixed interval; record `cron_job_id` if one is returned, else
   note `engine: dynamic` in state.
4. Capture the returned job id into `cron_job_id`, set `durable: true`, `created_at` = now,
   `expires_at` = now + 7 days, and persist state.
5. Confirm to the user: slug, mode, interval/engine, cron expression, job id, and expiry date.

Always prefer `durable: true` — a non-durable job dies on session exit and is the #1 cause of
"the loop stopped firing."

## /cloop-fix checklist (run in order; report findings + actions)

1. **Cron globally disabled?** If env `CLAUDE_CODE_DISABLE_CRON=1`, report that cron + `/loop`
   are disabled; nothing will fire until it's unset.
2. **Job present?** Read `.claude/scheduled_tasks.json` (root `{ "tasks": [...] }`) and run
   `CronList`. Is the state's `cron_job_id` present?
3. **Missing but state says running** → in-memory death or fresh session. RE-ARM durable, update
   `cron_job_id`/`created_at`/`expires_at`.
4. **Present but `iteration` not advancing** → session rarely idle (iterations too long, or the
   session is busy). Advise shrinking iteration scope; offer to lower the interval.
5. **Near 7-day expiry** → re-arm and reset `expires_at`.
6. **State file corrupt/missing** → rebuild from the last ADR in `.claude/cloop/adr/<slug>/` +
   `git log` + the plan (`iteration` = highest ADR number).
7. **Stopped legitimately?** If criteria met or `max_iterations` reached, report it stopped on
   purpose; offer to raise the ceiling or switch to continuous.

## Morning report (used by /cloop-status)

Summarize each active loop on one screen: slug, status, current iteration, last ADR title,
commits since `created_at` (`git log --oneline --since`), progress vs. done criteria, and
"expires in X days". Keep it scannable — this is read with coffee.

## Cross-platform note

All scheduling uses `CronCreate`/`ScheduleWakeup`/`CronList`/`CronDelete` — Claude tools, not
shell or OS cron. Behavior is identical on Windows and macOS. Do not add shell hooks.
````

- [ ] **Step 2: Verify frontmatter parses and required sections exist**

Run:
```bash
sed -n '1,4p' skills/cloop/SKILL.md
grep -c "^## " skills/cloop/SKILL.md
```
Expected: frontmatter shows `name: cloop`; the `grep -c` count is `>= 8` (the `##` sections).

- [ ] **Step 3: Commit**

```bash
git add skills/cloop/SKILL.md
git commit -m "feat(cloop): add the engine skill (lifecycle, state, arming, fix checklist)"
```

---

## Task 4: `/cloop-iterate` — the internal single-iteration runner (cron payload)

This is what the cron job fires every interval. It runs exactly one iteration via the engine,
then returns. Hidden from the slash-command picker so users don't run it by hand.

**Files:**
- Create: `commands/cloop-iterate.md`

- [ ] **Step 1: Write the command**

Create `commands/cloop-iterate.md`:

```markdown
---
name: cloop-iterate
description: "INTERNAL — runs exactly one C Loop iteration for a slug. Fired automatically by the loop's cron job; not meant to be typed by hand."
argument-hint: "<slug>"
hide-from-slash-command-tool: "true"
allowed-tools: ["Read", "Write", "Edit", "Bash", "Workflow", "CronCreate", "CronDelete", "CronList", "PushNotification"]
---

# C Loop — Run One Iteration

Slug: **$ARGUMENTS**

Follow the **C Loop engine** skill at `@${CLAUDE_PLUGIN_ROOT}/skills/cloop/SKILL.md`,
section **"Iteration lifecycle"**, for the slug above. Run EXACTLY ONE iteration, then stop.

Do not loop internally and do not start additional iterations — the cron schedule fires the
next one. If state is missing or `status` is not `running`, follow the engine's Guard step and
stop with a clear report.
```

- [ ] **Step 2: Verify frontmatter**

Run:
```bash
grep -E "name:|hide-from-slash-command-tool:|argument-hint:" commands/cloop-iterate.md
```
Expected: shows `name: cloop-iterate`, the hide flag, and the `<slug>` hint.

- [ ] **Step 3: Commit**

```bash
git add commands/cloop-iterate.md
git commit -m "feat(cloop): add internal /cloop-iterate cron payload command"
```

---

## Task 5: `/cloop-plan` + interview reference

Produces a plan file via a planning-only interview. No execution.

**Files:**
- Create: `skills/cloop/references/interview.md`
- Create: `commands/cloop-plan.md`

- [ ] **Step 1: Write the interview reference**

Create `skills/cloop/references/interview.md`:

````markdown
# C Loop Interview

Drives `/cloop` (full) and `/cloop-plan` (planning portion). Use the `AskUserQuestion` tool.
Skip any question already answered by `~/.claude/cloop/config.json` (see /cloop-config); state
which defaults you applied.

## Questions (ask only what's needed; collapse into as few AskUserQuestion calls as sensible)

1. **Context** — Detect whether this session already has substantial context. Ask: "Continue
   from the existing context/effort, or start fresh?" (Skip if obviously fresh/empty.)
2. **Goal & type** (fresh only) — "What should this loop work on?" Suggest options: code
   enhancement, unit tests, documentation, refactor, feature planning, performance, bug sweep.
3. **Criteria** — "Do you have precise criteria (PRD / user stories)?" If **yes**: ask the user
   to paste or drop the file; save it under `.claude/cloop/` and set `criteria_ref`. If **no**:
   ask 1–2 targeted questions to capture what "done/good" means, suggesting concrete options
   drawn from the goal.
4. **Mode** — strict (bounded, auto-stops) vs. continuous (until `/cloop-stop`).
5. **Cadence** — interval for cron, or self-paced. Apply the interval guidance from
   `plan-template.md` (steer away from `5m` and `:00`/`:30`). Suggest `20m` as a safe default.
6. **Roles** — confirm `[planner, worker, qa, scribe]`; offer to add `innovator`.
7. **Commit style** — conventional-context (default) / brief-context / custom.

## Output
Write `.claude/cloop/plans/<slug>.md` using `plan-template.md`. Generate a kebab-case `slug`
from the goal if the user doesn't supply one. Echo the slug and file path back to the user.
````

- [ ] **Step 2: Write the command**

Create `commands/cloop-plan.md`:

```markdown
---
name: cloop-plan
description: "Interview to produce a C Loop plan (no execution). Writes .claude/cloop/plans/<slug>.md."
argument-hint: "[goal hint]"
allowed-tools: ["Read", "Write", "Edit", "Bash", "AskUserQuestion", "WebSearch"]
---

# C Loop — Plan

Optional goal hint: **$ARGUMENTS**

Run the **planning interview** in `@${CLAUDE_PLUGIN_ROOT}/skills/cloop/references/interview.md`
and write the plan using `@${CLAUDE_PLUGIN_ROOT}/skills/cloop/references/plan-template.md`,
following the **C Loop engine** skill at `@${CLAUDE_PLUGIN_ROOT}/skills/cloop/SKILL.md` for the
on-disk layout. Do NOT arm a loop — stop after writing the plan and tell the user they can start
it with `/cloop-execute`.
```

- [ ] **Step 3: Verify**

Run:
```bash
grep "name:" commands/cloop-plan.md
test -f skills/cloop/references/interview.md && echo "interview ref OK"
```
Expected: `name: cloop-plan` and `interview ref OK`.

- [ ] **Step 4: Commit**

```bash
git add commands/cloop-plan.md skills/cloop/references/interview.md
git commit -m "feat(cloop): add /cloop-plan command and interview reference"
```

---

## Task 6: `/cloop-execute` — arm a durable loop from a plan

**Files:**
- Create: `commands/cloop-execute.md`

- [ ] **Step 1: Write the command**

Create `commands/cloop-execute.md`:

```markdown
---
name: cloop-execute
description: "Arm a durable C Loop from an existing plan. Lists plans to pick from; starts the cron loop."
argument-hint: "[slug]"
allowed-tools: ["Read", "Write", "Edit", "Bash", "AskUserQuestion", "CronCreate", "CronList", "PushNotification"]
---

# C Loop — Execute

Requested slug (optional): **$ARGUMENTS**

1. List existing plans in `.claude/cloop/plans/` (`ls`). If a slug was given and matches, use it.
   Otherwise present the plans via `AskUserQuestion` for the user to choose.
2. If there are NO plans, tell the user and suggest `/cloop-plan`, then stop.
3. Arm the loop by following the **"Arming a durable cron loop"** section of the engine skill at
   `@${CLAUDE_PLUGIN_ROOT}/skills/cloop/SKILL.md`. Always use `durable: true`.
4. Write/initialize `.claude/cloop/state/<slug>.state.json` per the engine's state schema and
   confirm the cadence, cron expression, job id, and expiry to the user.
```

- [ ] **Step 2: Verify**

Run: `grep "name:" commands/cloop-execute.md`
Expected: `name: cloop-execute`.

- [ ] **Step 3: Commit**

```bash
git add commands/cloop-execute.md
git commit -m "feat(cloop): add /cloop-execute durable-arming command"
```

---

## Task 7: `/cloop` — full interview then offer to execute

Composes Task 5 + Task 6: interview → write plan → offer to start now.

**Files:**
- Create: `commands/cloop.md`

- [ ] **Step 1: Write the command**

Create `commands/cloop.md`:

```markdown
---
name: cloop
description: "Start C Loop: full interview to design a continuous loop, write its plan, then offer to start iterating."
argument-hint: "[goal hint]"
allowed-tools: ["Read", "Write", "Edit", "Bash", "AskUserQuestion", "WebSearch", "CronCreate", "CronList", "PushNotification"]
---

# C Loop

Optional goal hint: **$ARGUMENTS**

1. Run the full interview in `@${CLAUDE_PLUGIN_ROOT}/skills/cloop/references/interview.md` and
   write the plan using `@${CLAUDE_PLUGIN_ROOT}/skills/cloop/references/plan-template.md`.
2. Then ask the user (via `AskUserQuestion`) whether to start the loop now.
   - If yes: arm it via the **"Arming a durable cron loop"** section of the engine skill
     `@${CLAUDE_PLUGIN_ROOT}/skills/cloop/SKILL.md` (`durable: true`) and initialize state.
   - If no: tell them they can start later with `/cloop-execute`.
```

- [ ] **Step 2: Verify**

Run: `grep "name:" commands/cloop.md`
Expected: `name: cloop`.

- [ ] **Step 3: Commit**

```bash
git add commands/cloop.md
git commit -m "feat(cloop): add /cloop full interview-to-execute command"
```

---

## Task 8: `/cloop-status` — active loops + morning report

**Files:**
- Create: `commands/cloop-status.md`

- [ ] **Step 1: Write the command**

Create `commands/cloop-status.md`:

```markdown
---
name: cloop-status
description: "Show active C Loops with current iteration, last ADR, commits, progress vs criteria, and expiry — a morning report."
argument-hint: "[slug]"
allowed-tools: ["Read", "Bash", "CronList"]
---

# C Loop — Status

Optional slug filter: **$ARGUMENTS**

Produce the **Morning report** described in the engine skill at
`@${CLAUDE_PLUGIN_ROOT}/skills/cloop/SKILL.md`.

For each `.claude/cloop/state/*.state.json` (or just the given slug): show slug, status, current
iteration, last ADR title, commits since `created_at` (`git log --oneline --since=<created_at>`),
progress vs. the plan's done criteria, and "expires in X days". Cross-check against `CronList` and
`.claude/scheduled_tasks.json`; if a loop claims `running` but its job is absent, flag it and
suggest `/cloop-fix <slug>`.
```

- [ ] **Step 2: Verify**

Run: `grep "name:" commands/cloop-status.md`
Expected: `name: cloop-status`.

- [ ] **Step 3: Commit**

```bash
git add commands/cloop-status.md
git commit -m "feat(cloop): add /cloop-status morning report command"
```

---

## Task 9: `/cloop-stop` — stop a running loop

**Files:**
- Create: `commands/cloop-stop.md`

- [ ] **Step 1: Write the command**

Create `commands/cloop-stop.md`:

```markdown
---
name: cloop-stop
description: "Stop a running C Loop: cancel its scheduled job and mark its state stopped."
argument-hint: "[slug]"
allowed-tools: ["Read", "Write", "Edit", "Bash", "AskUserQuestion", "CronList", "CronDelete"]
---

# C Loop — Stop

Requested slug (optional): **$ARGUMENTS**

1. Identify the target loop: if a slug is given use it; else list `running` loops from
   `.claude/cloop/state/*.state.json` and ask via `AskUserQuestion`.
2. Read its state, take `cron_job_id`, and `CronDelete` that job. Cross-check `CronList` to
   confirm removal.
3. Set the state's `status` to `stopped` and persist it. Confirm to the user, noting the plan and
   ADRs remain on disk so the loop can be resumed later with `/cloop-execute`.
```

- [ ] **Step 2: Verify**

Run: `grep "name:" commands/cloop-stop.md`
Expected: `name: cloop-stop`.

- [ ] **Step 3: Commit**

```bash
git add commands/cloop-stop.md
git commit -m "feat(cloop): add /cloop-stop command"
```

---

## Task 10: `/cloop-config` — user-wide defaults

**Files:**
- Create: `commands/cloop-config.md`

- [ ] **Step 1: Write the command**

Create `commands/cloop-config.md`:

```markdown
---
name: cloop-config
description: "Set user-wide C Loop defaults (commit style, interval, roles, mode, limits) so future interviews skip those questions."
argument-hint: ""
allowed-tools: ["Read", "Write", "Edit", "Bash", "AskUserQuestion"]
---

# C Loop — Config

Manage user-wide defaults stored at `~/.claude/cloop/config.json`.

1. If the file exists, read and show current values. Create the `~/.claude/cloop/` directory if
   missing.
2. Use `AskUserQuestion` to set any of: `default_mode` (strict|continuous), `default_interval`
   (e.g. 20m), `default_roles`, `default_commit_style` (conventional-context|brief-context|custom),
   `default_max_iterations`, `default_no_progress_limit`.
3. Write the file as valid JSON with exactly those keys (omit keys the user leaves unset). The
   interview (`interview.md`) reads this file and skips questions it already answers.
```

JSON shape written by this command:

```json
{
  "default_mode": "continuous",
  "default_interval": "20m",
  "default_roles": ["planner", "worker", "qa", "scribe"],
  "default_commit_style": "conventional-context",
  "default_max_iterations": 200,
  "default_no_progress_limit": 5
}
```

- [ ] **Step 2: Verify**

Run: `grep "name:" commands/cloop-config.md`
Expected: `name: cloop-config`.

- [ ] **Step 3: Commit**

```bash
git add commands/cloop-config.md
git commit -m "feat(cloop): add /cloop-config user-wide defaults command"
```

---

## Task 11: `/cloop-fix` — diagnose & re-arm a stalled loop

**Files:**
- Create: `commands/cloop-fix.md`

- [ ] **Step 1: Write the command**

Create `commands/cloop-fix.md`:

```markdown
---
name: cloop-fix
description: "Diagnose why a C Loop isn't firing and repair/re-arm it (durable job missing, expired, busy session, corrupt state)."
argument-hint: "[slug]"
allowed-tools: ["Read", "Write", "Edit", "Bash", "AskUserQuestion", "CronCreate", "CronList", "CronDelete", "PushNotification"]
---

# C Loop — Fix

Requested slug (optional): **$ARGUMENTS**

1. Identify the target loop (given slug, or pick from `.claude/cloop/state/*.state.json`).
2. Work through the **"/cloop-fix checklist"** in the engine skill at
   `@${CLAUDE_PLUGIN_ROOT}/skills/cloop/SKILL.md`, in order.
3. Re-arm with `durable: true` where the checklist calls for it, updating
   `cron_job_id`/`created_at`/`expires_at` in state.
4. Print a clear summary: what was wrong, what you changed, and the loop's current status.
```

- [ ] **Step 2: Verify**

Run: `grep "name:" commands/cloop-fix.md`
Expected: `name: cloop-fix`.

- [ ] **Step 3: Commit**

```bash
git add commands/cloop-fix.md
git commit -m "feat(cloop): add /cloop-fix diagnostics command"
```

---

## Task 12: README + end-to-end install & smoke test

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write the README**

Create `README.md`:

````markdown
# C Loop (`cloop`)

Structured, self-documenting **continuous loops** on top of Claude Code's built-in `/loop`.
Set it up once via a short interview; it iterates while you're away and leaves behind one ADR
and one verbose commit per iteration — so you wake up to a reviewable git trail.

## Install

Remote:
```
claude plugin marketplace add <your-repo-url>
# then enable "cloop" in /plugin or settings.json enabledPlugins
```

Local development (author == user):
```
claude plugin marketplace add ./        # run from this repo root
```

## Commands

| Command | Does |
|---|---|
| `/cloop` | Full interview → writes a plan → offers to start. |
| `/cloop-plan` | Planning interview only → writes `.claude/cloop/plans/<slug>.md`. |
| `/cloop-execute` | Arm a **durable** loop from an existing plan. |
| `/cloop-status` | Active loops + morning report. |
| `/cloop-stop` | Stop a loop. |
| `/cloop-config` | User-wide defaults (`~/.claude/cloop/config.json`). |
| `/cloop-fix` | Diagnose & re-arm a loop that isn't firing. |
| `/cloop-iterate` | Internal — the per-interval cron payload. |

## How it works

- Each interval, the loop fires `/cloop-iterate <slug>`, which runs ONE iteration: orient →
  work → QA → write ADR → commit → update state → stop-check.
- Iterations are keyed off a counter, not the clock, so jitter and missed fires don't matter.
- Loops are armed with `durable: true`, surviving session restarts; recurring jobs auto-expire
  after 7 days and cloop auto-re-arms + notifies.
- Pure Claude-tool scheduling (no shell / OS cron) → identical on Windows and macOS.

## Layout it creates in your project

```
.claude/cloop/plans/<slug>.md           # the plan (committed)
.claude/cloop/state/<slug>.state.json    # runtime state (gitignored)
.claude/cloop/adr/<slug>/NNNN-title.md    # one ADR per iteration (committed)
```
````

- [ ] **Step 2: Install the plugin from the local marketplace and reload**

Run (from repo root):
```bash
claude plugin marketplace add ./ 2>&1 | tail -5
```
Then in Claude Code, reload plugins (restart the session or re-run `/plugin`). Verify the
commands appear:
Expected: typing `/cloop` shows the eight commands (minus the hidden `/cloop-iterate`) in the
slash menu. If `source: "./"` fails to resolve, adjust `marketplace.json` `source` to the
absolute repo path and re-add.

- [ ] **Step 3: Empirical loop smoke test (the critical validation)**

This confirms the durable cron actually fires and persists — the core robustness claim. Use a
disposable plan and a fast interval.

1. Create a throwaway plan `.claude/cloop/plans/smoke.md` (continuous, `interval: 90s`,
   `max_iterations: 3`) whose objective is "append one timestamped line to `cloop-smoke.log`
   each iteration."
2. Run `/cloop-execute smoke`. Confirm it reports a job id and `durable: true`.
3. Verify the job persisted:
   ```bash
   python3 -m json.tool .claude/scheduled_tasks.json
   ```
   Expected: `tasks` array contains one entry whose prompt references `/cloop-iterate smoke`.
4. Let the session sit idle ~3–4 minutes. Confirm `cloop-smoke.log` gains lines, an ADR appears
   under `.claude/cloop/adr/smoke/`, `git log` shows iteration commits, and
   `.claude/cloop/state/smoke.state.json` shows `iteration` advancing.
5. Run `/cloop-status smoke` — confirm the morning report renders.
6. Run `/cloop-stop smoke` — confirm `CronList` no longer lists the job and state `status` is
   `stopped`.
7. Clean up the smoke artifacts:
   ```bash
   rm -rf .claude/cloop/plans/smoke.md .claude/cloop/state/smoke.state.json .claude/cloop/adr/smoke cloop-smoke.log
   ```

If step 4 produces no lines after ~5 minutes, run `/cloop-fix smoke` and confirm the checklist
identifies the cause — this exercises the diagnostics path too.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs(cloop): add README; verified end-to-end durable loop smoke test"
```

---

## Self-Review (completed during planning)

**Spec coverage:** Every spec section maps to a task — §3.2 layout + §3.4 state (Task 3 engine,
+ gitignore handled in Task 3 / already in repo), §3.3 plan format (Task 2), §4 lifecycle
(Task 3 + Task 4), §5 modes/rails (Task 3), §6 ADR/commit (Task 2 + Task 3), §7 all eight
commands (Tasks 4–11), §8 fix checklist (Task 3 + Task 11), §9 packaging/deploy (Task 1 + Task
12), cross-platform (Task 3 engine note + Task 12 install). §11 open questions are exercised by
the Task 12 smoke test (durable persistence + slash-command-as-cron-payload across the loop).

**Placeholder scan:** No TBD/TODO; every file's full content is provided.

**Type/name consistency:** `slug`, `cron_job_id`, `consecutive_no_progress`, `no_progress_limit`,
`max_iterations`, `commit_style`/`custom_commit_template`, `workflow_script`, `criteria_ref`,
`status` values (`running|paused|stopped|completed`), and the `/cloop-iterate <slug>` payload are
used identically across the engine, commands, templates, and state schema.
````
