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

If the loop's status is `stalled`, this is not a timer fault — a guardrail landed it on purpose. Read
its latest diagnosis ADR in `.claude/cloop/adr/<slug>/`, summarize for the user what kept failing and
the narrower scope it suggests, and offer to restart. If they accept, reset `consecutive_qa_failures`
to 0 and `stalled_reason` to null, set `last_progress_iteration` to the current `iteration` (so a
plateau-stalled loop gets a fresh window instead of tripping again on the next fire), set `status`
back to running, and re-arm the timer from the saved `cron` expression (update `cron_job_id`). The next iteration reads that diagnosis ADR and picks up the
narrower scope.
