# C Loop Interview

Drives `/cloop` (full) and `/cloop-plan` (planning portion). Uses `AskUserQuestion` — these run
with a present user, NEVER by cron. Skip any question already set by `~/.claude/cloop/config.json`
(precedence: explicit answer > config default > built-in default); state which defaults applied.

1. **Context** — heuristic: if `/cloop` got a goal-hint arg, OR the conversation already contains a
   concrete goal the loop could continue → OFFER "continue existing context"; else default fresh
   (do not ask a confusing question in an empty session).
2. **Goal & type** (fresh) — suggest: code enhancement, unit tests, documentation, refactor,
   feature planning, performance, bug sweep.
3. **Criteria** — "Precise criteria (PRD / user stories)?" Yes → user pastes/drops; save under
   `.claude/cloop/` and set `criteria_ref`. No → 1-2 targeted questions on what "done/good" means.
4. **Cadence & safety** — mode (strict/continuous); interval (whole-minute; explain in plain terms
   that ~5m is the costliest band and steer to >=20m for overnight; engine avoids :00/:30); branch
   isolation (default ON → `cloop/<slug>`; offer `current` to opt out); commit style.
5. **Confirm slug** — propose the generated kebab slug; let the user accept or rename (it is their
   handle to every command).

Output: write `.claude/cloop/plans/<slug>.md` from
`${CLAUDE_PLUGIN_ROOT}/skills/cloop-engine/references/plan-template.md`. Echo slug + path.
