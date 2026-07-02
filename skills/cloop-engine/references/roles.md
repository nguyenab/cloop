# cloop roles

You pick which roles are active when you set up a loop (the setup questions ask). A normal loop uses
Planner, Worker, QA, and Scribe. Innovator is optional and heavier.

- **Planner** looks at the goal, the criteria, and the recent ADRs, and scopes the next one or two
  iterations, or sketches the whole arc. Ends each scoped step with an explicit `Done when:` line
  QA can check this iteration. Keeps the loop pointed somewhere sensible.
- **Worker** does the actual implementation for the iteration.
- **QA** checks in two tiers: first the deterministic ones (the plan's `check` command exits 0, and
  the iteration produced a non-empty diff scoped to the step), then judgment — the `Done when` line,
  flipping the criteria boxes this iteration satisfied, and spirit over letter, never weakening
  tests or criteria to make a check pass. Records pass or fail in the ADR.
- **Scribe** writes the ADR and the commit message in your chosen style, so the reasoning is on
  record, and fills the ADR's Handoff section so the next iteration inherits the outcome and any
  grounded failure reason.
- **Innovator** (optional) researches what would be best for the project, then runs a 5-agent
  council with the Workflow tool to argue for and against the idea before it reaches the Planner. It
  is the expensive role; use it occasionally, not every iteration.
