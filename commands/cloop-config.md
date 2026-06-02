---
name: cloop-config
description: "Read/write user-wide C Loop defaults (~/.claude/cloop/config.json) so interviews can skip those questions."
argument-hint: ""
allowed-tools: ["Read", "Write", "Edit", "Bash", "AskUserQuestion"]
---

# C Loop — Config

Manage user-wide defaults at `~/.claude/cloop/config.json` (also hand-editable). Create
`~/.claude/cloop/` if missing. Show current values, then set any keys via `AskUserQuestion`.

Schema (write valid JSON; omit unset keys):
```json
{
  "default_mode": "continuous",
  "default_interval": "20m",
  "default_commit_style": "conventional-context",
  "default_max_iterations": 50,
  "default_no_progress_limit": 5,
  "default_branch_isolation": true
}
```
Precedence the interview MUST follow: explicit interview answer > config default > built-in default.
