---
name: cloop-execute
description: "Start a cloop loop from an existing plan."
argument-hint: "[slug]"
allowed-tools: ["Read", "Write", "Edit", "Glob", "Bash", "AskUserQuestion", "CronCreate", "CronList", "PushNotification"]
---

# cloop: start

Slug (optional): **$ARGUMENTS**

1. List plans in `.claude/cloop/plans/`. If a slug was given and matches, use it; otherwise ask
   which one. If there are none, suggest `/cloop:cloop-plan` and stop.
2. Follow **Starting a loop** in `${CLAUDE_PLUGIN_ROOT}/skills/cloop-engine/SKILL.md`: build the
   timer, save state, and tell the user the cadence, how long it will run, and the job id.
