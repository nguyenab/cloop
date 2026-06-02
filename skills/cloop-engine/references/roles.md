# cloop roles

You pick which roles are active when you set up a loop (the setup questions ask). A normal loop uses
Planner, Worker, QA, and Scribe. Innovator is optional and heavier.

- **Planner** looks at the goal, the criteria, and the last ADR, and scopes the next one or two
  iterations, or sketches the whole arc. Keeps the loop pointed somewhere sensible.
- **Worker** does the actual implementation for the iteration.
- **QA** checks the iteration's result against the goal and the criteria file, and records pass or
  fail in the ADR.
- **Scribe** writes the ADR and the commit message in your chosen style, so the reasoning is on
  record.
- **Innovator** (optional) researches what would be best for the project, then runs a 5-agent
  council with the Workflow tool to argue for and against the idea before it reaches the Planner. It
  is the expensive role; use it occasionally, not every iteration.
