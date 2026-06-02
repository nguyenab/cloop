#!/usr/bin/env bash
# C Loop deterministic test gate. Run from anywhere; operates on the repo root.
# TEST/BUILD tooling only (NOT plugin runtime). POSIX dev env: macOS, or Git Bash/WSL on Windows.
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0
pass(){ printf 'PASS  %s\n' "$1"; }
bad(){ printf 'FAIL  %s\n' "$1"; fail=1; }

# 1. Validate BOTH manifests on their own paths. A co-located marketplace.json makes
#    `claude plugin validate ./` check only the marketplace, so we validate each explicitly:
#    marketplace.json for the marketplace, plugin.json for the plugin + its components.
if command -v claude >/dev/null 2>&1; then
  if claude plugin validate ./.claude-plugin/marketplace.json --strict >/dev/null 2>&1; then
    pass "claude plugin validate marketplace --strict"
  else
    bad "claude plugin validate marketplace --strict"
  fi
  if claude plugin validate ./.claude-plugin/plugin.json --strict >/dev/null 2>&1; then
    pass "claude plugin validate plugin --strict"
  else
    bad "claude plugin validate plugin --strict"
  fi
else
  printf 'SKIP  claude CLI not found (manifest validate)\n'
fi

# 2. All JSON (manifests + schemas) is syntactically valid
for j in .claude-plugin/plugin.json .claude-plugin/marketplace.json \
         test/schemas/state.schema.json test/schemas/config.schema.json; do
  if python3 -m json.tool "$j" >/dev/null 2>&1; then pass "json valid: $j"; else bad "json invalid: $j"; fi
done

# 3. Frontmatter lint: every command + skill begins with --- and has name + description
while IFS= read -r f; do
  if [ "$(sed -n '1p' "$f")" = "---" ] && grep -q '^name:' "$f" && grep -q '^description:' "$f"; then
    pass "frontmatter: $f"
  else
    bad "frontmatter: $f"
  fi
done < <( { ls commands/*.md 2>/dev/null; find skills -name 'SKILL.md'; } )

# 4. The unattended cron payload command carries its non-interactive guards
if grep -q 'user-invocable: false' commands/cloop-iterate.md \
   && grep -q 'disallowed-tools' commands/cloop-iterate.md \
   && grep -q 'AskUserQuestion' commands/cloop-iterate.md; then
  pass "iterate non-interactive guards"
else
  bad "iterate non-interactive guards"
fi

# 5. Every \${CLAUDE_PLUGIN_ROOT}/... reference resolves to a real file
while IFS= read -r ref; do
  rel=$(printf '%s' "$ref" | sed 's#${CLAUDE_PLUGIN_ROOT}/##')
  if [ -f "$rel" ]; then pass "ref: $rel"; else bad "missing ref: $rel"; fi
done < <(grep -rhoE '\$\{CLAUDE_PLUGIN_ROOT\}/[A-Za-z0-9._/-]+' commands skills | sort -u)

# 6. No placeholder markers left in shipped prose
targets="commands skills"
[ -f README.md ] && targets="$targets README.md"
if grep -RInE 'TODO|TBD|FIXME' $targets >/dev/null 2>&1; then
  bad "placeholder markers present"; grep -RInE 'TODO|TBD|FIXME' $targets
else
  pass "no TODO/TBD/FIXME"
fi

# 7. State-key consistency: every canonical key appears in BOTH SKILL.md and the state schema
keys="slug status fires iteration cron_job_id engine interval branch armed_at_sha durable created_at expires_at rearm_after last_adr last_commit consecutive_no_progress session_marker"
kfail=0
for k in $keys; do
  if grep -q "\"$k\"" skills/cloop-engine/SKILL.md && grep -q "\"$k\"" test/schemas/state.schema.json; then :; else
    bad "state key missing in SKILL.md or schema: $k"; kfail=1
  fi
done
[ "$kfail" -eq 0 ] && pass "state-key consistency"

# 8. Commit/ADR template structure (deterministic drift guard against the golden shape)
if grep -q 'Why:' skills/cloop-engine/references/commit-templates.md \
   && grep -q 'ADR:' skills/cloop-engine/references/commit-templates.md \
   && grep -q 'Loop:' skills/cloop-engine/references/commit-templates.md \
   && grep -q 'iteration' skills/cloop-engine/references/commit-templates.md; then
  pass "commit template carries Why/ADR/Loop/iteration trail"
else
  bad "commit template missing trail tokens"
fi
if grep -q 'qa_result' skills/cloop-engine/references/adr-template.md \
   && grep -q '## Context' skills/cloop-engine/references/adr-template.md \
   && grep -q '## Decision' skills/cloop-engine/references/adr-template.md; then
  pass "adr template carries qa_result + required sections"
else
  bad "adr template missing required fields"
fi
# golden fixtures parse as the shapes they document
grep -q '^Loop: improve-test-coverage | iteration 7$' test/golden/commit-conventional.txt \
  && pass "golden commit fixture intact" || bad "golden commit fixture drift"

echo "----"
if [ "$fail" -eq 0 ]; then echo "ALL PASS"; else echo "FAILURES PRESENT"; fi
exit "$fail"
