---
slug: self-improve
mode: strict
interval: 18m
max_iterations: 8
roles: [planner, worker, qa, scribe]
commit_style: brief-context
criteria_ref: null
---

# Goal

Dogfood cloop on its own repository. This is a full test run: each iteration both
exercises the cloop machinery and improves the cloop project itself. After doing the
work, evaluate how the iteration went — was the plan clear, did the loop fire, did the
ADR and commit read well, was anything awkward or missing — and turn that evaluation
into a concrete enhancement to the cloop project (docs, skills, command prompts,
references, templates, or scaffolding).

"Done" for each iteration: one real, reviewed improvement is committed with an ADR that
records both the change and the meta-observation that motivated it. The loop is
exploratory — there is no PRD — so success is a steady stream of genuine improvements,
not chasing a fixed checklist.

# Scope and notes

- Stay within the cloop project (skills/, commands, references, README, plugin/marketplace
  metadata, .claude/cloop scaffolding). Do not wander into unrelated repos.
- Honor the project's own rule: cloop stays a lean /loop wrapper, not an orchestration
  framework. Prefer clarifying, tightening, and fixing over adding heavy machinery.
- Each iteration should leave the repo in a working state: skills still parse, command
  references resolve, no broken paths.
- Keep changes small and independently reviewable — one coherent improvement per commit.
- When evaluating, look for: confusing instructions, broken or stale file paths, gaps
  between what the docs promise and what the commands do, missing edge-case handling,
  and rough onboarding. Record the observation in the ADR's Context.
- Never push. Commit only.
