# cloop loop-engineering hardening

Date: 2026-07-02. Author: Fable 5, from a Sonnet 5 research sweep over 2024–2026 loop-engineering
literature (Reflexion, SWE-bench lineage, Anthropic long-running-harness posts, AgentQuest, RAMP,
Engram, goal-drift studies). Implemented by Opus 4.8 agents.

## Why

cloop's shape — a fresh context per timer fire, file-based state, one commit per iteration, a
separate QA role — is exactly what the 2025–2026 literature converged on for unattended loops
(Engram arXiv:2603.21321; Anthropic "Effective harnesses for long-running agents"). Keep the shape.
Five gaps remain, each backed by established findings:

1. **QA has no ground truth.** LLMs cannot reliably self-correct without an external signal
   (Huang arXiv:2310.01798; CRITIC). A QA that only re-reads the Worker's output degrades quality.
2. **"Done" is not machine-checkable.** The proven pattern is a criteria list with per-item
   pass/fail status, updated each iteration (SWE-bench lineage; Anthropic feature-list pattern).
3. **Memory between iterations is too thin.** Only the last ADR is read. Reflexion
   (arXiv:2303.11366) and Engram show failure reasons must carry forward, and the self-correction
   illusion result (arXiv:2606.05976) shows feedback lands better framed as external.
4. **No circuit breaker.** Repeated QA fails, empty diffs, and plateaus are the documented silent
   killers of unattended loops (AgentQuest arXiv:2404.06411; RAMP arXiv:2605.27492).
5. **Goal drift is unguarded.** Loops inherit drift from their own prior state writes
   (arXiv:2603.03258); the mitigation is an immutable goal re-read verbatim, plus a QA that checks
   spirit-not-letter so criteria can't be gamed (DeepMind specification-gaming catalog).

Constraint that overrides everything: **cloop stays lean.** No embeddings, no vector stores, no
watchdog processes, no new roles, no orchestration framework. Every mechanism below is plain
instructions, one small committed file, or a counter in state.json. Everything is
backward-compatible: an existing plan with none of the new fields behaves exactly as today.

## Changes

### 1. Ground-truth check command (`check`)

- `references/plan-template.md`: add optional frontmatter field `check` — a shell command that
  must exit 0 for an iteration to pass QA (e.g. `check: npm test`). Default null. Add one tip
  line: a loop without a check command is only as reliable as LLM judgment; give it one when the
  project has tests.
- `SKILL.md` **Plan frontmatter** section: document `check` in the field list.
- `SKILL.md` state example: add `"check": null` (carried from the plan so /cloop-status and
  guardrails can see it without re-parsing the plan).

### 2. Criteria ledger

A small committed checklist that makes progress and completion machine-readable.

- New file convention: `.claude/cloop/criteria/<slug>.md` (committed, like plans).
- New reference: `references/criteria-template.md` with this exact shape:

  ```markdown
  # Criteria: <slug>

  One line per criterion. The loop may only flip `[ ]` to `[x]` (or back, with the flip noted in
  that iteration's ADR). It never rewrites, reorders, or deletes a criterion. New requirements
  discovered mid-loop go under Discovered, never into the original list.

  - [ ] <criterion in plain language> — verify: <the concrete check: a command, a file, a behavior>

  ## Discovered
  <criteria surfaced during the loop, same format; starts empty>
  ```

  Every criterion line must carry a `— verify:` clause naming a concrete check. Aspirational
  criteria without a verification method produce inconsistent QA verdicts (Anthropic "Building
  Effective Agents").
- Written at setup: `/cloop` and `/cloop-plan` (via `references/interview.md` question 3) distill
  the goal — and `criteria_ref` if given — into the ledger. If a loop starts without one
  (`/cloop-execute` on a hand-written plan), the first iteration's Planner writes it before doing
  anything else, from the goal and `criteria_ref`.
- `SKILL.md` **Files** section: add the path. **Summary** and strict-mode completion: strict mode
  is done when every box (original and Discovered) is checked AND the `check` command (if set)
  exits 0 — not when the model feels done.
- If the ledger is absent and the plan predates this change, behave as today (goal-prose judgment).

### 3. Tiered QA with external grounding

Rewrite `SKILL.md` iteration step 4 (Check) as two tiers:

- **Tier 1 — deterministic, always first, no LLM judgment spent:** run the plan's `check` command
  if set (must exit 0); confirm the iteration produced a non-empty diff scoped to the planned
  step. Any Tier-1 failure is `qa: fail` immediately.
- **Tier 2 — judgment, only after Tier 1 passes:** verify the iteration's `Done when` line (see
  change 4), flip any criteria-ledger boxes this iteration satisfied, and check spirit over
  letter: the implementation must achieve the criterion's intent, and the loop never deletes,
  weakens, or edits tests or criteria to make a check pass.

