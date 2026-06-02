---
name: cloop-fix
description: "Diagnose why a C Loop isn't firing and repair/re-arm it (disabled cron, parked prompt, missing/duplicate/expired job, fresh-vs-resumed session, corrupt state)."
argument-hint: "[slug]"
allowed-tools: ["Read", "Write", "Edit", "Glob", "Bash", "AskUserQuestion", "CronCreate", "CronList", "CronDelete", "PushNotification"]
---

# C Loop — Fix

Requested slug (optional): **$ARGUMENTS**

1. Identify the loop (given slug, or pick from `.claude/cloop/state/*.state.json`).
2. Read `${CLAUDE_PLUGIN_ROOT}/skills/cloop/SKILL.md` and work the **"/cloop-fix checklist"** in
   order (incl. disabled-cron, parked-prompt, missing/duplicate/expired job, fresh-vs-resumed
   session, corrupt/stale state/lock).
3. Re-arm **transactionally** where the checklist calls for it (CronCreate new → verify via
   CronList → CronDelete old → update state).
4. Print a clear summary: what was wrong, what changed, current status.
