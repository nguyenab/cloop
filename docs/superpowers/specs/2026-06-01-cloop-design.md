# C Loop — Design Spec

**Date:** 2026-06-01 (rev. 2026-06-02 after council review)
**Status:** Approved design, pre-implementation
**Author:** Abraham Nguyen (with Claude)

> **Rev note:** This revision incorporates a multi-agent council review (research → fact-check →
> design lenses → adversarial verification). Key corrections: command **namespacing**
> (`/cloop:cloop-iterate`), a hard **non-interactivity** invariant for unattended iterations,
> **cron-only** execution in v0.1 (dynamic engine deferred), **branch isolation** by default,
> **git/secret safety rails**, **atomic state + advisory lock**, **tool-level (not shell)**
> runtime, a **deterministic test tier**, and honest framing of what "runs while you sleep"
> actually requires.

---

## 1. Summary

**C Loop (`cloop`)** is a Claude Code **plugin** that wraps Claude Code's built-in `/loop`
(cron mode) to run **structured, self-documenting continuous loops**. You set it up once through
a short interview, it iterates on a fixed interval, and every iteration leaves behind an **ADR**
(Architecture Decision Record) and a **verbose commit** explaining *why*. You get a clean,
reviewable git trail instead of an opaque pile of changes.

C Loop is **not** an agent-orchestration framework. It is a thin, robust, *neat* wrapper around
the native `/loop` (cron) mechanism.

### What "runs while you're away" actually means (important, corrected)

Scheduled tasks **only fire while a Claude Code session is open and idle on a running machine.**
Closing the terminal or letting the session exit stops firing. `durable: true` does **not** make
the loop run with no session — it persists the job to `.claude/scheduled_tasks.json` so the job
is **restored when you reopen the same session** with `claude --resume`/`--continue` (within the
7-day window), without having to re-arm. So C Loop is for *"leave a session open/idle overnight,
or resume it in the morning"* — not *"close the laptop and it keeps coding."* The README and
interview state this plainly so expectations are correct.

### Design goals

1. **Robust** — survives session restarts (via `--resume`); diagnoses and self-heals the common
   "loop didn't fire" failures; never silently corrupts state or loses more than one iteration.
2. **Agnostic** — the engine is fixed; *what* the loop works on is fully pluggable via a per-loop
   plan file. Another dev points it at their own kind of work by **authoring a plan**, never by
   touching the engine.
3. **Cross-platform** — identical on Windows and macOS (primary: macOS). The runtime path depends
   on nothing but **git + Claude's own tools**; no shell-only idioms, no OS cron daemon, no
   runtime Node/Python.
4. **Reviewable** — small iterations, one commit each, one ADR each, on an isolated branch.

---

## 2. Background: how Claude Code's `/loop` actually works

Ground-truthed against the `CronCreate`/`CronList`/`CronDelete` tool schemas in this harness, the
public scheduled-tasks docs, and real `.claude/scheduled_tasks.json` files on disk. These are the
constraints the design is built around.

- **Engine (v0.1 is cron-only):** an interval → `CronCreate` (standard 5-field cron, **local
  timezone**). The self-paced/dynamic (`ScheduleWakeup`) mode exists in the harness but is
  **deferred** (see §10) — its durable/re-arm semantics are unverified, so v0.1 **requires an
  interval**.
- **`durable` flag is decisive:**
  - `durable: false` (default) → in-memory only; **dies when the session exits.**
  - `durable: true` → persisted to project-local **`.claude/scheduled_tasks.json`** (root
    `{ "tasks": [ ... ] }`), restored when the **same session** is resumed with
    `--resume`/`--continue` if unexpired. **Overnight loops require this.**
  - Note: a fresh conversation does **not** restore the job; you must resume the session that
    armed it (or accept a re-arm that mints a new job).
