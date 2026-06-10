---
id: 0001
iteration: 1
date: 2026-06-10T07:10:00Z
plan_slug: fable-evolution
qa: pass
---

## Context

First iteration of the overnight fable-evolution loop. The quota-aware-scheduling plan
(criteria_ref) names a reproducible parse of `ccs cliproxy quota --provider claude` as the
foundation everything else (skip-when-low, pause/resume on exhaustion) builds on. Nothing existed
yet; the plan's guess about account markers (`[X]`/`[!]`/`[ ]`) needed checking against reality.

## Decision

Captured live output and built the parse on what is actually there: accounts are marked `[OK]`
(status text varies; only the two-space `[` prefix is structural) and the default account carries
a `(default)` tag. Shipped a portable awk script
(`skills/cloop-engine/references/quota-parse.awk`) that emits six key=value lines for the default
account (5h/weekly/Sonnet percentages and reset windows), a reference doc
(`references/quota.md`) documenting the check, the format contract, and the empty-output =
"quota unknown, proceed normally" failure rule, plus a sanitized fixture and golden expectation
wired into `test/validate.sh` as check 9. Verified the parser gives identical output on the live
command and the fixture.

## Alternatives

- Inline one-liner duplicated in docs and tests: rejected — two copies of the same awk would
  drift; one `.awk` file is referenced by both.
- A python/jq parser: rejected — output is plain text, awk is already everywhere, and cloop
  stays lean (no new dependencies).
- Committing the raw capture: rejected — it contains real account emails; fixture uses
  example.com names with byte-identical structure.

## Consequences

Acceptance item 1 of the quota plan is met. Next iterations can call the documented check at the
top of a fire and trust the keys. Likely next: the Innovator council (front-loaded research per
the plan), then skip-when-low wiring into SKILL.md's iteration steps using `five_h_pct > 90`.
If ccs changes its output format, validate.sh check 9 fails loudly instead of the loop silently
losing quota awareness.

## Links

- files: skills/cloop-engine/references/quota-parse.awk,
  skills/cloop-engine/references/quota.md, test/golden/quota-fixture.txt,
  test/golden/quota-parse-expected.txt, test/validate.sh
