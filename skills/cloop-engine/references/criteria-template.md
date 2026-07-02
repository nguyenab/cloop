# cloop criteria template

A criteria ledger is a small committed checklist that makes progress and completion
machine-readable. It lives at `.claude/cloop/criteria/<slug>.md`, committed like the plan. Copy the
shape below.

```markdown
# Criteria: <slug>

One line per criterion. The loop may only flip `[ ]` to `[x]` (or back, with the flip noted in
that iteration's ADR). It never rewrites, reorders, or deletes a criterion. New requirements
discovered mid-loop go under Discovered, never into the original list.

- [ ] <criterion in plain language> — verify: <the concrete check: a command, a file, a behavior>

## Discovered
<criteria surfaced during the loop, same format; starts empty>
```

Every criterion line must carry a `— verify:` clause naming a concrete check. Aspirational criteria
without a verification method produce inconsistent QA verdicts.
