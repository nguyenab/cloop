# C Loop ADR Template

One ADR per iteration: `.claude/cloop/adr/<slug>/NNNN-<title>.md`.
- `NNNN` = (committed-iteration count) + 1, zero-padded to 4. Derived at write time from the
  highest existing ADR number in the slug's ADR dir (cross-checked with `git log`).
- `<title>` = kebab-case of the ADR's one-line subject, `[a-z0-9-]` only, max ~6 words.
- The ADR is committed in the SAME commit as the change, so it has NO `commit:` field; the ADR and
  its commit share the iteration number (recover via `git log --grep "iteration N"`).

```markdown
---
id: NNNN
iteration: N
date: <ISO-8601>
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
