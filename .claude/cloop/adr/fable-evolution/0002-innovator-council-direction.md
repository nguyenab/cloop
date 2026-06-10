---
id: 0002
iteration: 2
date: 2026-06-10T08:15:00Z
plan_slug: fable-evolution
qa: pass
---

## Context

The plan front-loads research: before building the remaining quota behaviors, find out what
Fable 5 (released 2026-06-09) changes for cloop and vet the direction with the Innovator
council. Researched via Anthropic's model docs: `claude-fable-5` is the most capable widely
released model — 1M context, 128k max output, $10/$50 per MTok (2x Opus 4.8), adaptive thinking
always on, and the Opus 4.7 tokenizer (~30% more tokens for the same text). Net: subscription
quota burns materially faster per unit of work, raising the value of quota awareness. Live
readout during research: 5h 56%, weekly 90%, Sonnet-weekly 97% — and a real 429 landed on a
WebFetch call mid-iteration, a live demonstration of the failure mode this thread guards.
Web search providers were blocked (DuckDuckGo anti-bot), so community-usage evidence is thin;
findings rest on Anthropic's own docs.

## Decision

Ran the 5-agent council (proponent, skeptic, lean-guardian, user-value, ops-realist) via the
Workflow tool on one question: is finishing the quota machinery the best use of the remaining
iterations, and what would a less imaginative planner miss? Verdict 4/5 yes (skeptic partial),
with a unanimous correction and three additions, recorded as "Council amendments" in the
quota-aware-scheduling plan: gate on max(5h%, weekly%) rather than 5h alone; pause honestly
based on reset horizon (no session-only heartbeat against a multi-day weekly reset); land with
a tiny wrap-up iteration instead of a silent skip; and add quota-delta accounting so thresholds
become evidence-based. No code this iteration — the deliverable is the vetted direction.

## Alternatives

- Build skip-when-low directly as planned: rejected — the council found the specced 5h-only
  gate would sleep through tonight's actual (weekly) wall; building it unamended would have
  shipped machinery that never fires when needed.
- A separate "Fable 5 notes" doc: rejected — the durable implications (cost, tokenizer) are
  captured here and in the plan amendment; a standalone doc would be fluff (cloop stays lean).
- Skeptic's "drop the heartbeat entirely": partially adopted — the heartbeat survives only for
  the 5h-wall case where a session-plausible reset makes it real.

## Consequences

Iteration 3 builds the skip-when-low gate per amendments 1-3 (binding-constraint gate +
wrap-up landing); iteration 4 wires status/fix surfacing and quota-delta accounting. The
heartbeat shrinks to the 5h-wall case only. Council cost: ~247k subagent tokens — with weekly
at 90%, remaining iterations should be deliberately small; the innovator does not run again
tonight.

## Links

- files: .claude/cloop/plans/quota-aware-scheduling.md
- workflow: innovator-council wf_0db96e13-b38 (5 agents, 247k tokens)
