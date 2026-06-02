---
id: 0003
iteration: 3
date: 2026-06-02T08:45:49Z
plan_slug: self-improve
qa: pass
---

## Context

The "next likely step" recorded in ADR 0001. During setup, building the timer for this loop
from an 18m interval, the first attempt used a step-from-offset cron `7/18 * * * *` and the
scheduler rejected it ("Expected 5 fields" / invalid). The working expression was a comma list
`7,25,43`. But "Starting a loop" only said "build a 5-field cron expression... pick a minute
not :00 or :30" — it gave no help translating an arbitrary whole-minute interval into a valid
expression, so the same dead end would catch the next person.

## Decision

Added one sentence of honest translation guidance to "Starting a loop": `*/N` only steps evenly
when N divides 60; step-from-offset forms like `7/18` are rejected; for intervals that do not
divide 60, use an evenly-spaced comma list (18m -> `7,25,43`, accepting one wider gap per hour).
The example is exactly what this loop runs, so the docs now describe real, tested behavior.

## Alternatives

- Restrict intervals to divisors of 60 in the interview: rejected — too limiting, and the comma
  list works fine.
- Add an interval->cron lookup table reference file: rejected as over-engineered for a lean
  wrapper; one sentence covers it.

## Consequences

Setup can build a valid timer for any whole-minute interval on the first try. Closes the
follow-up from ADR 0001.

## Links
- files: skills/cloop-engine/SKILL.md