- **Idle-only firing, serialized** — a tick fires *between* turns, never mid-response, and **all
  scheduled fires in a session are serialized** (one at a time, never concurrent). If an iteration
  runs long, the next tick waits. **No catch-up** for missed fires.
- **7-day auto-expiry** on recurring jobs — fires one final time, then self-deletes. Expiry
  **cannot be extended in place**; you must `CronDelete` + `CronCreate` a new job to continue.
- **Jitter is significant** — recurring jobs can fire **up to 30 minutes after** the scheduled
  time (or up to **half the interval** for sub-hourly tasks); the offset is deterministic
  (derived from the task id). Loops must **never assume exact wall-clock timing**.
- **One-minute granularity** — seconds round up to the nearest minute; the practical interval
  floor is **1 minute**. Intervals that don't map to a clean cron step are rounded.
- **Prompt-cache ~5-min TTL** — waking past ~300s pays a full cache miss. As an **author
  heuristic** (not an Anthropic-published constant): intervals `< ~270s` keep the cache warm but
  burn tokens fastest; `>= ~20m` are economical for overnight runs (each iteration starts cold,
  amortizing the cache write). `5m` is the worst case. Avoid `:00`/`:30` minutes to dodge
  fleet-wide jitter pileups.
- **`CLAUDE_CODE_DISABLE_CRON=1`** disables all cron tools and `/loop` entirely.
- **Pure Claude-tool scheduling** — no shell, no system cron → identical on Windows and macOS.

**Design consequence:** iterations are keyed off a **persisted fire/iteration counter**, never a
clock. Jitter and missed fires become irrelevant — each fire runs "the next iteration," whenever
it lands.

---

## 3. Architecture

### 3.1 Two layers (the agnostic split)

| Layer | Changes? | Contents |
|---|---|---|
| **Engine** | Fixed | Read plan → run iteration lifecycle → write ADR → commit → update state → check stop condition. Lives in `skills/cloop/SKILL.md` + the `/cloop-iterate` command. |
| **Loop plan** | Per-loop, pluggable | Goals, done-criteria, interval, mode, branch, commit style. A Markdown file. |

A dev makes C Loop do something new by **authoring a plan** (`plans/<slug>.md`), never by editing
the engine. (`workflow_script` — a custom Workflow as the iteration body — is a **deferred**
v-next escape hatch; see §10.)

### 3.2 On-disk layout (in the target project, relative to repo root)

```
.claude/cloop/plans/<slug>.md              # the plan (committed)
.claude/cloop/state/<slug>.state.json      # runtime state (gitignored)
.claude/cloop/state/<slug>.lock            # advisory cross-session lock (gitignored)
.claude/cloop/adr/<slug>/NNNN-title.md      # one ADR per iteration (committed)
.claude/scheduled_tasks.json               # native durable cron store (managed by Claude Code)
```

- **Plans and ADRs are committed** (the reviewable trail). **State and lock are gitignored.**
- On first use, the engine ensures `.gitignore` contains `.claude/cloop/state/` (idempotent:
  read first, append only if absent, via Read+Edit/Write — never a shell redirect).

### 3.3 Plan file format (Markdown + YAML frontmatter)

```markdown
---
slug: improve-test-coverage
mode: continuous            # strict | continuous
interval: 20m               # REQUIRED in v0.1 (whole-minute floor; cron only)
engine: cron                # cron (v0.1). 'dynamic' is reserved / not yet implemented.
branch: cloop/improve-test-coverage   # default cloop/<slug>; 'current' to commit on the checked-out branch; or a named branch
commit_style: conventional-context     # conventional-context | brief-context | custom
custom_commit_template: null            # required only when commit_style: custom
max_iterations: 50          # hard ceiling on FIRES (always set); confirmed at arm time
no_progress_limit: 5        # consecutive no-real-progress iterations → auto-pause + notify
criteria_ref: null          # optional repo-relative path to PRD.json / user-stories.md
---

# Objective
<what this loop is trying to achieve and what "good" looks like>

# Done criteria
<bullet list, or "See criteria_ref">

# Iteration scope / guardrails
<what ONE iteration should accomplish; what NOT to touch; repo-specific constraints>
```

