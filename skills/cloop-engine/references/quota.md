# Quota awareness: reading capacity from ccs

cloop can read how much Claude capacity is left before it spends an iteration. The signal is the
`ccs` CLI proxy's quota readout; this file documents the check and the parse. Later sections of
the quota behavior (skip thresholds, pause and resume on exhaustion) build on this readout.

## The check

```bash
ccs cliproxy quota --provider claude 2>/dev/null \
  | awk -f "${CLAUDE_PLUGIN_ROOT}/skills/cloop-engine/references/quota-parse.awk"
```

It prints key=value lines for the **default account only** (the one marked `(default)`):

```
five_h_pct=56
five_h_reset=2h
weekly_pct=90
weekly_reset=3d 18h
sonnet_pct=97
sonnet_reset=3d 18h
```

Percentages are integers (no `%`); reset values are the literal `Resets in` text, like `2h` or
`3d 18h`. The check is a cheap local CLI call — it does not spend Claude tokens.

## What the raw output looks like

`test/golden/quota-fixture.txt` holds a captured sample. The shape the parser relies on:

- Accounts begin with a two-space-indented status marker line: `  [OK] name (email) ...`.
  The marker text can vary (`[OK]`, `[X]`, `[!]`, `[ ]`); only the `  [` prefix matters.
- The default account's marker line carries `(default)`.
- Inside an account block, each limit line ends with
  `[<progress bar>] <pct>% Resets in <window>`.
- The default account's block ends at the next account marker line.

## Tolerance and failure

The output is human-readable text and can change between ccs versions. The parser keys on the
stable parts (the `(default)` tag, the `] N% Resets in` tail) and ignores the progress bars and
markers. If `ccs` is not installed, errors, or the format shifts so nothing matches, the pipeline
prints nothing — **treat empty output as "quota unknown" and proceed normally** rather than
blocking the loop on a broken readout.

`test/validate.sh` runs the parser against the fixture and compares to
`test/golden/quota-parse-expected.txt`, so a format change that breaks the parse fails the gate.
