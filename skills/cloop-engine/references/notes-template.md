# cloop notes template

The loop keeps one notes file per slug at `.claude/cloop/<slug>.notes.md`. It is just the loop's
memory between iterations: it reads it at the start of each iteration and updates it at the end.
No strict format is required. Keep it short and useful. A simple shape:

```markdown
# <slug>

## Where things stand
<a line or two on the current state>

## Next
- the next concrete thing to do
- and the one after that

## Done
- iteration 3: <what changed>
- iteration 2: <what changed>
- iteration 1: <what changed>
```