The engine parses **only** the frontmatter (a fixed key set; unknown keys are ignored with a
warning). `roles` is **not** a configurable field in v0.1 — planner/worker/qa/scribe are the
fixed lifecycle phases (see §4). `criteria_ref` is treated opaquely (read and handed to the QA
step). Both `criteria_ref` and `branch` are validated at arm time: repo-relative, no `..`, no
absolute paths, no symlink escape.

### 3.4 State file format (`<slug>.state.json`)

```json
{
  "slug": "improve-test-coverage",
  "status": "running",            // running | paused | stopped | completed
  "fires": 7,                     // incremented BEFORE work each fire (hard-ceiling counter)
  "iteration": 7,                 // committed-iteration count, derived from ADRs/git (see §4)
  "cron_job_id": "<id from CronCreate>",
  "engine": "cron",
  "interval": "20m",
  "branch": "cloop/improve-test-coverage",
  "armed_at_sha": "<HEAD sha at arm time>",   // for shell-free commit counting
  "durable": true,
  "created_at": "<ISO>",
  "expires_at": "<ISO = created_at + 7 days>",
  "rearm_after": "<ISO ≈ expires_at − 1 day>",  // proactive re-arm trigger
  "last_adr": "0007-add-parser-tests.md",
  "last_commit": "<sha>",
  "consecutive_no_progress": 0,
  "session_marker": "<session id/uuid that armed or last advanced the loop>"
}
```

Timestamps/SHAs are stamped by the engine when it writes the file. **Writes are atomic**
(write `<slug>.state.json.tmp`, then rename over the real file).

---

## 4. Iteration lifecycle

Each cron tick fires **`/cloop:cloop-iterate <slug>`** (namespaced — see §7), which runs **exactly
one iteration** as a single agent adopting inline roles. **It runs fully unattended.**

> **NON-INTERACTIVITY INVARIANT (load-bearing):** an iteration must **never** call
> `AskUserQuestion`, `EnterPlanMode`/`ExitPlanMode`, or any tool that waits for a human, and must
> never trigger a permission prompt. A cron fire runs in the **live interactive session between
> turns**; any human-waiting call freezes the *entire loop* until a person returns. The engine
> resolves all ambiguity from the plan + state + last ADR + `criteria_ref`. If it cannot proceed
> unambiguously, it sets `status: paused`, `PushNotification`s, and **stops** — it never asks.
> This is enforced structurally: `/cloop-iterate` declares `disallowed-tools: [AskUserQuestion,
> EnterPlanMode, ExitPlanMode]` and runs under a permission posture where its iteration tools are
> pre-approved (see §9).

**Crash-atomicity model:** the single commit is the atomic boundary, and **iteration identity is
derived from committed state, not the gitignored state file.** At the start of step 5 the engine
computes `NNNN = max(existing ADR number in adr/<slug>/) + 1` (cross-checked against `git log`),
so a crash between commit and state-write cannot double-number or lose an iteration. The `fires`
counter is bumped and persisted **before** any work (step 1) so a crash-looping iteration still
advances toward the hard ceiling.

Procedure (one fire = one iteration):

1. **Load & lock** — acquire the advisory lock (§5); read plan + state. Bump and persist
   `fires += 1`. If state is missing, stop and direct the user to `/cloop-fix <slug>`.
2. **Guard** — if `status != running`, stop. If `fires > max_iterations`, finalize (§5). If
   `consecutive_no_progress >= no_progress_limit`, set `paused`, notify, stop. Verify on the
   plan's `branch` (else checkout; if that would require a prompt, pause+notify).
