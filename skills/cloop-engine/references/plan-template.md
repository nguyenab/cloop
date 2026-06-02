# cloop plan template

A plan captures a loop's goal and cadence once, so you do not re-dump it every time. The loop reads
the frontmatter; the prose below is the goal in your own words.

```markdown
---
slug: <short-name>
interval: 20m          # how often it fires, in whole minutes
run_for: 4h            # duration (4h), a count (12 iterations), or "until <condition>"
commit_style: conventional   # conventional | plain
---

# Goal
<what you want done, in plain language>

# Scope and notes
<anything to focus on or stay away from; optional>
```

Interval tips: whole minutes only (the timer has minute granularity). Avoid :00 and :30 to dodge
scheduler pileups. Around 20m is a sensible default; very short intervals burn tokens fast.
