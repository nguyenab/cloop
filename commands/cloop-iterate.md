---
name: cloop-iterate
description: "Internal. Runs one cloop iteration for a slug. Fired by the loop's timer, not meant to be run by hand."
argument-hint: "<slug>"
user-invocable: false
allowed-tools: ["Read", "Write", "Edit", "Glob", "Bash", "CronDelete", "CronList", "PushNotification"]
disallowed-tools: ["AskUserQuestion", "EnterPlanMode", "ExitPlanMode"]
---

# cloop: one iteration

Slug: **$ARGUMENTS**

Read `${CLAUDE_PLUGIN_ROOT}/skills/cloop-engine/SKILL.md` and follow **What one iteration does**
for this slug. Do exactly one iteration, then stop. The timer fires the next one.

No human is here, so do not ask anything and do not do anything that needs a permission prompt.
Work from the plan and the notes file. If you truly cannot tell what to do, write that into the
summary and stop.
