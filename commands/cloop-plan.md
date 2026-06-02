---
name: cloop-plan
description: "Interview to produce a C Loop plan (no execution). Writes .claude/cloop/plans/<slug>.md."
argument-hint: "[goal hint]"
allowed-tools: ["Read", "Write", "Edit", "Glob", "Bash", "AskUserQuestion", "WebSearch"]
---

# C Loop — Plan

Optional goal hint: **$ARGUMENTS**

Read `${CLAUDE_PLUGIN_ROOT}/skills/cloop/SKILL.md` (layout) and run the interview in
`${CLAUDE_PLUGIN_ROOT}/skills/cloop/references/interview.md`, writing the plan from
`${CLAUDE_PLUGIN_ROOT}/skills/cloop/references/plan-template.md`. Do NOT arm a loop — stop after
writing the plan and tell the user to start it with `/cloop:cloop-execute`.
