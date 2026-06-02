---
name: cloop-execute
description: "Arm a durable C Loop from an existing plan: estimate+confirm, create the branch, start the cron loop."
argument-hint: "[slug]"
allowed-tools: ["Read", "Write", "Edit", "Glob", "Bash", "AskUserQuestion", "CronCreate", "CronList", "PushNotification"]
---

# C Loop — Execute

Requested slug (optional): **$ARGUMENTS**

1. Enumerate plans in `.claude/cloop/plans/` (Glob/Read). If a slug was given and matches, use it;
   else present choices via `AskUserQuestion`. No plans → suggest `/cloop:cloop-plan` and stop.
2. Read `${CLAUDE_PLUGIN_ROOT}/skills/cloop/SKILL.md` and follow **"Arming a durable cron loop"**:
   require `interval`; validate `branch`/`criteria_ref`; show the cost estimate and CONFIRM;
   create/checkout the branch; `CronCreate` durable+recurring with the self-contained payload;
   record cron_job_id/armed_at_sha; initialize state (atomic write).
3. Confirm cadence, cron expression, job id, branch, and expiry to the user.
