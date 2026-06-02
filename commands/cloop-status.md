---
name: cloop-status
description: "Show active C Loops (iteration, last ADR, commits, expiry) as a morning report; print exact remediation commands for any problem."
argument-hint: "[slug]"
allowed-tools: ["Read", "Glob", "Bash", "CronList"]
---

# C Loop — Status

Optional slug filter: **$ARGUMENTS**

Read `${CLAUDE_PLUGIN_ROOT}/skills/cloop-engine/SKILL.md` and produce the **Morning report** for each
`.claude/cloop/state/*.state.json` (or the given slug): one scannable line per loop (status,
iter N/max, commit count via `git log --oneline <armed_at_sha>..HEAD`, last ADR title, expires in
Xd). Cross-check `CronList` + `.claude/scheduled_tasks.json`; if a loop claims running but its job
is absent (or duplicated, or near expiry, or state corrupt), print the EXACT remediation command
(e.g. `/cloop:cloop-fix <slug>`). If there are no loops, say so plainly.
