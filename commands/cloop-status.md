---
name: cloop-status
description: "Show what your cloop loops are doing and what they have changed so far."
argument-hint: "[slug]"
allowed-tools: ["Read", "Glob", "Bash", "CronList"]
---

# cloop: status

Slug (optional): **$ARGUMENTS**

For each `.claude/cloop/<slug>.state.json` (or the given slug), produce the **Summary** described in
`${CLAUDE_PLUGIN_ROOT}/skills/cloop-engine/SKILL.md`: goal, mode, iterations run, the main changes
(from `git log` and the ADRs), and anything left over. When a criteria ledger exists at
`.claude/cloop/criteria/<slug>.md`, count its boxes and report progress as `N of M criteria met`.
Cross-check `CronList`; if a loop says running but its timer is gone, say so and point to
`/cloop:cloop-fix <slug>`. If a loop's status is `stalled`, say so, point at its latest diagnosis ADR
in `.claude/cloop/adr/<slug>/`, and note that `/cloop:cloop-fix <slug>` can read it and restart with
a narrower scope. If there are no loops, say so plainly.
