# cloop commit messages

Each commit embeds the why and points to its ADR, so `git log` alone tells the story. Pick the
style in setup with `commit_style`.

## conventional-context (default)
```
<type>(<scope>): <summary>

Why: <1-2 sentences from the ADR's Context and Decision>
ADR: .claude/cloop/adr/<slug>/NNNN-title.md
cloop: <slug> iteration N
```
`<type>` is one of feat, fix, refactor, test, docs, chore, perf, style.

## brief-context
```
<short summary>

Why: <1-2 sentences>
ADR: .claude/cloop/adr/<slug>/NNNN-title.md
cloop: <slug> iteration N
```

## custom
Your own template. It must include the `ADR:` path and the iteration so the trail stays intact.
