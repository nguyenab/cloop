# Parse `ccs cliproxy quota --provider claude` for the default account.
# Emits key=value lines: five_h_pct, five_h_reset, weekly_pct, weekly_reset,
# sonnet_pct, sonnet_reset. Portable awk (macOS/BSD and GNU).
/\(default\)/ { blk = 1; next }
/^  \[/ { blk = 0 }
blk && /5h usage limit/          { print "five_h_pct=" pct($0); print "five_h_reset=" rst($0) }
blk && /Weekly usage limit/      { print "weekly_pct=" pct($0); print "weekly_reset=" rst($0) }
blk && /Weekly usage \(Sonnet\)/ { print "sonnet_pct=" pct($0); print "sonnet_reset=" rst($0) }
function pct(s) { sub(/.*\] */, "", s); sub(/%.*/, "", s); return s }
function rst(s) { sub(/.*Resets in */, "", s); return s }
