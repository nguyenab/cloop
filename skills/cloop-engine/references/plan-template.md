# C Loop Plan Template

The engine parses ONLY the frontmatter (fixed key set; unknown keys are ignored with a warning).
Prose sections are context for the working agent.

```markdown
---
slug: <kebab-case-id>
mode: continuous            # strict | continuous
interval: 20m               # REQUIRED in v0.1; whole-minute floor (e.g. 1m, 2m, 20m, 2h)
engine: cron                # cron (v0.1). 'dynamic' is reserved / not yet implemented.
branch: cloop/<slug>        # default cloop/<slug>; 'current' to commit on the checked-out branch; or a named branch
commit_style: conventional-context   # conventional-context | brief-context | custom
custom_commit_template: null          # required only when commit_style: custom
max_iterations: 50          # hard ceiling on FIRES; confirmed at arm time
no_progress_limit: 5         # consecutive no-real-progress iterations → auto-pause + notify
criteria_ref: null           # optional REPO-RELATIVE path to PRD.json / user-stories.md
---

# Objective
<what this loop is trying to achieve and what "good" looks like>

# Done criteria
<bullet list, OR "See criteria_ref">

# Iteration scope / guardrails
<what ONE iteration should accomplish; what NOT to touch; repo-specific constraints>
```

## Interval guidance (author heuristics, NOT Anthropic constants)
- Whole-minute floor: cron has 1-minute granularity; sub-minute values round up. No `90s`.
- `< ~270s`: prompt cache stays warm but burns tokens fastest — short bursts only.
- `5m`: worst case — pays a full cache miss without amortizing. Avoid.
- `>= ~20m`: economical for overnight runs (cache expires; each iteration starts cold). Recommended default.
- Jitter is significant: recurring jobs can fire up to ~30 min late (or up to half the interval
  for sub-hourly tasks). Never rely on exact timing. The engine picks a non-`:00`/`:30` minute.
