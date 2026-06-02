---
name: cloop-plan
description: "Write a cloop plan without starting it. Saves the goal and cadence so you can reuse it."
argument-hint: "[what to work on]"
allowed-tools: ["Read", "Write", "Edit", "Glob", "Bash", "AskUserQuestion", "WebSearch"]
---

# cloop: plan

What to work on (optional): **$ARGUMENTS**

Ask the setup questions in `${CLAUDE_PLUGIN_ROOT}/skills/cloop-engine/references/interview.md` and
write the plan from `${CLAUDE_PLUGIN_ROOT}/skills/cloop-engine/references/plan-template.md`. Do not
start a loop. Tell the user they can start it with `/cloop:cloop-execute`.
