---
name: cloop-status
description: "Show what your cloop loops are doing and what they have changed so far."
argument-hint: "[slug]"
allowed-tools: ["Read", "Glob", "Bash", "CronList"]
---

# cloop: status

Slug (optional): **$ARGUMENTS**

For each `.claude/cloop/<slug>.state.json` (or the given slug), produce the **Summary** described in
`${CLAUDE_PLUGIN_ROOT}/skills/cloop-engine/SKILL.md`: goal, iterations run, the main changes (from
`git log`), and anything left over. Cross-check `CronList`; if a loop says running but its timer is
gone, say so and point to `/cloop:cloop-fix <slug>`. If there are no loops, say so plainly.
