---
name: cloop-fix
description: "Work out why a cloop loop stopped firing and restart it."
argument-hint: "[slug]"
allowed-tools: ["Read", "Write", "Edit", "Glob", "Bash", "AskUserQuestion", "CronCreate", "CronList", "PushNotification"]
---

# cloop: fix

Slug (optional): **$ARGUMENTS**

Find the loop (given slug, or pick from `.claude/cloop/<slug>.state.json`), then follow **If it
stops firing** in `${CLAUDE_PLUGIN_ROOT}/skills/cloop-engine/SKILL.md`. Recreate the timer if it is
missing and the loop is not done, update `cron_job_id`, and say plainly what was wrong and what you
changed.