3. **Expiry check** — if now ≥ `rearm_after`, **re-arm transactionally** (§5) before working.
4. **Orient** *(Planner)* — scope this iteration to **one coherent change** from plan + state +
   last ADR + `git log`.
5. **Work** *(Worker)* — implement it.
6. **Check** *(QA)* — verify against done criteria / `criteria_ref`; record the result in the ADR.
7. **Document** *(Scribe)* — compute `NNNN`, write `adr/<slug>/NNNN-<title>.md`.
8. **Commit** — stage **only** this iteration's own files + the ADR by explicit path (never
   `git add -A`/`.`); run the secret guard (§5); make **exactly one local commit** using
   `commit_style`. End every iteration with a **clean working tree**: if there was genuinely
   nothing to change, make no commit and `git restore`/drop any partial edits.
9. **Update state** — set `iteration` (= derived NNNN), `last_adr`, `last_commit`. Set
   `consecutive_no_progress = 0` **iff** a real commit was made AND QA passed; otherwise
   increment it (single owner — only step 9 mutates this counter). Atomic write; release lock.
10. **Stop check** — see §5.

There is **no Innovator phase** in v0.1 (deferred, §10).

---

## 5. Modes, stop conditions, and safety rails

### Modes
- **Strict** — bounded work. Stops (`CronDelete` + `status: completed`) when done-criteria are met
  **or** `fires >= max_iterations`.
- **Continuous** — improves until `/cloop-stop`. Still bounded by `max_iterations` and the
  no-progress guard.

### Safety rails (always on)
- **Hard ceiling on fires** — `max_iterations` counts *fires* (bumped before work), so a
  crash-looping iteration cannot run unbounded.
- **No-progress detector** — `no_progress_limit` consecutive iterations with no real progress
  (no commit, or a committed iteration whose QA failed) → `paused` + `PushNotification`.
- **Estimate-and-confirm (cost)** — at arm time the engine shows a one-line estimate
  (`~max_iterations fires × interval → est. duration`; note token cost scales with iteration
  count) and requires confirmation **before** arming. No live token-budget rail (unmeasurable
  from a cron/markdown plugin — it would be false assurance); the ceiling + no-progress guard are
  the real bounds. Default `max_iterations` is conservative (50).
- **Git safety rail** — during an iteration the loop **NEVER** pushes, `--force`/`--force-with-lease`,
  `rebase`, `reset --hard`, or `amend`; makes exactly one local commit; stages only its own files
  by explicit path. Runs on the plan's isolated `branch` (default `cloop/<slug>`).
- **Secret guard** — before committing, scan staged paths for likely secrets (`.env`, key/cred
  filenames, obvious token patterns); if matched, **unstage and skip** rather than commit, and
  note it in the ADR.
- **Advisory cross-session lock** — step 1 writes `<slug>.lock` with the session marker + ISO
  timestamp; if a *fresh* lock from another session exists, the iteration **skips** (logs/notes)
  to prevent two resumed sessions from double-committing. Stale locks (older than a few intervals)
  are reclaimed.
- **7-day expiry → transactional auto re-arm + notify.** Triggered proactively at `rearm_after`
  (≈ 1 day before expiry, widened to survive a missed fire): (a) `CronCreate` a new durable
  recurring job and capture its id; (b) verify via `CronList` it registered — if not, keep the old
  `cron_job_id`, `PushNotification` the failure, and stop; (c) `CronDelete` the old job; (d) update
  `cron_job_id`/`created_at`/`expires_at`/`rearm_after`. Each re-arm extends the loop another
  7 days **only while a session stays open/idle (or is resumed within 7 days)** to fire it — it is
  not truly unattended across a closed session.

---

## 6. ADR and commit specs

### ADR (`adr/<slug>/NNNN-<title>.md`)

`NNNN` = the iteration number this ADR documents = (committed-iteration count) + 1, **zero-padded
to 4**. `<title>` = kebab-case of the ADR's one-line subject, `[a-z0-9-]`, max ~6 words.

