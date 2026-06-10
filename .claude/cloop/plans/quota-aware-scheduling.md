---
slug: quota-aware-scheduling
mode: continuous
interval: 18m
max_iterations: 40
roles: [planner, worker, qa, scribe]
commit_style: conventional-context
criteria_ref: null
---

# Goal

Make cloop quota-aware so it spends available Claude capacity well and never keeps firing into a
wall. Use `ccs cliproxy quota --provider claude` as the capacity signal, woven into cloop's existing
skill + commands (no daemon — cloop only runs while a session is open and idle).

Three behaviors, built incrementally:

1. **Read capacity.** Parse `ccs cliproxy quota --provider claude` (human-readable, no JSON) into the
   default account's `5h%`, `weekly%`, weekly-Sonnet%, and the reset windows (`Resets in Xh`).
   Tolerate the text/progress-bar format and the `[X]`/`[!]`/`[ ]` account markers.

2. **Skip-when-low (preemptive backoff).** At the top of each iteration, read quota first (a cheap
   bash call that does not meaningfully spend Claude tokens). If the **default account's 5h usage
   > 90%** (safety threshold), skip the iteration cheaply: no token-heavy work, no commit — record a
   one-line skip note and exit. Fixed 18m interval otherwise.

3. **Hard-stop on exhaustion / 429 → hybrid heartbeat resume.** When the default account is fully
   exhausted, or an iteration catches a real **429** (which, because the proxy already rotates the 2
   Claude accounts, means *all* accounts are out — the true ceiling):
   - Read the reset window from quota → compute `resume_at = now + Resets-in (+ small buffer)`.
   - `CronDelete` the fast 18m timer (the literal "stop scheduling crons" — stop burning cadence).
   - `CronCreate` a **slow check-only heartbeat** timer near `resume_at` (e.g. a ~20m check whose
     only job is to read quota).
   - Write state `status: paused-quota`, `resume_at`, `paused_reason`.
   - Each slow heartbeat fire: if quota has capacity again → **re-arm the fast 18m timer**,
     `CronDelete` the slow heartbeat, set `status: running`; if still out → keep checking.
   - Notify the user (PushNotification) on pause and on resume.

# Council amendments (2026-06-10, fable-evolution iteration 2)

A 5-agent council reviewed this plan against live data (5h 56%, weekly 90%, Sonnet-weekly 97%)
and Fable 5's launch facts (2x Opus pricing, ~30% fatter tokenization). Four amendments override
the matching parts of the behaviors above:

1. **Gate on the binding constraint, not 5h alone.** Skip when `max(five_h_pct, weekly_pct)`
   crosses the threshold, and compute `resume_at` from whichever window is binding. A 5h-only
   gate sails straight into a weekly wall (tonight's exact shape).
2. **Horizon-honest pause.** Only arm the slow heartbeat when the binding reset is within a
   session-plausible horizon (~6h, i.e. the 5h wall). For a weekly wall (resets in days), do not
   arm a timer that cannot survive the session: set `paused-quota`, notify with the exact reset
   time, and have `cloop-fix`/`cloop-status` offer the re-arm on the next session.
3. **Wrap-up landing, not silent skip.** When the gate trips, spend one deliberately tiny
   iteration landing the loop: commit or revert in-flight work, write a handoff ADR (what
   shipped, what's half-done, resume_at), notify, then pause. Exhaustion is a scheduled landing,
   not an error to suppress.
4. **Quota-delta accounting.** Snapshot the parsed quota at iteration start and end, store the
   delta (`last_quota`, `last_iteration_cost`), and surface cost-per-iteration and
   "≈N iterations of headroom left" in `cloop-status`. This makes the threshold evidence-based
   instead of a magic 90%.

# Scope and notes

- **Where the logic lives.** cloop is markdown skill-instructions, not a runtime. Add a small
  reference doc (e.g. `skills/cloop-engine/references/quota.md`) describing the quota check, the
  parse rules, thresholds, and the hybrid-heartbeat state machine. Wire it into:
  - `skills/cloop-engine/SKILL.md` — a "Quota awareness" section + hooks in **What one iteration
    does** (step 0: check quota → skip/pause) and **Starting a loop** (check quota before first arm).
  - `commands/cloop-iterate.md` — note the top-of-fire quota gate (allowed-tools already include Bash,
    CronDelete, CronList, CronCreate? — verify; add CronCreate if missing for re-arm).
  - `commands/cloop-status.md` and `skills/cloop-engine/SKILL.md` State block — surface
    `status: paused-quota`, `resume_at`, last skip.
  - `commands/cloop-fix.md` — recognize `paused-quota` as a non-broken state and resume correctly.
- **A tiny parser helper is OK** (e.g. a shell/awk snippet or `test/`-covered script) since the
  output is fragile text. Keep it lean — cloop stays a thin wrapper, never an orchestration
  framework (see memory: cloop stays lean). Prefer a documented bash one-liner over a new dependency.
- **State additions** (keep small, atomic write): `status` gains `paused-quota`; add `resume_at`,
  `paused_reason`, `last_quota` (the parsed snapshot), `slow_cron_job_id`.
- **Threshold is a knob.** Default 5h skip at 90%; make it a documented constant so it's tunable,
  and consider surfacing it in `/cloop:cloop-config` later (not required this loop).
- **Honesty about limits.** Document plainly: neither the heartbeat nor the re-arm fires while the
  session is closed; the hybrid model just gives many chances to catch the reset instead of one.
- **Account signal.** Govern on the **default** account's 5h/weekly for the preemptive skip; treat
  any 429 as the hard-stop. Do not try to read per-request routing.
- **Out of scope (note for later):** adaptive interval from used%+reset (drifts on progress-bar
  data); per-account rotation control; weekly-cap-primary mode. Leave hooks/notes, don't build.

# Acceptance (what "good" looks like, since no criteria_ref)

- A reproducible parse of `ccs cliproxy quota --provider claude` → default-account 5h%, weekly%,
  reset window, with a test fixture of the current text format.
- An iteration with default 5h >90% skips without a token-heavy run or a commit, leaving a skip note.
- On simulated exhaustion/429: fast timer is deleted, a slow heartbeat exists, state is
  `paused-quota` with a sane `resume_at`; on simulated recovery the fast timer is re-armed and the
  heartbeat removed.
- Docs (README + SKILL) explain the behavior and the session-open caveat honestly.
- Every iteration leaves one ADR and one commit; cloop stays lean.
