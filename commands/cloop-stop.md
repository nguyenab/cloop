---
name: cloop-stop
description: "Stop a running cloop loop early."
argument-hint: "[slug]"
allowed-tools: ["Read", "Write", "Edit", "Glob", "Bash", "AskUserQuestion", "CronList", "CronDelete"]
---

# cloop: stop

Slug (optional): **$ARGUMENTS**

1. Find the loop: use the given slug, or list running loops from `.claude/cloop/<slug>.state.json`
   and ask which one.
2. Cancel its timer with `CronDelete` (the `cron_job_id` in state), confirm with `CronList`, set
   `status` to stopped, and write the end **Summary**. The plan and notes stay on disk so it can be
   restarted later with `/cloop:cloop-execute`.
