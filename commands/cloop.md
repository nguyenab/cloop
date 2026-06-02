---
name: cloop
description: "Start C Loop: full interview to design a continuous loop, write its plan, then (with a cost estimate) offer to start iterating."
argument-hint: "[goal hint]"
allowed-tools: ["Read", "Write", "Edit", "Glob", "Bash", "AskUserQuestion", "WebSearch", "CronCreate", "CronList", "PushNotification"]
---

# C Loop

Optional goal hint: **$ARGUMENTS**

1. Read `${CLAUDE_PLUGIN_ROOT}/skills/cloop-engine/SKILL.md`, run the interview in
   `${CLAUDE_PLUGIN_ROOT}/skills/cloop-engine/references/interview.md`, write the plan from
   `plan-template.md`.
2. Then ask (via `AskUserQuestion`) whether to start now.
   - Yes → follow **"Arming a durable cron loop"** (estimate+confirm, branch, durable CronCreate,
     init state).
   - No → tell them to start later with `/cloop:cloop-execute`.
