# Parse `ccs cliproxy quota --provider claude` for EVERY account (the proxy
# rotates the whole pool, so capacity is a pool-wide question — not the default
# account alone). Percentages are read as ccs prints them: percent REMAINING, a
# fuel gauge where a full bar / high number means healthy.
#
# Per account it emits: account, default (1/0), five_h_pct, five_h_reset,
# weekly_pct, weekly_reset, sonnet_pct/sonnet_reset (only if present), and
# binding_pct = MIN(five_h_pct, weekly_pct) — the least fuel of the two windows,
# the one that binds. A trailing pool summary emits pool_best_account and
# pool_binding_pct = the highest binding_pct across accounts (the account with
# the most fuel, i.e. where the loop should run). Portable awk (macOS/BSD + GNU).
/^  \[/ {
  n++
  nm = $0; sub(/^  \[[^]]*\] */, "", nm); sub(/ .*/, "", nm)
  name[n] = nm
  def[n]  = ($0 ~ /\(default\)/) ? 1 : 0
  next
}
n > 0 && /5h usage limit/          { fh[n]  = pct($0); fhr[n] = rst($0) }
n > 0 && /Weekly usage limit/      { wk[n]  = pct($0); wkr[n] = rst($0) }
n > 0 && /Weekly usage \(Sonnet\)/ { sn[n]  = pct($0); snr[n] = rst($0) }
END {
  best = -1; bestacct = ""
  for (i = 1; i <= n; i++) {
    b = (fh[i] + 0 < wk[i] + 0) ? fh[i] + 0 : wk[i] + 0
    bind[i] = b
    if (b > best) { best = b; bestacct = name[i] }
  }
  for (i = 1; i <= n; i++) {
    print "account="      name[i]
    print "default="      def[i]
    print "five_h_pct="   fh[i]
    print "five_h_reset=" fhr[i]
    print "weekly_pct="   wk[i]
    print "weekly_reset=" wkr[i]
    if (sn[i] != "") { print "sonnet_pct=" sn[i]; print "sonnet_reset=" snr[i] }
    print "binding_pct="  bind[i]
  }
  if (n > 0) { print "pool_best_account=" bestacct; print "pool_binding_pct=" best }
}
function pct(s) { sub(/.*\] */, "", s); sub(/%.*/, "", s); return s }
function rst(s) { sub(/.*Resets in */, "", s); return s }
