# C Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `cloop` Claude Code plugin (v0.1) — a robust, cross-platform, **cron-only** wrapper around the built-in `/loop` that runs structured, self-documenting continuous loops (interview → plan → durable cron iterations → per-iteration ADR + verbose commit → diagnostics), with a deterministic test tier.

**Architecture:** One plugin at the repo root. Eight thin `commands/*.md` slash entry points delegate to ONE engine skill (`skills/cloop-engine/SKILL.md`). The loop is driven by `CronCreate`/`CronList`/`CronDelete` (Claude tools, no shell, no OS cron). Per-loop plans/state/ADRs live under the target project's `.claude/cloop/`. Iterations run **unattended and non-interactively** on an isolated branch.

**Tech Stack:** Claude Code plugin (Markdown + YAML frontmatter + JSON manifests). **No runtime language** (the runtime path uses only git + Claude tools). `python3`/bash appear only in build/test steps, which are scoped to a POSIX dev env (macOS, or Git Bash/WSL on Windows).

**Spec:** `docs/superpowers/specs/2026-06-01-cloop-design.md` — read it fully before starting; this plan implements it.

**Load-bearing facts (spec §2):**
- v0.1 is **cron-only**; `interval` is REQUIRED (whole-minute floor). Dynamic/`ScheduleWakeup` is deferred.
- Overnight loops use `durable: true` (persisted to project-local `.claude/scheduled_tasks.json`); they fire **only while a session is open & idle**, restored on `--resume`.
- Plugin commands are **namespaced**: invoked as `/cloop:<command>`. The cron payload is `/cloop:cloop-iterate <slug>` (with a self-contained natural-language fallback).
- Iterations are keyed off a persisted **fire counter** (bumped before work), never the clock.
- An iteration must **never** call a human-waiting tool or trigger a permission prompt.

---

## File Structure

```
.claude-plugin/plugin.json
.claude-plugin/marketplace.json       # self-marketplace; NO $schema line
commands/
  cloop.md  cloop-plan.md  cloop-execute.md  cloop-iterate.md
  cloop-config.md  cloop-status.md  cloop-stop.md  cloop-fix.md
skills/cloop-engine/SKILL.md                 # the engine (all shared logic)
skills/cloop-engine/references/
  plan-template.md  adr-template.md  commit-templates.md  interview.md
test/
  validate.sh                         # deterministic static-tier gate (POSIX dev env)
  schemas/state.schema.json  schemas/config.schema.json
  golden/                             # golden ADR + commit fixtures
README.md
.gitignore                            # contains .claude/cloop/state/
```

