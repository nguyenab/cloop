# Quota awareness: reading capacity from ccs

cloop can read how much Claude capacity is left before it spends an iteration. The signal is the
`ccs` CLI proxy's quota readout; this file documents the check and the parse. Later sections of
the quota behavior (skip thresholds, pause and resume on exhaustion) build on this readout.

**Fuel-gauge semantics — read this first.** ccs prints each limit as percent **remaining**, like a
fuel gauge: a full bar at `98%` means 98 percent of capacity is *left* (healthy), and `4%` means
nearly *empty*. The gate proceeds while fuel is high and pauses only when it runs low — the
opposite direction from a percent-*used* meter. Everything below is written in remaining terms.

## The check

```bash
ccs cliproxy quota --provider claude 2>/dev/null \
  | awk -f "${CLAUDE_PLUGIN_ROOT}/skills/cloop-engine/references/quota-parse.awk"
```

It prints key=value lines for **every account** — the ccs proxy rotates across the whole pool, so
capacity is a pool-wide question, not a property of the default account. Each account block carries
its windows plus a computed `binding_pct`, and a trailing pool summary names the account with the
most fuel:

```
account=alice
default=1
five_h_pct=56
five_h_reset=2h
weekly_pct=90
weekly_reset=3d 18h
sonnet_pct=97
sonnet_reset=3d 18h
binding_pct=56
account=bob
default=0
five_h_pct=73
five_h_reset=2h
weekly_pct=92
weekly_reset=2h
binding_pct=73
pool_best_account=bob
pool_binding_pct=73
```

All percentages are **remaining** (see fuel-gauge note above). `binding_pct` is `MIN(five_h_pct,
weekly_pct)` — the window with the *least* fuel, the one that binds that account. `pool_binding_pct`
is the *highest* `binding_pct` across accounts: the fuel available at the best account, which is
where the loop should run. `sonnet_pct`/`sonnet_reset` appear only when ccs reports a Sonnet line;
the default account is flagged with `default=1` but is **not** privileged — selection is by fuel.
Percentages are integers (no `%`); reset values are the literal `Resets in` text, like `2h` or
`3d 18h`. The check is a cheap local CLI call — it does not spend Claude tokens.

## What the raw output looks like

`test/golden/quota-fixture.txt` holds a captured sample. The shape the parser relies on:

- Accounts begin with a two-space-indented status marker line: `  [OK] name (email) ...`.
  The marker text can vary (`[OK]`, `[X]`, `[!]`, `[ ]`); only the `  [` prefix matters. The
  account name is the first token after the marker; the marker itself tracks that account's
  own fuel (`[X]` ≈ empty, `[!]` ≈ low, `[OK]` ≈ healthy) but the parser reads the numbers.
- The default account's marker line carries `(default)`.
- Inside an account block, each limit line ends with
  `[<progress bar>] <pct>% Resets in <window>`, where `<pct>` is percent **remaining**.
- Each account's block ends at the next account marker line (or end of input).

## Tolerance and failure

The output is human-readable text and can change between ccs versions. The parser keys on the
stable parts (the `  [` account-marker prefix, the `(default)` tag, the `] N% Resets in` tail) and
ignores the progress bars and marker text. If `ccs` is not installed, errors, or the format shifts
so nothing matches, the pipeline prints nothing — **treat empty output as "quota unknown" and
proceed normally** rather than blocking the loop on a broken readout.

`test/validate.sh` runs the parser against the fixture and compares to
`test/golden/quota-parse-expected.txt`, so a format change that breaks the parse fails the gate.

## The gate (step 0 of every iteration)

Run the check before any token-heavy work. The pool has capacity when **any** account has fuel, so
judge by `pool_binding_pct` — the best account's `binding_pct`, already the `MIN` of its two windows
(never the 5h gauge alone: a 5h-only gate sleeps through a weekly wall; never the *higher* window
either: that reads the fullest gauge and ignores the one about to run dry).

- **Empty output** → quota unknown. Proceed normally.
- **`pool_binding_pct` ≥ floor** → proceed normally; run at `pool_best_account`.
- **`pool_binding_pct` < floor** → every account is near empty. Do not start new feature work; run a
  **wrap-up landing** instead. Exhaustion is a scheduled landing, not an error to suppress.

The floor is a documented constant: **10** (percent *remaining*, on the binding window of the best
account). Above it there is fuel to burn; below it the whole pool is dry. Tune it here if needed;
nothing else hardcodes it.

## Wrap-up landing and pause

A wrap-up landing is one deliberately tiny iteration that leaves the loop parked cleanly:

1. Leave the tree coherent: commit safe in-flight work or revert it, as on a QA fail.
2. Write a short handoff ADR: what shipped so far, what is half-done, the quota readout, and
   when capacity returns. This is the iteration's ADR; commit it.
3. Set state: `status: paused-quota`, `paused_reason` (e.g. `best account weekly at 6% remaining`),
   `resume_at` = now plus the **binding window's** reset at `pool_best_account` (the `five_h_reset`
   or `weekly_reset` whose window is the binding `MIN`) plus a small buffer, and store the parsed
   readout in `last_quota`. Set `last_adr` to the handoff ADR; a landing is not a new iteration, so
   leave `iteration` unchanged.
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