```markdown
---
id: NNNN
iteration: N
date: <ISO>
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

The ADR is committed **in the same commit** as the change, so it cannot contain its own commit
SHA. The trail is recovered deterministically instead: the ADR and its commit share the iteration
number, so `git log --grep "iteration N"` (or the `ADR:` pointer in the commit) links them. The
ADR therefore has **no `commit:` field**.

### Commit message styles (configurable via `commit_style`)

Placeholder substitution is performed by the **Scribe agent** (not an engine "machine"). The
`ADR:` pointer is always the full repo-root-relative path so `cat <path>` resolves from the root.
Trailers use ASCII separators (no non-ASCII middle dot).

- **`conventional-context`** (default):
  ```
  type(scope): concise summary

  Why: <1-3 sentence rationale from the ADR Context/Decision>
  ADR: .claude/cloop/adr/<slug>/NNNN-title.md
  Loop: <slug> | iteration N
  ```
- **`brief-context`** — non-conventional subject + the same `Why:`/`ADR:`/`Loop:` trailer.
- **`custom`** — the plan's `custom_commit_template`. It MUST include the ADR path and iteration
  so the trail stays intact.

---

## 7. Commands

Plugin commands are **namespaced by plugin name**, so they surface and are invoked as
`/cloop:<command>` (e.g. `/cloop:cloop-execute`). The `name:` frontmatter is cosmetic — the
installed command name derives from the **filename + plugin namespace**.

| Command | Behavior |
|---|---|
| `/cloop:cloop` | Full interview → writes a plan → offers to start (with the cost estimate + confirm). |
| `/cloop:cloop-plan` | Planning interview only → writes `plans/<slug>.md`. No execution. |
| `/cloop:cloop-execute` | `AskUserQuestion` list of existing plans → estimate + confirm → arms a **durable** cron loop, creates/checks out `branch`, records `cron_job_id`/`armed_at_sha`. None? → `/cloop:cloop-plan`. |
| `/cloop:cloop-iterate <slug>` | **Internal**, `user-invocable: false`. Runs exactly one unattended iteration (the cron payload). |
| `/cloop:cloop-config` | Read/write user-wide defaults at `~/.claude/cloop/config.json` (hand-editable; pinned schema + precedence below). |
| `/cloop:cloop-status` | Active loops + morning report; cross-checks `CronList`/`scheduled_tasks.json`; for any detected problem prints the **exact remediation command**. |
| `/cloop:cloop-stop` | Stop a loop (`CronDelete` + `status: stopped`). |
| `/cloop:cloop-fix` | Diagnose & re-arm a stalled loop (§8). |

All commands are thin delegators that **Read** `${CLAUDE_PLUGIN_ROOT}/skills/cloop/SKILL.md` and
follow the relevant section. (The `@`-include / Read inlines the engine text; it does **not**
invoke a separate skill — so each command's own `allowed-tools` is the load-bearing permission
source.) `commands/*.md` is the legacy-but-supported layout; `skills/<name>/SKILL.md` is the
currently recommended shape (either works; v0.1 uses `commands/` for thin explicit entry points).

### Config schema + precedence (`~/.claude/cloop/config.json`)

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

Precedence: **explicit interview answer > config default > built-in default.** The interview
states which defaults it applied.

### Interview (`/cloop`, `/cloop-plan`)

Uses `AskUserQuestion` (interactive — these commands are run by a present user, never by cron).
Skips anything config already sets, naming what it applied.

1. **Context** — heuristic: if `/cloop` was given a goal hint, or the conversation already
   contains a concrete goal the loop could continue, **offer** "continue existing context"; else
   default to fresh (don't ask a confusing question in an empty session).
2. *(fresh)* Goal / type — suggests: code enhancement, tests, docs, refactor, feature planning…
3. Precise criteria (PRD / user stories)? Yes → paste/drop → saved + `criteria_ref`. No → 1-2
   targeted questions.
4. Mode, interval (whole-minute; steer off `5m`/`:00`/`:30` with the plain-language cost
   trade-off), branch isolation (default on), commit style.
5. **Confirm the slug** — propose the generated kebab slug and let the user accept/rename (the
   slug is their handle to every command).

Then writes the plan and (for `/cloop`) shows the estimate and offers to execute.

---

## 8. `/cloop-fix` — diagnostics (the "didn't fire" cure)

Runs in order, then repairs:

1. **`CLAUDE_CODE_DISABLE_CRON`** set? → report; cron is globally disabled.
2. **Session parked on a prompt?** → if the session is frozen on an `AskUserQuestion`/permission
   prompt, the loop can't fire because the session is never idle → tell the user to answer/dismiss
   it; flag any plan/engine path that could have asked (should not happen post-fix).
3. **Job present?** — read `.claude/scheduled_tasks.json` + `CronList`; is `cron_job_id` present?
4. **Duplicate jobs?** — more than one job for this slug → `CronDelete` extras, keep one.
5. **Missing but running** → in-memory death, or a **fresh conversation instead of `--resume`** of
   the arming session. Distinguish: advise resuming the original session, or re-arm durably
   (transactional, §5) and update `cron_job_id`.
6. **Present but `fires` not advancing** → session rarely idle (long iterations / busy session) →
   advise shrinking scope; offer a longer interval.
7. **Near expiry** → re-arm transactionally (§5).
8. **State/lock corrupt or stale** → rebuild state from highest ADR + `git log` + plan; clear a
   stale lock.
9. **Stopped legitimately?** → criteria met / ceiling reached → report; offer to raise ceiling or
   switch to continuous.

Ends by printing what it found and changed.

---

## 9. Packaging, deployment, cross-platform

### Layout
```
cloop/
  .claude-plugin/plugin.json
  .claude-plugin/marketplace.json     # self-marketplace (no $schema line)
  commands/
    cloop.md  cloop-plan.md  cloop-execute.md  cloop-iterate.md
    cloop-config.md  cloop-status.md  cloop-stop.md  cloop-fix.md
  skills/cloop/SKILL.md                # the engine
  skills/cloop/references/
    adr-template.md  commit-templates.md  interview.md  plan-template.md
  test/                                # deterministic test tier (see §below)
  README.md
```

### Validation & deploy
- **Validate with `claude plugin validate --strict`** (exit-code gate), not just JSON syntax.
  Because a co-located `marketplace.json` makes the validator skip plugin/command/skill checks,
  run **two separate** validates: (a) `claude plugin validate ./.claude-plugin/marketplace.json
  --strict` for the marketplace; (b) validate the plugin (commands + skills) against a plugin root
  that the validator does not treat as marketplace-only.
- **Install (local dev):** `claude plugin marketplace add ./` then
  `/plugin install cloop@cloop-marketplace` (or add `cloop@cloop-marketplace` to `enabledPlugins`).
- **Install (remote):** `claude plugin marketplace add <owner>/<repo>` then
  `/plugin install cloop@cloop-marketplace`.
- After install, commands surface as `/cloop:cloop`, `/cloop:cloop-plan`, … and
  `/cloop:cloop-iterate` is hidden (`user-invocable: false`).

### Cross-platform (the real invariant)
The **runtime path depends only on git + Claude's own tools** (Read/Write/Edit/Glob, and `Bash`
*or* PowerShell for git). The engine prescribes **tool-level operations, not shell idioms**:
enumerate plans via Glob/Read, edit `.gitignore` via Read+Edit, count commits since arming via a
SHA range (`git log --oneline <armed_at_sha>..HEAD`) rather than `--since=<date>` (timezone/quoting
fragile). **No runtime Node or Python** (Claude Code is a native binary; Node is only an install
prereq). Build/test/verification *scripts* in the plan that use bash (`python3`, `rm -rf`, etc.)
are explicitly scoped to a POSIX dev environment (macOS, or Git Bash/WSL on Windows); they are not
part of the runtime.

---

## 10. Out of scope (YAGNI / deferred)

- **Dynamic / self-paced engine** (`ScheduleWakeup`) — deferred until its durable + re-arm
  semantics are verified and a dynamic-path test exists. `engine` enum keeps a reserved `dynamic`
  slot for forward-compat; v0.1 requires an `interval`.
- **Innovator role** and the per-iteration research/critique council — cut (conflicts with the
  anti-orchestration framing; reintroduce only with a cost cap).
- **`workflow_script`** (arbitrary Workflow as the iteration body) — deferred until it has a
  defined engine↔script contract (inputs, result shape, which lifecycle phases it replaces) and
  path/safety validation. v0.1 agnosticism is delivered via **hand-authored plans**.
- No remote/server execution; relies on a local resumable session.
- No multi-repo central state (project-local only).
- No GUI/email; the "morning report" is `/cloop-status` output in-session.

---

## 11. Testing strategy (how to unit-test a prose plugin and control results)

The plugin is mostly prose, so test in **layers**, shrinking the nondeterministic surface:

1. **Static tier (fully deterministic, CI gate).**
   - `claude plugin validate --strict` (two separate paths per §9).
   - Frontmatter lint: every command/skill has valid YAML + required keys; `/cloop-iterate` has
     `user-invocable: false` and `disallowed-tools: [AskUserQuestion, EnterPlanMode, ExitPlanMode]`.
   - `@${CLAUDE_PLUGIN_ROOT}/<path>` resolver test: extract every reference and assert the file
     exists.
   - JSON-schema validation of the state file and config file against committed schemas.
   - Grep gates: no `TODO|TBD|FIXME`; state-key consistency (the canonical key set appears
     identically across engine/templates).
2. **Golden tests** — fixed inputs → assert the exact ADR body and commit message produced by the
   templates (text fixtures; deterministic).
3. **Headless invariant tests** — `claude -p "/cloop:cloop-iterate smoke"` in a throwaway fixture
   repo; assert **contracts, not exact output**: after one iteration → exactly one new commit OR
   `consecutive_no_progress` incremented; an ADR exists; `iteration` advanced by exactly 1; clean
   working tree; **no push, no force, nothing committed outside the iteration's files**; and **no
   interactive prompt rendered** (including an intentionally-ambiguous-scope run that must
   pause+notify, not ask). Run a few times; invariants must hold every run.
4. **E2E smoke** (top of pyramid) — arm a real durable cron loop at a whole-minute interval, let
   an idle session fire it, assert files/commits/ADRs accrue and `/cloop-stop` removes the job.

"Control results" = (a) shrink nondeterminism by keeping the must-be-exact logic (interval→cron
rule, ADR numbering/title, commit templating, state transitions, expiry math) **specified
precisely in SKILL.md and covered by golden/static tests**; (b) assert **invariants/contracts**
for the LLM-driven parts; (c) pin everything else with schema + grep gates. Deterministic logic is
**not** extracted into a runtime helper (no runtime Node/Python — §9); it is specified as an
explicit rule and verified by golden tests.

---

## 12. Open questions / to validate during implementation

1. Confirm `/cloop:cloop-iterate <slug>` fires reliably as a **namespaced** cron payload, and
   survives `--resume`. As a hardening fallback, the cron prompt is **self-contained natural
   language** that names the slug *and* instructs reading the engine skill by path, so the loop
   does not depend solely on slash-command expansion.
2. Confirm `durable: true` jobs in `.claude/scheduled_tasks.json` keep firing after `--resume`
   without manual re-arm.
3. Confirm the exact `claude plugin validate` invocation that covers commands+skills given a
   co-located `marketplace.json` (two-path workaround in §9).