**Responsibility boundaries:** `commands/*.md` are thin — parse `$ARGUMENTS`, then **Read** `${CLAUDE_PLUGIN_ROOT}/skills/cloop-engine/SKILL.md` and follow the relevant section (the Read inlines engine text; it does not invoke a separate skill, so each command's own `allowed-tools` is the load-bearing permission). `skills/cloop-engine/SKILL.md` is the single source of truth for the lifecycle, state schema, safety rails, and `/cloop-fix`.

---

## Task 1: Plugin scaffold + installable manifests + validate gate

**Files:** Create `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`

- [ ] **Step 1: Write the plugin manifest** — `.claude-plugin/plugin.json`:

```json
{
  "name": "cloop",
  "version": "0.1.0",
  "description": "C Loop: structured, self-documenting continuous loops on top of Claude Code's /loop. Interview-driven setup, pluggable per-loop plans, per-iteration ADRs and verbose commits, durable cron with self-healing diagnostics.",
  "author": { "name": "Abraham Nguyen" }
}
```

- [ ] **Step 2: Write the self-marketplace manifest** — `.claude-plugin/marketplace.json` (no `$schema`; it is ignored at load and the documented URL was wrong):

```json
{
  "name": "cloop-marketplace",
  "description": "Marketplace hosting the C Loop plugin.",
  "owner": { "name": "Abraham Nguyen" },
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

- [ ] **Step 3: Validate (syntax + schema).** JSON syntax:
```bash
python3 -m json.tool .claude-plugin/plugin.json >/dev/null && echo "plugin.json OK"
python3 -m json.tool .claude-plugin/marketplace.json >/dev/null && echo "marketplace.json OK"
```
Then the authoritative validator (co-located marketplace.json blinds the plugin check, so validate the marketplace explicitly):
```bash
claude plugin validate ./.claude-plugin/marketplace.json --strict; echo "exit=$?"
```
Expected: both `OK`; validator exit `0`. (Plugin commands/skills are validated in Task 12 once they exist.)

- [ ] **Step 4: Commit**
```bash
git add .claude-plugin/
git commit -m "feat(cloop): add plugin + self-marketplace manifests"
```

---

## Task 2: Reference templates

**Files:** Create `skills/cloop-engine/references/{plan-template,adr-template,commit-templates}.md`

- [ ] **Step 1: `plan-template.md`**

````markdown
# C Loop Plan Template

The engine parses ONLY the frontmatter (fixed key set; unknown keys are ignored with a warning).
Prose sections are context for the working agent.

```markdown
---
slug: <kebab-case-id>
mode: continuous            # strict | continuous
interval: 20m               # REQUIRED in v0.1; whole-minute floor (e.g. 1m, 2m, 20m, 2h)
engine: cron                # cron (v0.1). 'dynamic' is reserved / not yet implemented.
branch: cloop/<slug>        # default cloop/<slug>; 'current' to commit on the checked-out branch; or a named branch
commit_style: conventional-context   # conventional-context | brief-context | custom
custom_commit_template: null          # required only when commit_style: custom
max_iterations: 50          # hard ceiling on FIRES; confirmed at arm time
no_progress_limit: 5         # consecutive no-real-progress iterations → auto-pause + notify
criteria_ref: null           # optional REPO-RELATIVE path to PRD.json / user-stories.md
---

# Objective
<what this loop is trying to achieve and what "good" looks like>

# Done criteria
<bullet list, OR "See criteria_ref">

# Iteration scope / guardrails
<what ONE iteration should accomplish; what NOT to touch; repo-specific constraints>
```

## Interval guidance (author heuristics, NOT Anthropic constants)
- Whole-minute floor: cron has 1-minute granularity; sub-minute values round up. No `90s`.
- `< ~270s`: prompt cache stays warm but burns tokens fastest — short bursts only.
- `5m`: worst case — pays a full cache miss without amortizing. Avoid.
- `>= ~20m`: economical for overnight runs (cache expires; each iteration starts cold). Recommended default.
- Jitter is significant: recurring jobs can fire up to ~30 min late (or up to half the interval
  for sub-hourly tasks). Never rely on exact timing. The engine picks a non-`:00`/`:30` minute.
````

- [ ] **Step 2: `adr-template.md`**

````markdown
# C Loop ADR Template

One ADR per iteration: `.claude/cloop/adr/<slug>/NNNN-<title>.md`.
- `NNNN` = (committed-iteration count) + 1, zero-padded to 4. Derived at write time from the
  highest existing ADR number in the slug's ADR dir (cross-checked with `git log`).
- `<title>` = kebab-case of the ADR's one-line subject, `[a-z0-9-]` only, max ~6 words.
- The ADR is committed in the SAME commit as the change, so it has NO `commit:` field; the ADR and
  its commit share the iteration number (recover via `git log --grep "iteration N"`).

```markdown
---
id: NNNN
iteration: N
date: <ISO-8601>
status: accepted          # proposed | accepted | superseded
plan_slug: <slug>
qa_result: pass           # pass | fail | n/a  (feeds the no-progress detector)
---

## Context
<why this iteration did what it did; repo state going in>

## Decision
<what was changed and the approach>

## Alternatives considered
<options weighed and why rejected; "none — mechanical change" is acceptable>

## Consequences
<effects, follow-ups, risks>

## Links
- files: <touched paths>
```
````

- [ ] **Step 3: `commit-templates.md`**

````markdown
# C Loop Commit Templates

Placeholder substitution is done by the Scribe agent (no engine "machine"). The `ADR:` pointer is
always the FULL repo-root-relative path. Trailers use ASCII separators (no non-ASCII middle dot).

## conventional-context (default)
```
<type>(<scope>): <concise summary>

Why: <1-3 sentence rationale from the ADR Context/Decision>
ADR: .claude/cloop/adr/<slug>/NNNN-title.md
Loop: <slug> | iteration N
```
`<type>` ∈ feat, fix, refactor, test, docs, chore, perf, style.

## brief-context
```
<concise non-conventional subject>

Why: <1-3 sentence rationale>
ADR: .claude/cloop/adr/<slug>/NNNN-title.md
Loop: <slug> | iteration N
```

## custom
Use the plan's `custom_commit_template` verbatim. It MUST include the full ADR path and the
iteration number so the trail stays intact. Substituted placeholders: `{summary}`, `{why}`,
`{adr_path}`, `{slug}`, `{iteration}`, `{type}`, `{scope}`.
````

- [ ] **Step 4: Verify** — `for f in plan-template adr-template commit-templates; do head -1 "skills/cloop-engine/references/$f.md"; done` → three `# C Loop …` headers.
- [ ] **Step 5: Commit** — `git add skills/cloop-engine/references/ && git commit -m "feat(cloop): add plan, ADR, and commit reference templates"`

---

## Task 3: The engine skill

**Files:** Create `skills/cloop-engine/SKILL.md`

- [ ] **Step 1: Write `skills/cloop-engine/SKILL.md`**

````markdown
---
name: cloop
description: C Loop engine — runs structured, self-documenting continuous loops on top of Claude Code's /loop (cron). Use when arming, iterating, inspecting, stopping, or repairing a cloop. Defines the iteration lifecycle, state/ADR/commit specs, durable cron arming, safety rails, and diagnostics. Read by the /cloop-* commands.
---

# C Loop Engine

C Loop wraps Claude Code's built-in `/loop` (cron) to run structured, self-documenting continuous
loops. Each iteration produces one ADR and one verbose commit. The engine is fixed; *what* a loop
works on is defined by a pluggable plan file. This skill is the shared logic for all `/cloop-*`
commands — follow the relevant section when a command Reads it.

## On-disk layout (TARGET project, repo-root-relative)
```
.claude/cloop/plans/<slug>.md              # plan (committed)
.claude/cloop/state/<slug>.state.json      # runtime state (gitignored)
.claude/cloop/state/<slug>.lock            # advisory cross-session lock (gitignored)
.claude/cloop/adr/<slug>/NNNN-title.md      # one ADR per iteration (committed)
.claude/scheduled_tasks.json               # native durable cron store (managed by Claude Code)
```
On first use, ensure `.gitignore` contains `.claude/cloop/state/`: Read it; if absent, append the
line via Edit/Write (idempotent — never a shell redirect; works on Windows + macOS).

## Cross-platform rule (load-bearing)
The runtime path uses ONLY git + Claude tools (Read/Write/Edit/Glob, and Bash or PowerShell for
git). Prescribe TOOL-level operations, not shell idioms: enumerate plans via Glob/Read; edit
.gitignore via Read+Edit; count commits since arming by SHA range (`git log --oneline
<armed_at_sha>..HEAD`), never `--since=<date>`. NO runtime Node or Python.

## State schema (`<slug>.state.json`) — write ATOMICALLY (write .tmp, then rename over real file)
```json
{
  "slug": "<slug>", "status": "running",
  "fires": 0, "iteration": 0,
  "cron_job_id": "<id>", "engine": "cron", "interval": "20m",
  "branch": "cloop/<slug>", "armed_at_sha": "<HEAD sha at arm>",
  "durable": true, "created_at": "<ISO>", "expires_at": "<ISO+7d>", "rearm_after": "<ISO≈expires−1d>",
  "last_adr": null, "last_commit": null, "consecutive_no_progress": 0,
  "session_marker": "<session id>"
}
```
`status` ∈ running|paused|stopped|completed. Stamp times/SHAs when writing.

## NON-INTERACTIVITY INVARIANT (the most important rule)
`/cloop-iterate` runs UNATTENDED in the live session between turns. It MUST NEVER call
AskUserQuestion, EnterPlanMode/ExitPlanMode, or any human-waiting tool, and MUST NOT trigger a
permission prompt — any such call freezes the ENTIRE loop until a human returns. Resolve ALL
ambiguity from plan + state + last ADR + criteria_ref. If you cannot proceed unambiguously, set
status:paused, PushNotification, and STOP. Never ask.

## Roles (inline behaviors; single agent; NO subagents/Workflow in v0.1)
Planner (scope one change) → Worker (implement) → QA (verify vs done criteria) → Scribe (ADR +
commit). These are fixed lifecycle phases, not a configurable list.

## Iteration lifecycle (run by /cloop-iterate; EXACTLY ONE per fire)
Iterations key off the persisted counters, never the clock. Iteration identity derives from
committed ADRs/git, not the gitignored state file (crash-safe).

1. **Load & lock** — write `<slug>.lock` (session_marker + ISO now). If a FRESH lock from a
   different session exists, STOP (another session owns this loop). Read plan + state. Bump and
   atomically persist `fires += 1` BEFORE any work. If state missing → STOP, tell user to run
   `/cloop:cloop-fix <slug>`.
2. **Guard** — if `status != running` → STOP. If `fires > max_iterations` → finalize (Stop
   conditions). If `consecutive_no_progress >= no_progress_limit` → set paused, PushNotification,
   STOP. Ensure current git branch == plan `branch` (unless `branch: current`); if a checkout is
   needed and clean, do it; if it would require resolving a dirty tree (a prompt) → pause+notify.
3. **Expiry check** — if now ≥ `rearm_after` → RE-ARM transactionally (see Arming) before working;
   PushNotification that it re-armed.
4. **Orient (Planner)** — scope ONE coherent change from plan + state + last ADR + `git log`.
5. **Work (Worker)** — implement it.
6. **Check (QA)** — verify against done criteria / criteria_ref; record pass/fail.
7. **Document (Scribe)** — NNNN = max(existing ADR numbers in adr/<slug>/) + 1 (cross-check
   `git log`), zero-padded to 4; title = kebab one-line subject. Write the ADR (qa_result set).
8. **Commit** — stage ONLY this iteration's files + the ADR by EXPLICIT path (never `git add -A`/`.`).
   Secret guard: if any staged path looks like a secret (.env, *key*, *cred*, token patterns),
   UNSTAGE + skip it and note in the ADR. Make EXACTLY ONE local commit via `commit_style`. NEVER
   push, --force, rebase, reset --hard, or amend. End with a CLEAN working tree: if nothing to
   change, make no commit and `git restore`/drop partial edits.
9. **Update state (sole owner of counters)** — set `iteration` = NNNN, `last_adr`, `last_commit`.
   `consecutive_no_progress = 0` IFF a real commit was made AND QA passed; else increment it.
   Atomic write. Release lock.
10. **Stop check** — see Stop conditions.

## Stop conditions
- Strict: done criteria met OR `fires >= max_iterations` → `CronDelete` cron_job_id, status:
  completed, final summary line, PushNotification.
- Continuous: until `/cloop-stop`; still bounded by max_iterations (→completed) and no-progress (→paused).

## Arming a durable cron loop (used by /cloop-execute, /cloop, and re-arm)
1. Read plan frontmatter. `interval` is REQUIRED — if absent, REFUSE: "self-paced/dynamic loops
   are not supported in v0.1; specify an interval (e.g. 20m)." Validate `branch` and `criteria_ref`
   (repo-relative, no `..`, no absolute, no symlink escape).
2. Build a 5-field cron expression from `interval`, choosing a non-`:00`/`:30` minute (e.g. `20m`
   → `7,27,47 * * * *`; hourly → `7 * * * *`). Whole-minute floor.
3. Cost confirm: show `~max_iterations fires × interval → est. duration` (note token cost scales
   with iterations) and get confirmation before arming. (In /cloop-iterate's re-arm path this is
   skipped — already confirmed.)
4. Branch: if `branch != current`, create/checkout `branch`; record `armed_at_sha` = HEAD sha.
5. `CronCreate` with `durable: true`, `recurring: true`, and a SELF-CONTAINED prompt (does not
   depend solely on slash expansion):
   `Run exactly ONE C Loop iteration for slug "<slug>": invoke /cloop:cloop-iterate <slug> (and if
   that is unavailable, Read .claude/cloop/ + this repo's cloop engine and run one iteration).`
6. Capture the job id → `cron_job_id`; set durable:true, created_at=now, expires_at=now+7d,
   rearm_after≈expires−1d; atomic write state. Confirm slug, interval, cron expr, job id, branch,
   expiry to the user.

### Transactional RE-ARM (expiry / fix)
(a) `CronCreate` the new durable+recurring job, capture new id; (b) verify via `CronList` it
registered — if NOT, keep old cron_job_id, PushNotification failure, STOP; (c) `CronDelete` the old
job; (d) update cron_job_id/created_at/expires_at/rearm_after; atomic write. Never leave two live
jobs or zero.

## /cloop-fix checklist (in order; then repair)
1. `CLAUDE_CODE_DISABLE_CRON` set? → report (cron globally disabled).
2. Session parked on an AskUserQuestion/permission prompt? → loop can't fire (never idle); tell
   user to answer/dismiss; flag the offending path.
3. Job present? Read `.claude/scheduled_tasks.json` + `CronList`; is cron_job_id there?
4. Duplicate jobs for this slug? → `CronDelete` extras, keep one.
5. Missing but status running → in-memory death OR fresh conversation instead of `--resume`.
   Advise resuming the arming session, or re-arm transactionally; update cron_job_id.
6. Present but `fires` not advancing → session rarely idle (long iterations/busy) → advise
   smaller scope; offer longer interval.
7. Near expiry (≥ rearm_after) → re-arm transactionally.
8. State/lock corrupt or stale → rebuild state from highest ADR + `git log` + plan; clear stale lock.
9. Stopped legitimately (criteria met / ceiling) → report; offer to raise ceiling or go continuous.

## Morning report (used by /cloop-status)
One scannable line per loop: `<slug> [status] iter N/max · C commits since arm · last ADR "<title>"
· expires in Xd`. Commit count via SHA range `git log --oneline <armed_at_sha>..HEAD`. Lead with
deterministic facts; treat progress-vs-criteria as best-effort qualitative. For any detected
problem (running-but-job-absent, duplicate jobs, near-expiry, corrupt state) print the EXACT
remediation command (e.g. `/cloop:cloop-fix <slug>`). Define an explicit empty state ("no active
loops").
````

- [ ] **Step 2: Verify** — `sed -n '1,4p' skills/cloop-engine/SKILL.md` shows `name: cloop`; `grep -c "^## " skills/cloop-engine/SKILL.md` ≥ 10.
- [ ] **Step 3: Commit** — `git add skills/cloop-engine/SKILL.md && git commit -m "feat(cloop): add the engine skill (lifecycle, safety rails, arming, fix)"`

---

## Task 4: `/cloop-iterate` — internal unattended cron payload

**Files:** Create `commands/cloop-iterate.md`

- [ ] **Step 1: Write `commands/cloop-iterate.md`** — `user-invocable: false` hides it; `disallowed-tools` structurally blocks human-waiting tools:

```markdown
---
name: cloop-iterate
description: "INTERNAL — runs exactly one unattended C Loop iteration for a slug. Fired by the loop's cron job."
argument-hint: "<slug>"
user-invocable: false
allowed-tools: ["Read", "Write", "Edit", "Glob", "Bash", "CronCreate", "CronDelete", "CronList", "PushNotification"]
disallowed-tools: ["AskUserQuestion", "EnterPlanMode", "ExitPlanMode"]
---

# C Loop — Run One Iteration (UNATTENDED)

Slug: **$ARGUMENTS**

Read `${CLAUDE_PLUGIN_ROOT}/skills/cloop-engine/SKILL.md` and follow its **Iteration lifecycle** section
for the slug above. Run EXACTLY ONE iteration, then stop — do NOT loop internally; the cron
schedule fires the next one.

This runs with NO human present. NEVER call a tool that waits for a human and NEVER do anything
that would trigger a permission prompt. Resolve all ambiguity from the plan + state + last ADR +
criteria_ref; if you cannot, set status:paused, PushNotification, and STOP (per the
NON-INTERACTIVITY INVARIANT). If state is missing or status != running, follow the Guard step.
```

- [ ] **Step 2: Verify** — `grep -E "name:|user-invocable:|disallowed-tools:" commands/cloop-iterate.md` shows all three.
- [ ] **Step 3: Commit** — `git add commands/cloop-iterate.md && git commit -m "feat(cloop): add internal unattended /cloop-iterate cron payload"`

---

## Task 5: `/cloop-plan` + interview reference

**Files:** Create `skills/cloop-engine/references/interview.md`, `commands/cloop-plan.md`

- [ ] **Step 1: `skills/cloop-engine/references/interview.md`**

````markdown
# C Loop Interview

Drives `/cloop` (full) and `/cloop-plan` (planning portion). Uses `AskUserQuestion` — these run
with a present user, NEVER by cron. Skip any question already set by `~/.claude/cloop/config.json`
(precedence: explicit answer > config default > built-in default); state which defaults applied.

1. **Context** — heuristic: if `/cloop` got a goal-hint arg, OR the conversation already contains a
   concrete goal the loop could continue → OFFER "continue existing context"; else default fresh
   (do not ask a confusing question in an empty session).
2. **Goal & type** (fresh) — suggest: code enhancement, unit tests, documentation, refactor,
   feature planning, performance, bug sweep.
3. **Criteria** — "Precise criteria (PRD / user stories)?" Yes → user pastes/drops; save under
   `.claude/cloop/` and set `criteria_ref`. No → 1-2 targeted questions on what "done/good" means.
4. **Cadence & safety** — mode (strict/continuous); interval (whole-minute; explain in plain terms
   that ~5m is the costliest band and steer to ≥20m for overnight; engine avoids :00/:30); branch
   isolation (default ON → `cloop/<slug>`; offer `current` to opt out); commit style.
5. **Confirm slug** — propose the generated kebab slug; let the user accept or rename (it is their
   handle to every command).

Output: write `.claude/cloop/plans/<slug>.md` from `plan-template.md`. Echo slug + path.
````

- [ ] **Step 2: `commands/cloop-plan.md`**

```markdown
---
name: cloop-plan
description: "Interview to produce a C Loop plan (no execution). Writes .claude/cloop/plans/<slug>.md."
argument-hint: "[goal hint]"
allowed-tools: ["Read", "Write", "Edit", "Glob", "Bash", "AskUserQuestion", "WebSearch"]
---

# C Loop — Plan

Optional goal hint: **$ARGUMENTS**

Read `${CLAUDE_PLUGIN_ROOT}/skills/cloop-engine/SKILL.md` (layout) and run the interview in
`${CLAUDE_PLUGIN_ROOT}/skills/cloop-engine/references/interview.md`, writing the plan from
`${CLAUDE_PLUGIN_ROOT}/skills/cloop-engine/references/plan-template.md`. Do NOT arm a loop — stop after
writing the plan and tell the user to start it with `/cloop:cloop-execute`.
```

- [ ] **Step 3: Verify** — `grep "name:" commands/cloop-plan.md` and `test -f skills/cloop-engine/references/interview.md && echo OK`.
- [ ] **Step 4: Commit** — `git add commands/cloop-plan.md skills/cloop-engine/references/interview.md && git commit -m "feat(cloop): add /cloop-plan and interview reference"`

---

## Task 6: `/cloop-execute` — arm a durable loop

**Files:** Create `commands/cloop-execute.md`

- [ ] **Step 1: Write `commands/cloop-execute.md`**

```markdown
---
name: cloop-execute
description: "Arm a durable C Loop from an existing plan: estimate+confirm, create the branch, start the cron loop."
argument-hint: "[slug]"
allowed-tools: ["Read", "Write", "Edit", "Glob", "Bash", "AskUserQuestion", "CronCreate", "CronList", "PushNotification"]
---

# C Loop — Execute

Requested slug (optional): **$ARGUMENTS**

1. Enumerate plans in `.claude/cloop/plans/` (Glob/Read). If a slug was given and matches, use it;
   else present choices via `AskUserQuestion`. No plans → suggest `/cloop:cloop-plan` and stop.
2. Read `${CLAUDE_PLUGIN_ROOT}/skills/cloop-engine/SKILL.md` and follow **"Arming a durable cron loop"**:
   require `interval`; validate `branch`/`criteria_ref`; show the cost estimate and CONFIRM;
   create/checkout the branch; `CronCreate` durable+recurring with the self-contained payload;
   record cron_job_id/armed_at_sha; initialize state (atomic write).
3. Confirm cadence, cron expression, job id, branch, and expiry to the user.
```

- [ ] **Step 2: Verify** — `grep "name:" commands/cloop-execute.md`.
- [ ] **Step 3: Commit** — `git add commands/cloop-execute.md && git commit -m "feat(cloop): add /cloop-execute durable-arming command"`

---

## Task 7: `/cloop` — full interview then offer to execute

**Files:** Create `commands/cloop.md`

- [ ] **Step 1: Write `commands/cloop.md`**

```markdown
---
name: cloop
description: "Start C Loop: full interview to design a continuous loop, write its plan, then (with a cost estimate) offer to start iterating."
argument-hint: "[goal hint]"
allowed-tools: ["Read", "Write", "Edit", "Glob", "Bash", "AskUserQuestion", "WebSearch", "CronCreate", "CronList", "PushNotification"]
---

# C Loop

Optional goal hint: **$ARGUMENTS**

1. Read `${CLAUDE_PLUGIN_ROOT}/skills/cloop-engine/SKILL.md`, run the interview in
   `${CLAUDE_PLUGIN_ROOT}/skills/cloop-engine/references/interview.md`, write the plan from
   `plan-template.md`.
2. Then ask (via `AskUserQuestion`) whether to start now.
   - Yes → follow **"Arming a durable cron loop"** (estimate+confirm, branch, durable CronCreate,
     init state).
   - No → tell them to start later with `/cloop:cloop-execute`.
```

- [ ] **Step 2: Verify** — `grep "name:" commands/cloop.md`.
- [ ] **Step 3: Commit** — `git add commands/cloop.md && git commit -m "feat(cloop): add /cloop full interview-to-execute command"`

---

## Task 8: `/cloop-status` — morning report

**Files:** Create `commands/cloop-status.md`

- [ ] **Step 1: Write `commands/cloop-status.md`**

```markdown
---
name: cloop-status
description: "Show active C Loops (iteration, last ADR, commits, expiry) as a morning report; print exact remediation commands for any problem."
argument-hint: "[slug]"
allowed-tools: ["Read", "Glob", "Bash", "CronList"]
---

# C Loop — Status

Optional slug filter: **$ARGUMENTS**

Read `${CLAUDE_PLUGIN_ROOT}/skills/cloop-engine/SKILL.md` and produce the **Morning report** for each
`.claude/cloop/state/*.state.json` (or the given slug): one scannable line per loop (status,
iter N/max, commit count via `git log --oneline <armed_at_sha>..HEAD`, last ADR title, expires in
Xd). Cross-check `CronList` + `.claude/scheduled_tasks.json`; if a loop claims running but its job
is absent (or duplicated, or near expiry, or state corrupt), print the EXACT remediation command
(e.g. `/cloop:cloop-fix <slug>`). If there are no loops, say so plainly.
```

- [ ] **Step 2: Verify** — `grep "name:" commands/cloop-status.md`.
- [ ] **Step 3: Commit** — `git add commands/cloop-status.md && git commit -m "feat(cloop): add /cloop-status morning report"`

---

## Task 9: `/cloop-stop`

**Files:** Create `commands/cloop-stop.md`

- [ ] **Step 1: Write `commands/cloop-stop.md`**

```markdown
---
name: cloop-stop
description: "Stop a running C Loop: cancel its scheduled job and mark its state stopped."
argument-hint: "[slug]"
allowed-tools: ["Read", "Write", "Edit", "Glob", "Bash", "AskUserQuestion", "CronList", "CronDelete"]
---

# C Loop — Stop

Requested slug (optional): **$ARGUMENTS**

1. Identify the loop: given slug, else list `running` loops from `.claude/cloop/state/*.state.json`
   and ask via `AskUserQuestion`.
2. Read its state; `CronDelete` the `cron_job_id`; cross-check `CronList` to confirm removal
   (delete any duplicates for the slug too).
3. Set state `status: stopped` (atomic write). Confirm; note the plan, ADRs, and branch remain so
   the loop can be resumed later with `/cloop:cloop-execute`.
```

- [ ] **Step 2: Verify** — `grep "name:" commands/cloop-stop.md`.
- [ ] **Step 3: Commit** — `git add commands/cloop-stop.md && git commit -m "feat(cloop): add /cloop-stop command"`

---

## Task 10: `/cloop-config` — user-wide defaults (pinned schema + precedence)

**Files:** Create `commands/cloop-config.md`

- [ ] **Step 1: Write `commands/cloop-config.md`**

```markdown
---
name: cloop-config
description: "Read/write user-wide C Loop defaults (~/.claude/cloop/config.json) so interviews can skip those questions."
argument-hint: ""
allowed-tools: ["Read", "Write", "Edit", "Bash", "AskUserQuestion"]
---

# C Loop — Config

Manage user-wide defaults at `~/.claude/cloop/config.json` (also hand-editable). Create
`~/.claude/cloop/` if missing. Show current values, then set any keys via `AskUserQuestion`.

Schema (write valid JSON; omit unset keys):
```json
{
  "default_mode": "continuous",
  "default_interval": "20m",
  "default_commit_style": "conventional-context",
  "default_max_iterations": 50,
  "default_no_progress_limit": 5,
  "default_branch_isolation": true
}
```
Precedence the interview MUST follow: explicit interview answer > config default > built-in default.
```

- [ ] **Step 2: Verify** — `grep "name:" commands/cloop-config.md`.
- [ ] **Step 3: Commit** — `git add commands/cloop-config.md && git commit -m "feat(cloop): add /cloop-config with pinned schema + precedence"`

---

## Task 11: `/cloop-fix` — diagnose & re-arm

**Files:** Create `commands/cloop-fix.md`

- [ ] **Step 1: Write `commands/cloop-fix.md`**

```markdown
---
name: cloop-fix
description: "Diagnose why a C Loop isn't firing and repair/re-arm it (disabled cron, parked prompt, missing/duplicate/expired job, fresh-vs-resumed session, corrupt state)."
argument-hint: "[slug]"
allowed-tools: ["Read", "Write", "Edit", "Glob", "Bash", "AskUserQuestion", "CronCreate", "CronList", "CronDelete", "PushNotification"]
---

# C Loop — Fix

Requested slug (optional): **$ARGUMENTS**

1. Identify the loop (given slug, or pick from `.claude/cloop/state/*.state.json`).
2. Read `${CLAUDE_PLUGIN_ROOT}/skills/cloop-engine/SKILL.md` and work the **"/cloop-fix checklist"** in
   order (incl. disabled-cron, parked-prompt, missing/duplicate/expired job, fresh-vs-resumed
   session, corrupt/stale state/lock).
3. Re-arm **transactionally** where the checklist calls for it (CronCreate new → verify via
   CronList → CronDelete old → update state).
4. Print a clear summary: what was wrong, what changed, current status.
```

- [ ] **Step 2: Verify** — `grep "name:" commands/cloop-fix.md`.
- [ ] **Step 3: Commit** — `git add commands/cloop-fix.md && git commit -m "feat(cloop): add /cloop-fix diagnostics"`

---

## Task 12: Deterministic test tier (static + golden + headless invariants)

This is the unit-test layer. It is CI-able and mostly deterministic. POSIX dev env (bash/python3;
on Windows use Git Bash/WSL) — these are BUILD/TEST tools, not runtime.

**Files:** Create `test/validate.sh`, `test/schemas/state.schema.json`, `test/schemas/config.schema.json`, `test/golden/` fixtures.

- [ ] **Step 1: Write JSON schemas** — `test/schemas/state.schema.json` and `config.schema.json` describing the §3.4 state and §7 config shapes (required keys, enums for `status`/`engine`). Validate with any JSON-schema check available; if none, fall back to `python3 -m json.tool` syntax + a key-presence grep.

- [ ] **Step 2: Write `test/validate.sh`** — a single exit-code gate. It must:
  1. `claude plugin validate ./.claude-plugin/marketplace.json --strict` (marketplace).
  2. Validate the plugin's commands+skills (per spec §9 two-path workaround — invoke
     `claude plugin validate` against the plugin so commands/skills are checked, not just the
     co-located marketplace). Fail on non-zero.
  3. Frontmatter lint: each `commands/*.md` + `skills/**/SKILL.md` begins with `---` … `---` and
     has a `description:`; assert `commands/cloop-iterate.md` contains `user-invocable: false` and
     `disallowed-tools:` listing `AskUserQuestion`.
  4. `@`/`${CLAUDE_PLUGIN_ROOT}` resolver: extract every `${CLAUDE_PLUGIN_ROOT}/<path>` token from
     `commands/*.md` and `skills/**/*.md`, strip the var, and assert each file exists.
  5. Grep gates: fail on any `TODO|TBD|FIXME` in `commands skills README.md`; assert the canonical
     state-key set appears identically in SKILL.md and the schemas.
  Each check prints PASS/FAIL and the script exits non-zero on any failure.

Skeleton:
```bash
#!/usr/bin/env bash
set -uo pipefail
fail=0
note(){ printf '%s %s\n' "$1" "$2"; }
# 1+2 validator
claude plugin validate ./.claude-plugin/marketplace.json --strict >/dev/null 2>&1 \
  && note PASS "marketplace validate" || { note FAIL "marketplace validate"; fail=1; }
# 3 frontmatter + iterate guards
grep -q 'user-invocable: false' commands/cloop-iterate.md && grep -q 'AskUserQuestion' commands/cloop-iterate.md \
  && note PASS "iterate non-interactive guards" || { note FAIL "iterate guards"; fail=1; }
# 4 resolver
while IFS= read -r p; do
  rel="${p#*CLAUDE_PLUGIN_ROOT/}"; [ -f "$rel" ] || { note FAIL "missing ref: $rel"; fail=1; }
done < <(grep -rhoE '\$\{CLAUDE_PLUGIN_ROOT\}/[A-Za-z0-9._/-]+' commands skills | sort -u)
[ "$fail" -eq 0 ] && note PASS "ref resolver" || true
# 5 placeholders
! grep -RInE 'TODO|TBD|FIXME' commands skills README.md >/dev/null \
  && note PASS "no TODO/TBD" || { note FAIL "found TODO/TBD"; fail=1; }
exit "$fail"
```

- [ ] **Step 3: Golden tests** — In `test/golden/`, store a fixed ADR input and the expected ADR
  file body, plus a fixed (summary, why, slug, iteration, adr_path) tuple and the expected
  `conventional-context` and `brief-context` commit messages. Add a check (in `validate.sh` or a
  sibling script) that rendering the templates with the fixed inputs equals the golden files
  byte-for-byte. (Rendering is done by following the template rules; the test pins the exact
  output so template drift is caught deterministically.)

- [ ] **Step 4: Run the gate** — `bash test/validate.sh; echo "exit=$?"` → all PASS, `exit=0`.

- [ ] **Step 5: Commit** — `git add test/ && git commit -m "test(cloop): add deterministic static + golden test gate"`

---

## Task 13: README + headless invariant test + E2E smoke

**Files:** Create `README.md`

- [ ] **Step 1: Write `README.md`** — include the honest framing and correct install:

````markdown
# C Loop (`cloop`)

Structured, self-documenting **continuous loops** on top of Claude Code's built-in `/loop`. Set it
up via a short interview; it iterates on an interval and leaves one ADR + one verbose commit per
iteration — so you wake up to a reviewable git trail on an isolated branch.

## What it does and does NOT do
Scheduled iterations fire **only while a Claude Code session is open and idle on a running
machine.** Closing the terminal or exiting stops them. `durable: true` persists the job so it is
**restored when you resume the same session** (`claude --resume`/`--continue`, within 7 days) — it
does NOT keep running with no session. Use it as "leave a session open/idle overnight, or resume in
the morning," not "close the laptop and it keeps coding."

## Install
Local dev:
```
claude plugin marketplace add ./
/plugin install cloop@cloop-marketplace      # or add cloop@cloop-marketplace to enabledPlugins
```
Remote:
```
claude plugin marketplace add <owner>/<repo>
/plugin install cloop@cloop-marketplace
```
Commands surface namespaced as `/cloop:cloop`, `/cloop:cloop-plan`, … (`/cloop:cloop-iterate` is hidden).

## Commands
| Command | Does |
|---|---|
| `/cloop:cloop` | Full interview → plan → (estimate + confirm) → offer to start. |
| `/cloop:cloop-plan` | Planning interview only → writes the plan. |
| `/cloop:cloop-execute` | Arm a durable loop from a plan. |
| `/cloop:cloop-status` | Active loops + morning report. |
| `/cloop:cloop-stop` | Stop a loop. |
| `/cloop:cloop-config` | User-wide defaults. |
| `/cloop:cloop-fix` | Diagnose & re-arm a loop that isn't firing. |
| `/cloop:cloop-iterate` | Internal — the per-interval cron payload. |

## How it works
Each interval the loop fires `/cloop:cloop-iterate <slug>`, which runs ONE unattended iteration:
orient → work → QA → ADR → single commit (isolated branch, no push/force) → update state →
stop-check. Iterations key off a fire counter, not the clock. `durable: true` + 7-day auto re-arm.
Pure Claude-tool scheduling → identical on Windows and macOS.

## Extending C Loop (authoring your own plan)
You don't need the interview. Copy `plan-template.md` to `.claude/cloop/plans/<slug>.md`, fill in
your own objective / done criteria / interval / commit style, then `/cloop:cloop-execute <slug>`.
Example: a docs-polish loop, `interval: 30m`, done criteria "every public function has a docstring".

## Layout it creates
```
.claude/cloop/plans/<slug>.md            # plan (committed)
.claude/cloop/state/<slug>.state.json    # state (gitignored)
.claude/cloop/adr/<slug>/NNNN-title.md    # one ADR per iteration (committed)
```
````

- [ ] **Step 2: Install + verify namespaced surface** — `claude plugin marketplace add ./` then
  `/plugin install cloop@cloop-marketplace` and reload. In `/help` (or the slash menu) confirm
  `/cloop:cloop`, `/cloop:cloop-plan`, `/cloop:cloop-execute`, `/cloop:cloop-status`,
  `/cloop:cloop-stop`, `/cloop:cloop-config`, `/cloop:cloop-fix` appear, and `/cloop:cloop-iterate`
  does NOT. Run `bash test/validate.sh` (Task 12) → `exit=0`.

- [ ] **Step 3: Headless invariant test (deterministic contracts).** In a throwaway fixture repo,
  hand-write `.claude/cloop/plans/smoke.md` (mode continuous, `interval: 2m`, `branch:
  cloop/smoke`, `max_iterations: 3`, objective "append one timestamped line to cloop-smoke.log").
  Initialize state via `/cloop:cloop-execute smoke`. Then run one iteration headlessly and assert
  invariants (not exact text):
  ```bash
  claude -p "/cloop:cloop-iterate smoke" --output-format json >/tmp/it.json 2>&1
  ```
  Assert: exactly one new commit on `cloop/smoke` OR `consecutive_no_progress` incremented; an ADR
  exists under `.claude/cloop/adr/smoke/`; `iteration` advanced by exactly 1; working tree clean;
  `git log` shows NO push/force; nothing committed outside the iteration's files; and the run
  rendered NO interactive prompt. Repeat once with an intentionally **ambiguous** objective and
  assert the iteration sets `status: paused` + PushNotifies and renders NO prompt (does not hang).

- [ ] **Step 4: E2E smoke (live cron).** With the `smoke` loop armed (whole-minute `interval: 2m`),
  confirm persistence:
  ```bash
  python3 -m json.tool .claude/scheduled_tasks.json   # tasks[] has an entry referencing cloop-iterate smoke
  ```
  Let an idle session sit ~5-6 minutes (allow for jitter up to half-interval). Confirm
  `cloop-smoke.log` gains lines, ADRs/commits accrue on `cloop/smoke`, and `state.fires`/`iteration`
  advance. `/cloop:cloop-status smoke` renders the report. `/cloop:cloop-stop smoke` removes the job
  (`CronList`) and sets `status: stopped`. If nothing fires after ~6 min, run `/cloop:cloop-fix
  smoke` and confirm the checklist finds the cause. Clean up:
  ```bash
  git branch -D cloop/smoke 2>/dev/null; rm -rf .claude/cloop/plans/smoke.md .claude/cloop/state/smoke.* .claude/cloop/adr/smoke cloop-smoke.log
  ```

- [ ] **Step 5: Commit** — `git add README.md && git commit -m "docs(cloop): add README; verified static gate, headless invariants, and live smoke"`

---

## Self-Review (completed during planning)

**Spec coverage:** §1 framing → Task 13 README + Task 5 interview; §2 facts → Task 3 engine; §3.2
layout + §3.4 state → Task 3 (+ gitignore via Read+Edit); §3.3 plan format → Task 2; §4 lifecycle +
non-interactivity + crash-atomicity → Task 3 + Task 4; §5 modes/rails (ceiling on fires, no-progress,
estimate-confirm, git/secret rails, lock, transactional re-arm) → Task 3 + Task 6; §6 ADR/commit →
Task 2 + Task 3; §7 all 8 commands + namespacing + config → Tasks 4-11; §8 fix checklist → Task 3 +
Task 11; §9 packaging/validate/cross-platform → Task 1 + Task 12 + Task 13; §11 testing tier →
Task 12 + Task 13; §12 open questions → exercised by Task 13 headless + smoke.

**Placeholder scan:** No TBD/TODO; full content provided per file (and Task 12 grep-gates it).

**Type/name consistency:** `slug`, `fires`, `iteration`, `cron_job_id`, `armed_at_sha`, `branch`,
`consecutive_no_progress`, `no_progress_limit`, `max_iterations`, `commit_style`/`custom_commit_template`,
`criteria_ref`, `rearm_after`, `session_marker`, `status` (running|paused|stopped|completed), the
namespaced `/cloop:cloop-iterate <slug>` payload, and `user-invocable: false` +
`disallowed-tools:[AskUserQuestion,…]` are used identically across engine, commands, templates,
state schema, and tests.
