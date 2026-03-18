#!/usr/bin/env bash
# Scoring rubric for berserk-skills agent quality
# Metric: total score (higher is better), max 100
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXPLORE="$REPO_ROOT/agents/explore.md"
SKILL="$REPO_ROOT/skills/berserk/SKILL.md"
AGENTS_DIR="$REPO_ROOT/agents"

score=0
notes=()

note() { notes+=("  $1"); }

# ─── RAW FIELD RESOLUTION (max 30) ────────────────────────────────────
section_raw=0

# +8: Documents that bare identifiers auto-resolve to $raw (permissive mode)
if grep -qiE '(auto[- ]?project|auto[- ]?resolv|permissive|bare.*(identif|field|name).*resolv|resolv.*\$raw)' "$EXPLORE"; then
    section_raw=$((section_raw + 8))
    note "+8  documents auto-projection / permissive resolution"
else
    note " 0  MISSING: auto-projection / permissive resolution docs"
fi

# +7: Documents the `annotate` operator for type hints on dynamic fields
if grep -qiE 'annotate.*(:real|:int|:long|:string|type.hint)' "$EXPLORE"; then
    section_raw=$((section_raw + 7))
    note "+7  documents annotate operator for type hints"
else
    note " 0  MISSING: annotate operator documentation"
fi

# +8: Advises against unnecessary $raw usage
if grep -qiE '(avoid|don.t|do not|unnecessary|rarely need|should not).*\$raw' "$EXPLORE"; then
    section_raw=$((section_raw + 8))
    note "+8  advises against unnecessary \$raw"
else
    note " 0  MISSING: guidance to avoid unnecessary \$raw"
fi

# +7: Example queries prefer bare field names over $raw.field
raw_in_examples=$(grep -cE '\$raw\.' "$EXPLORE" 2>/dev/null || true)
if [ "$raw_in_examples" -le 3 ]; then
    section_raw=$((section_raw + 7))
    note "+7  examples use bare fields (only $raw_in_examples \$raw refs)"
else
    penalty=$((raw_in_examples - 3))
    earned=$((7 - penalty > 0 ? 7 - penalty : 0))
    section_raw=$((section_raw + earned))
    note "+$earned  $raw_in_examples \$raw refs in examples (target ≤3)"
fi

score=$((score + section_raw))
echo "Raw Field Resolution: $section_raw / 30"

# ─── QUERY EFFICIENCY (max 30) ────────────────────────────────────────
section_eff=0

# +10: Has decision tree / conditional logic for when to skip discovery
if grep -qiE '(skip.*discover|already know|if you know|when.*schema.*known|shortcut|fast[- ]?path)' "$EXPLORE"; then
    section_eff=$((section_eff + 10))
    note "+10 has fast-path / skip-discovery guidance"
else
    note " 0  MISSING: fast-path guidance to skip unnecessary discovery"
fi

# +10: Documents combined discovery (otel-log-stats replaces multiple fieldstats)
if grep -qiE '(combines?|replaces?|instead of|single.*(query|step).*schema|one.*(query|step))' "$EXPLORE"; then
    section_eff=$((section_eff + 10))
    note "+10 documents combined discovery shortcuts"
else
    note " 0  MISSING: combined discovery documentation"
fi

# +10: Recommends minimum discovery steps (not a 6-step mandatory sequence)
# Count how many "### Step N" headers exist in the workflow
step_count=$(grep -cE '^### Step [0-9]' "$EXPLORE" 2>/dev/null || true)
if [ "$step_count" -le 3 ]; then
    section_eff=$((section_eff + 10))
    note "+10 streamlined workflow ($step_count mandatory steps)"
elif [ "$step_count" -le 4 ]; then
    section_eff=$((section_eff + 5))
    note "+5  workflow has $step_count steps (target ≤3)"
else
    note " 0  workflow has $step_count mandatory steps (target ≤3)"
fi

score=$((score + section_eff))
echo "Query Efficiency: $section_eff / 30"

