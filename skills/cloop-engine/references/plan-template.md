# cloop plan template

A plan captures a loop's goal and setup once, so you do not re-dump it every time. The loop reads
the frontmatter; the prose below is the goal in your own words.

```markdown
---
slug: <short-name>
mode: continuous          # strict | continuous
interval: 20m             # how often it fires, in whole minutes
max_iterations: 50        # stop after this many (required for strict; a cap for continuous)
roles: [planner, worker, qa, scribe]   # add innovator for the council
commit_style: conventional-context     # conventional-context | brief-context | custom
criteria_ref: null         # optional path to a PRD or user-stories file
check: null                # optional shell command that must exit 0 for QA to pass (e.g. npm test)
---

# Goal
<what you want done, in plain language>

# Scope and notes
<focus areas, what to avoid; optional>
```

Interval tips: whole minutes only, and avoid :00 and :30 to dodge scheduler pileups. Around 20m is a
sensible default; very short intervals burn tokens fast.

A loop without a `check` command is only as reliable as LLM judgment; give it one when the project
has tests.

Completion is tracked by the criteria ledger at `.claude/cloop/criteria/<slug>.md`, written at
setup — or by the first iteration, for a hand-written plan. `criteria_ref` is separate: an optional
pointer to an external PRD or user-stories file, and it can stay null.
