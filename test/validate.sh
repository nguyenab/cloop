#!/usr/bin/env bash
# cloop deterministic test gate. Run from anywhere; operates on the repo root.
# Test/build tooling only (not the plugin runtime). POSIX dev env: macOS, or Git Bash/WSL on Windows.
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0
pass(){ printf 'PASS  %s\n' "$1"; }
bad(){ printf 'FAIL  %s\n' "$1"; fail=1; }

# 1. Both manifests validate on their own paths (a co-located marketplace.json makes
#    `claude plugin validate ./` check only the marketplace).
if command -v claude >/dev/null 2>&1; then
  claude plugin validate ./.claude-plugin/marketplace.json --strict >/dev/null 2>&1 \
    && pass "validate marketplace --strict" || bad "validate marketplace --strict"
  claude plugin validate ./.claude-plugin/plugin.json --strict >/dev/null 2>&1 \
    && pass "validate plugin --strict" || bad "validate plugin --strict"
else
  printf 'SKIP  claude CLI not found\n'
fi

# 2. JSON (manifests + schemas) is valid
for j in .claude-plugin/plugin.json .claude-plugin/marketplace.json \
         test/schemas/state.schema.json test/schemas/config.schema.json; do
  python3 -m json.tool "$j" >/dev/null 2>&1 && pass "json valid: $j" || bad "json invalid: $j"
done

# 3. Every command + skill begins with --- and has name + description
while IFS= read -r f; do
  if [ "$(sed -n '1p' "$f")" = "---" ] && grep -q '^name:' "$f" && grep -q '^description:' "$f"; then
    pass "frontmatter: $f"; else bad "frontmatter: $f"; fi
done < <( { ls commands/*.md 2>/dev/null; find skills -name 'SKILL.md'; } )

# 4. The internal iterate command stays non-interactive
if grep -q 'user-invocable: false' commands/cloop-iterate.md \
   && grep -q 'disallowed-tools' commands/cloop-iterate.md \
   && grep -q 'AskUserQuestion' commands/cloop-iterate.md; then
  pass "iterate stays non-interactive"; else bad "iterate stays non-interactive"; fi

# 5. Every ${CLAUDE_PLUGIN_ROOT}/... reference resolves to a real file
while IFS= read -r ref; do
  rel=$(printf '%s' "$ref" | sed 's#${CLAUDE_PLUGIN_ROOT}/##')
  [ -f "$rel" ] && pass "ref: $rel" || bad "missing ref: $rel"
done < <(grep -rhoE '\$\{CLAUDE_PLUGIN_ROOT\}/[A-Za-z0-9._/-]+' commands skills | sort -u)

# 5b. No reference file is cited by bare name (must carry the ${CLAUDE_PLUGIN_ROOT} prefix)
if grep -rnE '`(plan-template|adr-template|commit-templates|roles|interview|SKILL)\.md`' commands skills \
     | grep -vF '${CLAUDE_PLUGIN_ROOT}' >/dev/null 2>&1; then
  bad "bare reference-file path (missing \${CLAUDE_PLUGIN_ROOT})"
  grep -rnE '`(plan-template|adr-template|commit-templates|roles|interview|SKILL)\.md`' commands skills | grep -vF '${CLAUDE_PLUGIN_ROOT}'
else
  pass "no bare reference-file paths"
fi

# 6. No placeholder markers in shipped prose
targets="commands skills"; [ -f README.md ] && targets="$targets README.md"
if grep -RInE 'TODO|TBD|FIXME' $targets >/dev/null 2>&1; then
  bad "placeholder markers present"; grep -RInE 'TODO|TBD|FIXME' $targets
else pass "no TODO/TBD/FIXME"; fi

# 7. State keys are consistent between SKILL.md and the state schema
kfail=0
for k in slug status iteration mode interval max_iterations roles commit_style criteria_ref cron_job_id started_at last_adr; do
  grep -q "\"$k\"" skills/cloop-engine/SKILL.md && grep -q "\"$k\"" test/schemas/state.schema.json || { bad "state key drift: $k"; kfail=1; }
done
[ "$kfail" -eq 0 ] && pass "state-key consistency"

# 8. Templates and golden fixtures keep their shape
grep -q 'Why:' skills/cloop-engine/references/commit-templates.md \
  && grep -q 'ADR:' skills/cloop-engine/references/commit-templates.md \
  && grep -q 'cloop:' skills/cloop-engine/references/commit-templates.md \
  && pass "commit template carries Why/ADR/cloop trailer" || bad "commit template trailer"
grep -q 'qa:' skills/cloop-engine/references/adr-template.md \
  && grep -q '## Context' skills/cloop-engine/references/adr-template.md \
  && grep -q '## Decision' skills/cloop-engine/references/adr-template.md \
  && pass "adr template carries qa + sections" || bad "adr template fields"
grep -q 'interval' skills/cloop-engine/references/plan-template.md \
  && grep -q 'max_iterations' skills/cloop-engine/references/plan-template.md \
  && grep -q 'roles' skills/cloop-engine/references/plan-template.md \
  && pass "plan template carries interval + max_iterations + roles" || bad "plan template fields"
[ -f skills/cloop-engine/references/roles.md ] && pass "roles reference present" || bad "roles reference missing"
grep -q '^cloop: improve-tests iteration 7$' test/golden/commit-conventional.txt \
  && grep -q '^ADR: ' test/golden/commit-conventional.txt \
  && pass "golden commit fixture intact" || bad "golden commit fixture drift"

# 9. Quota parser reproduces the golden expectation from the captured fixture
if awk -f skills/cloop-engine/references/quota-parse.awk test/golden/quota-fixture.txt \
     | diff -q - test/golden/quota-parse-expected.txt >/dev/null 2>&1; then
  pass "quota parse matches golden"
else
  bad "quota parse drift"
  awk -f skills/cloop-engine/references/quota-parse.awk test/golden/quota-fixture.txt \
    | diff - test/golden/quota-parse-expected.txt
fi

echo "----"
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILURES PRESENT"
exit "$fail"
