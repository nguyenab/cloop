# cloop setup questions

Used by `/cloop` and `/cloop-plan`. You are present, so these can ask. Keep it tight: you answer
once and do not re-dump it later. Skip anything already set in `~/.claude/cloop/config.json` and say
which defaults you used.

1. **Fresh or continuing?** If there is already context or work in this session, ask whether to
   continue it or start fresh.
2. **Goal.** What should the loop work on (tests, docs, refactor, features, cleanup, and so on)?
3. **Criteria.** Is there a precise spec, like a PRD or a user-stories file? If yes, take the path
   and set `criteria_ref`. If no, ask one or two questions to pin down what "done" means.
4. **Mode.** Strict (stop when done or after N iterations) or continuous (until you stop it).
5. **Cadence.** Interval in whole minutes (~20m is a fine default) and `max_iterations`.
6. **Roles.** Which roles run the loop. Default is planner, worker, qa, scribe; offer to add the
   Innovator council.
7. **Commit style.** conventional-context, brief-context, or custom.

Then write `.claude/cloop/plans/<slug>.md` from
`${CLAUDE_PLUGIN_ROOT}/skills/cloop-engine/references/plan-template.md`, confirm the generated slug
with the user, and report the path.
