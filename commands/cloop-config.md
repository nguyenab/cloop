---
name: cloop-config
description: "Set your default mode, interval, iteration cap, roles, and commit style so setup does not ask every time."
argument-hint: ""
allowed-tools: ["Read", "Write", "Edit", "Bash", "AskUserQuestion"]
---

# cloop: config

Manage defaults at `~/.claude/cloop/config.json` (also fine to hand-edit). Create `~/.claude/cloop/`
if it is missing, show current values, then set any of these:

```json
{
  "default_mode": "continuous",
  "default_interval": "20m",
  "default_max_iterations": 50,
  "default_roles": ["planner", "worker", "qa", "scribe"],
  "default_commit_style": "conventional-context"
}
```

Setup reads this and skips anything it already covers, so you answer once.
