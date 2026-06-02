---
name: cloop-stop
description: "Stop a running C Loop: cancel its scheduled job and mark its state stopped."
argument-hint: "[slug]"
allowed-tools: ["Read", "Write", "Edit", "Glob", "Bash", "AskUserQuestion", "CronList", "CronDelete"]
---

# C Loop — Stop

Requested slug (optional): **$ARGUMENTS**

1. Identify the loop: given slug, else list `running` loops from `.claude/cloop/state/*.state.json`
   and ask via `AskUserQuestion`.
2. Read its state; `CronDelete` the `cron_job_id`; cross-check `CronList` to confirm removal
   (delete any duplicates for the slug too).
3. Set state `status: stopped` (atomic write). Confirm; note the plan, ADRs, and branch remain so
   the loop can be resumed later with `/cloop:cloop-execute`.
