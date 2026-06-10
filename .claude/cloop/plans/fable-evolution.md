---
slug: fable-evolution
mode: continuous
interval: 60m
max_iterations: 8
roles: [planner, worker, qa, scribe, innovator]
commit_style: conventional-context
criteria_ref: .claude/cloop/plans/quota-aware-scheduling.md
---

# Goal

Evolve cloop into something of extreme value while Fable 5 access is available — overnight, hourly,
until 8 AM (2026-06-10). Three threads, roughly in priority order:

1. **Quota-aware scheduling (the core build).** Execute the existing
   `quota-aware-scheduling` plan: parse `ccs cliproxy quota --provider claude` for the default
   account's 5h%/weekly% and reset windows; skip iterations cheaply when 5h usage > 90%; on
   exhaustion or a real 429, hard-stop the fast timer and arm a slow heartbeat near the computed
   reset time, resuming automatically. Its frontmatter (18m cadence) does not apply here — this
   loop's cadence governs — but its Goal, Scope, and Acceptance sections are the spec and the
   QA bar for this thread.

2. **Accelerate and sharpen the harness.** Improve the /loop + cron machinery cloop wraps:
   tighter restart/fix behavior, better batched-fire handling, clearer status output, lower
   token cost per iteration. Small, real improvements over grand redesigns.

3. **Research: Fable 5 in the wild (2026).** Fable 5 released 2026-06-09 (today). Use the
   Innovator (web research + council) early in the loop to find how people are using it —
   capabilities, agentic patterns, long-horizon behaviors — and distill anything that should
   change cloop's design into concrete iterations. Capture findings in an ADR even if no code
   changes result; a "what Fable 5 changes for cloop" reference doc is a valid deliverable.

# Scope and notes

- cloop stays lean: a thin wrapper around /loop and cron, markdown-first, no daemon, no
  orchestration framework. Prefer documented bash one-liners over new dependencies.
- The quota plan's "Out of scope" items stay out of scope unless the Innovator council makes a
  compelling, lean case otherwise.
- Run the Innovator council in iteration 1 or 2 (front-load research while the night is young),
  then again at most once more; remaining iterations build.
- Bump plugin.json version if a release-worthy milestone lands (see memory: bump version each
  release).
- Time-bounded: the timer dies at 8 fires (00:07–07:07 PDT). If the quota thread completes early,
  spend remaining iterations on threads 2 and 3.
