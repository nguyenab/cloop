---
id: 0006
iteration: 6
date: 2026-06-02T08:45:49Z
plan_slug: self-improve
qa: pass
---

## Context

A full read of the README for accuracy. The "Read this first" section told users that "marking a
loop durable means it picks back up when you reopen that same session with `claude --resume`." But
iteration 1 established that the harness often registers the timer session-only and never writes
`.claude/scheduled_tasks.json`, in which case the loop does not resume at all. So the README's
strongest persistence promise was the one most likely to be wrong, and it offered no recovery path.

## Decision

Tempered the README's durability claim to match the engine docs: resume is possible only if the
harness persisted the timer, timers are often session-only and do not survive a close, and if the
loop is quiet after reopening the user should restart it with `/cloop:cloop-execute` or
`/cloop:cloop-fix`. The rest of the README read accurately and was left alone.

## Alternatives

- Drop the resume mention entirely: rejected — resume does work when the timer is persisted, so the
  honest move is to qualify it, not delete it.
- Document the scheduler files under "Where it keeps things": rejected — they are harness-managed
  and now gitignored (iteration 2); listing them as cloop's own storage would mislead.

## Consequences

The README, SKILL.md, and /cloop-fix now tell one consistent story about session-only timers and
how to recover. Closes the user-facing half of the persistence gap opened in iteration 1.

## Links
- files: README.md
