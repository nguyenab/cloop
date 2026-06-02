# cloop setup questions

Used by `/cloop` and `/cloop-plan`. These run with you present, so they can ask. Keep it short:
the whole point is that you answer once and never re-dump it. Skip anything already set in
`~/.claude/cloop/config.json` and say which defaults you used.

Ask only what is missing:

1. What should the loop work on? (the goal)
2. How often should it run? (interval, whole minutes; ~20m is a fine default)
3. How long should it keep going? (a duration like 4h, a count like 12 iterations, or until some
   condition is true)
4. Commit style: conventional or plain.

Then write `.claude/cloop/plans/<slug>.md` from
`${CLAUDE_PLUGIN_ROOT}/skills/cloop-engine/references/plan-template.md`, generate a short kebab
`slug` from the goal (confirm it with the user), and tell them the slug and file path.