Order rationale in one line in the doc: cheap checks that can reject do so before tokens are spent
on judgment (arXiv:2408.03314). Update the QA bullet in `references/roles.md` to match.

### 4. Planner writes "Done when" per step

- `SKILL.md` iteration step 2: the Planner's scoped step must end with one explicit line —
  `Done when: <a check QA can perform this iteration>` — before the Worker starts. One step = one
  verifiable sub-goal (plan-validate-execute; Chip Huyen 2025). Recorded in the ADR's Decision.
- `references/roles.md` Planner bullet: add this duty.

### 5. Handoff memory (Reflexion-grounded)

- `references/adr-template.md`: add a `## Handoff` section between Consequences and Links —
  at most 5 lines: outcome; if QA failed, the grounded reason (the failing check and its output,
  not "insufficient"); what the next iteration should avoid; what likely comes next.
- `SKILL.md` iteration step 1: read the last **three** ADRs (was: the last ADR), attending to
  their Handoff sections. Handoff notes are treated as external feedback from the prior QA, not
  the model's own prior reasoning.
- On a QA fail, the next iteration retries **fresh with a narrower scope** — it never patches the
  rejected attempt in place (fresh parallel generation beats sequential self-revision,
  arXiv:2502.12215). One sentence in the QA-fail paragraph of `SKILL.md`.
- `references/roles.md` Scribe bullet: add the Handoff duty.

### 6. Guardrails: circuit breaker, stall detection, re-anchor

New reference `references/guardrails.md`, read as step 0.5 of every iteration (after the quota
gate, before planning). Contents:

- **State counters** (added to the state example in `SKILL.md` and to
  `test/schemas/state.schema.json`):
  - `consecutive_qa_failures` — integer, reset to 0 on any `qa: pass`.
  - `last_progress_iteration` — integer; the last iteration that flipped a criteria box, or (when
    no ledger exists) landed a non-trivial commit.
  - `stalled_reason` — string or null.
- **Breaker rules**, checked before planning:
  - `consecutive_qa_failures >= 3` → stall landing.
  - Continuous mode: `iteration - last_progress_iteration >= 5` → stall landing.
- **Stall landing** (mirrors the quota wrap-up landing): leave the tree coherent; write a
  diagnosis ADR — what kept failing, the grounded evidence from the last Handoffs, one or two
  hypotheses, and a suggested narrower scope; set `status: stalled` and `stalled_reason`;
  `CronDelete` the timer; `PushNotification` with why and what to do next. A stalled loop burns
  no further iterations (failed self-refinement, arXiv:2508.13143; ~50% of loop budget is wasted
  past this point).
- **Re-anchor**: every 5th iteration (`iteration % 5 == 0`), the Planner re-reads the plan's Goal
  and the criteria ledger verbatim and records one line in the ADR Context: whether the recent
  trajectory still serves the goal, and anything that drifted. Deterministic counter, no
  similarity scoring.
- **Immutability**: the plan's Goal/Scope prose and the criteria ledger's criterion text are
  human-owned; the loop never edits them (only checkbox flips and Discovered appends). If an
  iteration believes a criterion is wrong, it says so in the ADR and keeps the criterion intact.

`SKILL.md` status line gains the new value: running, stopped, completed, paused-quota, or
**stalled**.

### 7. Command surface

