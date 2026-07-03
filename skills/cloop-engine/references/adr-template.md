# cloop ADR template

One ADR per iteration at `.claude/cloop/adr/<slug>/NNNN-title.md`. `NNNN` is the last ADR number in
the slug's adr dir plus one, zero-padded to 4 (so the first is 0001). `title` is a short kebab
summary. It is committed together with the change it describes.

```markdown
---
id: NNNN
iteration: N
date: <ISO>
plan_slug: <slug>
qa: pass        # pass | fail | n/a
---

## Context
<why this iteration did what it did, and where things stood going in>

## Decision
<what was done and the approach taken>

## Alternatives
<options weighed and why they were not chosen; "none, mechanical change" is fine>

## Consequences
<effects, follow-ups, and what likely comes next>

## Handoff
<at most 5 lines for the next iteration to read as external feedback: the outcome; if QA failed, the
grounded reason — the failing check and its output, not "insufficient"; what to avoid next; what
likely comes next>

## Links
- files: <paths this iteration touched>
```

A landing ADR (quota wrap-up or stall diagnosis) uses `qa: n/a` and carries `iteration` as it
stands in state — a landing does not start a new iteration; only `NNNN` advances.
