---
name: cloop
description: "Set up a continuous /loop and start it: a few quick questions, then it runs on a timer and carries its own direction forward."
argument-hint: "[what to work on]"
allowed-tools: ["Read", "Write", "Edit", "Glob", "Bash", "AskUserQuestion", "WebSearch", "CronCreate", "CronList", "PushNotification"]
---

# cloop

What to work on (optional): **$ARGUMENTS**

1. Ask the short setup questions in
   `${CLAUDE_PLUGIN_ROOT}/skills/cloop-engine/references/interview.md` and write the plan from
   `${CLAUDE_PLUGIN_ROOT}/skills/cloop-engine/references/plan-template.md`.
2. Ask whether to start now. If yes, follow **Starting a loop** in
   `${CLAUDE_PLUGIN_ROOT}/skills/cloop-engine/SKILL.md`. If no, tell them they can start later with
   `/cloop:cloop-execute`.