- `commands/cloop-status.md`: show criteria progress (`N of M criteria met`) when a ledger exists;
  for a `stalled` loop, point at the diagnosis ADR and `/cloop:cloop-fix`.
- `commands/cloop-fix.md`: add the stalled case — read the diagnosis ADR, summarize it for the
  user, and offer to restart with the suggested narrower scope (resetting
  `consecutive_qa_failures` and `stalled_reason`, setting `last_progress_iteration` to the current
  `iteration` so a plateau-stalled loop gets a fresh window, re-arming the timer from the saved
  `cron`).
- `references/interview.md`: question 3 (Criteria) now ends by writing the criteria ledger with a
  `— verify:` clause per criterion; add a question 3b asking for a `check` command (suggest the
  project's test command if one is visible; null is fine).
- `commands/cloop.md`, `commands/cloop-plan.md`: mention that setup writes
  `.claude/cloop/criteria/<slug>.md` alongside the plan.
- `commands/cloop-iterate.md`: unchanged except the sentence pointing at SKILL.md also names the
  step-0.5 guardrail gate.

### 8. Tests, schemas, docs, version

- `test/schemas/state.schema.json`: add `check`, `consecutive_qa_failures`,
  `last_progress_iteration`, `stalled_reason`; add `stalled` to the status enum.
- `test/validate.sh`:
  - extend the state-key consistency loop (check 7) with the three new counter keys (`check` too).
  - new check: `references/adr-template.md` contains `## Handoff`.
  - new check: `references/plan-template.md` contains `check:`.
  - new check: `references/criteria-template.md` exists, contains `- [ ]` and `verify:`.
  - new check: `references/guardrails.md` exists, contains `consecutive_qa_failures` and
    `stalled`.
  - new check: SKILL.md contains `stalled` in the status line and `Done when` in the iteration
    steps.
- `README.md`: one new short section, "How it stays on track", in the existing plain voice: the
  check command, the criteria ledger, handoff notes, and the stall breaker — four sentences to a
  short paragraph each at most. Update the "What one iteration does" section to mention the check
  command and criteria ledger in passing. No research citations in the README.
- `.claude-plugin/plugin.json`: bump version 0.3.0 → 0.4.0 (installs don't update otherwise).
  If `.claude-plugin/marketplace.json` carries a version for the plugin, bump it to match.

## Out of scope (deliberately)

Embedding/cosine drift detection, vector retrieval over ADRs, a Reflector role, LLM-scored
importance tagging, MemGPT-style paging, task-budget API features, watchdog daemons, and any
change that makes cloop an orchestration framework. The lean heuristics above capture most of the
value of each; revisit only if the simple counters prove insufficient in use.

## Amendments (post-verification, same day)

A two-agent end-to-end exercise (a full loop lifecycle run literally from the docs in a scratch
repo) surfaced ambiguities that could silently disable the breakers. Clarified:

- A failed iteration still completes step 7 (increment `iteration`, set `last_adr`, update
  counters) — otherwise `consecutive_qa_failures` never bumps and neither breaker can trip.
- State's `iteration` counts completed iterations; guardrail checks read it at step 0.5, so the
  fire in progress is `iteration + 1`. Re-anchor fires when that is a positive multiple of 5
  (fires 5, 10, …, never the first). `last_progress_iteration` is written at step 7 as the
  just-incremented value.
- A landing (quota wrap-up or stall diagnosis) commits its ADR, sets `last_adr` to it, and leaves
  `iteration` unchanged; its ADR uses `qa: n/a` and carries `iteration` as it stands in state.
- `plan-template.md` explains the ledger-vs-`criteria_ref` distinction; `cloop-iterate.md` says
  "recent ADRs"; the README file map lists the criteria ledger.

## Acceptance

- `test/validate.sh` passes, including all new checks.
- Every `${CLAUDE_PLUGIN_ROOT}/...` reference resolves (validate check 5 covers this).
- A plan written before this change (no `check`, no ledger) still runs: every new mechanism
  degrades to today's behavior when its file or field is absent.
- Prose stays in cloop's existing voice: plain, no fluff, no marketing.
