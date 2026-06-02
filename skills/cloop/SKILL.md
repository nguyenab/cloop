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
`status` is one of running|paused|stopped|completed. Stamp times/SHAs when writing.

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
