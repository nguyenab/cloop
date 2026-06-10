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

## The gate (step 0 of every iteration)

Run the check before any token-heavy work. Decide on the **binding constraint** — whichever of
`five_h_pct` and `weekly_pct` is higher — never on the 5h gauge alone (a 5h-only gate sleeps
through a weekly wall).

- **Empty output** → quota unknown. Proceed normally.
- **Binding percentage ≤ 90** → proceed normally.
- **Binding percentage > 90** → do not start new feature work. Run a **wrap-up landing** instead:
  exhaustion is a scheduled landing, not an error to suppress.

The threshold is a documented constant: **90** (percent used, on the binding window). Tune it
here if needed; nothing else hardcodes it.

## Wrap-up landing and pause

A wrap-up landing is one deliberately tiny iteration that leaves the loop parked cleanly:

1. Leave the tree coherent: commit safe in-flight work or revert it, as on a QA fail.
2. Write a short handoff ADR: what shipped so far, what is half-done, the quota readout, and
   when capacity returns. This is the iteration's ADR; commit it.
3. Set state: `status: paused-quota`, `paused_reason` (e.g. `weekly at 92%`), `resume_at` = now
   plus the **binding window's** reset (`five_h_reset` or `weekly_reset`, whichever is binding)
   plus a small buffer, and store the parsed readout in `last_quota`.
4. Pause honestly, by reset horizon:
   - **Binding reset within ~6h** (the 5h wall): `CronDelete` the fast timer and `CronCreate` a
     slow check-only heartbeat (~20m) whose prompt re-runs the iterate command for this slug;
     save its id in `slow_cron_job_id`. On a later fire with capacity back, re-arm the fast
     timer from the saved `cron` expression, delete the heartbeat, set `status: running`.
   - **Binding reset beyond ~6h** (a weekly wall, measured in days): do **not** arm a heartbeat
     — a session-only timer cannot survive until a multi-day reset, and pretending otherwise is
     theater. `CronDelete` the fast timer, leave `slow_cron_job_id` null, and rely on
     `/cloop:cloop-fix` or `/cloop:cloop-status` to offer the re-arm in a later session.
5. Notify (PushNotification): paused, why, and the exact reset time.

A real **429 during an iteration** is the same landing, taken immediately: the proxy already
rotates accounts, so a 429 means everyone is out. Stop the current step, keep the tree coherent,
and run the landing with whatever quota readout is available.
