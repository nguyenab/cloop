# C Loop Commit Templates

Placeholder substitution is done by the Scribe agent (no engine "machine"). The `ADR:` pointer is
always the FULL repo-root-relative path. Trailers use ASCII separators (no non-ASCII middle dot).

## conventional-context (default)
```
<type>(<scope>): <concise summary>

Why: <1-3 sentence rationale from the ADR Context/Decision>
ADR: .claude/cloop/adr/<slug>/NNNN-title.md
Loop: <slug> | iteration N
```
`<type>` is one of feat, fix, refactor, test, docs, chore, perf, style.

## brief-context
```
<concise non-conventional subject>

Why: <1-3 sentence rationale>
ADR: .claude/cloop/adr/<slug>/NNNN-title.md
Loop: <slug> | iteration N
```

## custom
Use the plan's `custom_commit_template` verbatim. It MUST include the full ADR path and the
iteration number so the trail stays intact. Substituted placeholders: `{summary}`, `{why}`,
`{adr_path}`, `{slug}`, `{iteration}`, `{type}`, `{scope}`.