# ─── OTEL SPECIALIZATION (max 20) ─────────────────────────────────────
section_otel=0

# +7: Dedicated OTEL log exploration agent or major section
otel_log_agent=$(find "$AGENTS_DIR" -name '*log*' -o -name '*otel-log*' 2>/dev/null | head -1)
if [ -n "$otel_log_agent" ]; then
    section_otel=$((section_otel + 7))
    note "+7  dedicated OTEL log agent exists"
elif grep -qiE '## .*log.*(explor|workflow|investigat|agent)' "$EXPLORE"; then
    section_otel=$((section_otel + 4))
    note "+4  has log-specific section (no dedicated agent)"
else
    note " 0  MISSING: OTEL log specialization"
fi

# +7: Dedicated OTEL trace exploration agent or major section
otel_trace_agent=$(find "$AGENTS_DIR" -name '*trace*' -o -name '*otel-trace*' 2>/dev/null | head -1)
if [ -n "$otel_trace_agent" ]; then
    section_otel=$((section_otel + 7))
    note "+7  dedicated OTEL trace agent exists"
elif grep -qiE '## .*trace.*(explor|workflow|investigat|agent)' "$EXPLORE"; then
    section_otel=$((section_otel + 4))
    note "+4  has trace-specific section (no dedicated agent)"
else
    note " 0  MISSING: OTEL trace specialization"
fi

# +6: Dedicated OTEL metrics exploration agent or major section
otel_metric_agent=$(find "$AGENTS_DIR" -name '*metric*' -o -name '*otel-metric*' 2>/dev/null | head -1)
if [ -n "$otel_metric_agent" ]; then
    section_otel=$((section_otel + 6))
    note "+6  dedicated OTEL metrics agent exists"
elif grep -qiE '## .*metric.*(explor|workflow|investigat|agent)' "$EXPLORE"; then
    section_otel=$((section_otel + 3))
    note "+3  has metrics-specific section (no dedicated agent)"
else
    note " 0  MISSING: OTEL metrics specialization"
fi

score=$((score + section_otel))
echo "OTEL Specialization: $section_otel / 20"

# ─── CONCISENESS & ROUTING (max 20) ───────────────────────────────────
section_conc=0

# +10: Total line count across all agent files (fewer = better, with floor)
total_lines=0
for f in "$AGENTS_DIR"/*.md; do
    [ -f "$f" ] && total_lines=$((total_lines + $(wc -l < "$f")))
done
# Ideal: ≤400 total lines across all agents. Penalty above 600.
if [ "$total_lines" -le 400 ]; then
    section_conc=$((section_conc + 10))
    note "+10 concise agents ($total_lines total lines)"
elif [ "$total_lines" -le 600 ]; then
    earned=$(( 10 - (total_lines - 400) / 20 ))
    earned=$((earned > 0 ? earned : 0))
    section_conc=$((section_conc + earned))
    note "+$earned  agents are $total_lines lines (target ≤400)"
else
    note " 0  agents too verbose: $total_lines lines (target ≤400)"
fi

# +10: Skill routes to specialized agents (not just generic explore)
agent_refs=$(grep -coE 'berserk:(explore|log|trace|metric|otel)' "$SKILL" 2>/dev/null || true)
if [ "$agent_refs" -ge 3 ]; then
    section_conc=$((section_conc + 10))
    note "+10 skill routes to $agent_refs specialized agents"
elif [ "$agent_refs" -ge 2 ]; then
    section_conc=$((section_conc + 5))
    note "+5  skill routes to $agent_refs agents (target ≥3)"
else
    note " 0  skill only routes to $agent_refs agent(s) (target ≥3)"
fi

score=$((score + section_conc))
echo "Conciseness & Routing: $section_conc / 20"

# ─── SUMMARY ──────────────────────────────────────────────────────────
echo ""
echo "Details:"
for n in "${notes[@]}"; do echo "$n"; done
echo ""
echo "TOTAL SCORE: $score / 100"
echo "$score"
