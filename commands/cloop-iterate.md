---
name: cloop-iterate
description: "INTERNAL — runs exactly one unattended C Loop iteration for a slug. Fired by the loop's cron job."
argument-hint: "<slug>"
user-invocable: false
allowed-tools: ["Read", "Write", "Edit", "Glob", "Bash", "CronCreate", "CronDelete", "CronList", "PushNotification"]
disallowed-tools: ["AskUserQuestion", "EnterPlanMode", "ExitPlanMode"]
---

# C Loop — Run One Iteration (UNATTENDED)

Slug: **$ARGUMENTS**

Read `${CLAUDE_PLUGIN_ROOT}/skills/cloop-engine/SKILL.md` and follow its **Iteration lifecycle** section
for the slug above. Run EXACTLY ONE iteration, then stop — do NOT loop internally; the cron
schedule fires the next one.

This runs with NO human present. NEVER call a tool that waits for a human and NEVER do anything
that would trigger a permission prompt. Resolve all ambiguity from the plan + state + last ADR +
criteria_ref; if you cannot, set status:paused, PushNotification, and STOP (per the
NON-INTERACTIVITY INVARIANT). If state is missing or status != running, follow the Guard step.
