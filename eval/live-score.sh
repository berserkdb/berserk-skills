#!/usr/bin/env bash
# Live scoring harness for berserk agent quality
# Tests agent instructions by running queries against valhalla cluster
# Metric: total score (higher is better), max 100
#
# PINNED TIME RANGE: 2026-03-17T18:45:00Z to 2026-03-18T18:45:00Z
# This makes results repeatable against the same data window.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXPLORE="$REPO_ROOT/agents/explore.md"
OTEL_LOG="$REPO_ROOT/agents/otel-log.md"
OTEL_TRACE="$REPO_ROOT/agents/otel-trace.md"
OTEL_METRIC="$REPO_ROOT/agents/otel-metric.md"
SKILL="$REPO_ROOT/skills/berserk/SKILL.md"

BZRK_DIR="$HOME/code/berserk/main"
SINCE="2026-03-17T18:45:00Z"
UNTIL="2026-03-18T18:45:00Z"
PROFILE="valhalla"

score=0
notes=()
note() { notes+=("  $1"); }

bzrk_query() {
    cd "$BZRK_DIR" && bzrk -P "$PROFILE" search "$1" --since "$SINCE" --until "$UNTIL" --desc "$2" 2>/dev/null
}

# Helper: check if agent file contains a pattern (case-insensitive)
agent_has() {
    local file="$1" pattern="$2"
    grep -qiE "$pattern" "$file" 2>/dev/null
}

# ─── TASK 1: ERROR DIAGNOSIS (max 20) ─────────────────────────────────
# Question: "What are the top error patterns and which services produce them?"
# Expected: Use log_template_hash + extract_log_template grouped by service
# Known answers: "FATAL: query thread exiting with error" (1078), query service has 2597 errors
task1=0

# +5: Agent docs show log_template_hash/extract_log_template usage
if agent_has "$OTEL_LOG" 'log_template_hash'; then
    task1=$((task1 + 5))
    note "+5  T1: otel-log agent has log_template_hash"
else
    note " 0  T1: MISSING log_template_hash in otel-log agent"
fi

# +5: Agent docs show grouping errors by service
if agent_has "$OTEL_LOG" "resource.attributes\['service.name'\].*ERROR|ERROR.*resource.attributes\['service.name'\]"; then
    task1=$((task1 + 5))
    note "+5  T1: otel-log shows service+error filtering pattern"
else
    note " 0  T1: MISSING service+error filtering pattern"
fi

# +5: Live query — error pattern query returns expected top pattern
result=$(bzrk_query "default | where isnotnull(body) | where severity_text == 'ERROR' or severity_text == 'error' | summarize sample=take_any(tostring(body)), count=count() by hash=log_template_hash(tostring(body)) | extend pattern=extract_log_template(sample) | project pattern, count | top 5 by count desc" "T1: error patterns" | grep -c "FATAL\|query thread\|Failed to send" || true)
if [ "$result" -ge 2 ]; then
    task1=$((task1 + 5))
    note "+5  T1: live query found $result expected error patterns"
else
    note " 0  T1: live query found only $result expected patterns (need ≥2)"
fi

# +5: Agent docs mention severity_number as alternative to severity_text
if agent_has "$OTEL_LOG" 'severity_number' || agent_has "$EXPLORE" 'severity_number'; then
    task1=$((task1 + 5))
    note "+5  T1: docs mention severity_number"
else
    note " 0  T1: MISSING severity_number reference (some services use lowercase severity_text)"
fi

score=$((score + task1))
echo "Task 1 (Error Diagnosis): $task1 / 20"

# ─── TASK 2: LATENCY INVESTIGATION (max 20) ───────────────────────────
# Question: "Which services have the worst p99 latency for incoming requests?"
# Expected: Use percentile() with totimespan conversion, annotate for dynamic fields
# Known answer: ui-server p99 ~168s, query p99 ~20s, meta p99 ~11ms
task2=0

# +5: Agent docs show percentile() function usage
if agent_has "$OTEL_TRACE" 'percentile'; then
    task2=$((task2 + 5))
    note "+5  T2: otel-trace agent mentions percentile"
else
    note " 0  T2: MISSING percentile in otel-trace agent"
fi

# +5: Agent docs show totimespan or annotate for dynamic duration field
if agent_has "$OTEL_TRACE" 'totimespan|annotate.*duration|duration.*annotate'; then
    task2=$((task2 + 5))
    note "+5  T2: docs show duration type conversion"
else
    note " 0  T2: MISSING duration type conversion guidance"
fi

# +5: Live query — percentile query returns ui-server as worst p99
result=$(bzrk_query "default | where isnotnull(\$time_end) | where name == 'incoming_request' | extend dur_ms = totimespan(duration) / 1ms | summarize p99=percentile(dur_ms, 99) by tostring(resource.attributes['service.name']) | top 1 by p99 desc" "T2: worst p99 latency" | grep -c "ui-server" || true)
if [ "$result" -ge 1 ]; then
    task2=$((task2 + 5))
    note "+5  T2: live query correctly identified ui-server as worst p99"
else
    note " 0  T2: live query did not find ui-server as worst p99"
fi

# +5: Agent docs show the pattern for slow span investigation (top N by duration)
if agent_has "$OTEL_TRACE" 'top.*duration|duration.*desc'; then
    task2=$((task2 + 5))
    note "+5  T2: docs show top-by-duration pattern"
else
    note " 0  T2: MISSING top-by-duration slow span pattern"
fi

score=$((score + task2))
echo "Task 2 (Latency Investigation): $task2 / 20"

# ─── TASK 3: TRACE CORRELATION (max 15) ───────────────────────────────
# Question: "Given a slow trace, show all spans to find the bottleneck"
# Expected: Filter by trace_id, project useful fields, order by $time
# Known: trace 06f9c5bb5cf9c0194a04a74c32fb5345 has a 46-min execute_query span
task3=0

# +5: Agent shows trace_id based drill-down pattern
if agent_has "$OTEL_TRACE" "trace_id.*==|where trace_id"; then
    task3=$((task3 + 5))
    note "+5  T3: otel-trace shows trace_id drill-down"
else
    note " 0  T3: MISSING trace_id drill-down pattern"
fi

# +5: Live query — trace drill-down returns spans ordered by time
result=$(bzrk_query "default | where trace_id == '06f9c5bb5cf9c0194a04a74c32fb5345' | project name, \$time, \$time_end, duration, span_id, parent_span_id, resource.attributes['service.name'] | order by \$time asc" "T3: trace drill-down" | grep -c "execute_query\|incoming_request" || true)
if [ "$result" -ge 1 ]; then
    task3=$((task3 + 5))
    note "+5  T3: live trace drill-down found expected spans ($result matches)"
else
    note " 0  T3: live trace drill-down failed to find expected spans"
fi

# +5: Agent shows parent_span_id in trace projection (needed to reconstruct tree)
if agent_has "$OTEL_TRACE" 'parent_span_id'; then
    task3=$((task3 + 5))
    note "+5  T3: trace pattern includes parent_span_id"
else
    note " 0  T3: MISSING parent_span_id in trace projection"
fi

score=$((score + task3))
echo "Task 3 (Trace Correlation): $task3 / 15"

# ─── TASK 4: METRIC ANALYSIS (max 15) ─────────────────────────────────
# Question: "What histogram metrics exist and what are the busiest endpoints?"
# Expected: Query histogram data with bucket_counts/explicit_bounds
# Known: server.request.duration is a histogram with 100k+ data points
task4=0

# +5: Agent docs show histogram-specific fields (bucket_counts, explicit_bounds)
if agent_has "$OTEL_METRIC" 'bucket_counts|explicit_bounds'; then
    task4=$((task4 + 5))
    note "+5  T4: otel-metric mentions histogram fields"
else
    note " 0  T4: MISSING histogram fields (bucket_counts, explicit_bounds)"
fi

# +5: Live query — metric discovery finds server.request.duration as top metric
result=$(bzrk_query "default | where isnotnull(metric.name) | summarize cnt=count() by metric.name | top 3 by cnt desc" "T4: top metrics" | grep -c "server.request.duration" || true)
if [ "$result" -ge 1 ]; then
    task4=$((task4 + 5))
    note "+5  T4: live query found server.request.duration as top metric"
else
    note " 0  T4: live query did not find server.request.duration"
fi

# +5: Agent docs show annotate with :real for metric value aggregation
if agent_has "$OTEL_METRIC" 'annotate.*value:real|annotate.*:real'; then
    task4=$((task4 + 5))
    note "+5  T4: docs show annotate value:real for metric aggregation"
else
    note " 0  T4: MISSING annotate value:real pattern"
fi

score=$((score + task4))
echo "Task 4 (Metric Analysis): $task4 / 15"

# ─── TASK 5: VOLUME & TREND ANALYSIS (max 15) ─────────────────────────
# Question: "Which service had the biggest spike in trace volume?"
# Expected: Use bin($time, 1h) with summarize count() to find volume trends
# Known: janitor spiked from ~2k to ~72k traces/hr between 16:00-17:00
task5=0

# +5: Agent docs show bin() for time-series bucketing
if agent_has "$EXPLORE" 'bin.*\$time|bin.*time' || agent_has "$OTEL_TRACE" 'bin.*\$time'; then
    task5=$((task5 + 5))
    note "+5  T5: docs show bin() for time-series"
else
    note " 0  T5: MISSING bin() time-series bucketing"
fi

# +5: Live query — hourly volume identifies janitor spike
result=$(bzrk_query "default | where isnotnull(\$time_end) | where resource.attributes['service.name'] == 'janitor' | summarize cnt=count() by bin(\$time, 1h) | top 1 by cnt desc" "T5: janitor spike" | grep -oP '\d+' | tail -1 || true)
if [ -n "$result" ] && [ "$result" -gt 30000 ]; then
    task5=$((task5 + 5))
    note "+5  T5: live query found janitor spike ($result traces in peak hour)"
else
    note " 0  T5: live query did not find janitor volume spike (got: ${result:-empty})"
fi

# +5: Agent shows make-series or time-based summarize for trend detection
if agent_has "$EXPLORE" 'make-series|bin.*1h|bin.*5m|bin.*1m' || agent_has "$OTEL_METRIC" 'bin.*1m|bin.*5m|bin.*1h'; then
    task5=$((task5 + 5))
    note "+5  T5: docs show time-bucketed aggregation patterns"
else
    note " 0  T5: MISSING time-bucketed aggregation patterns"
fi

score=$((score + task5))
echo "Task 5 (Volume & Trend Analysis): $task5 / 15"

# ─── TASK 6: FUNCTION COVERAGE (max 15) ───────────────────────────────
# Score based on variety of KQL functions referenced across all agent files
task6=0
all_agents="$EXPLORE $OTEL_LOG $OTEL_TRACE $OTEL_METRIC"

functions_found=0
# Aggregation functions
for fn in "percentile" "dcount" "avg\b" "count()" "take_any" "arg_max|arg_min" "make_list|make_set|collect"; do
    if grep -qiE "$fn" $all_agents 2>/dev/null; then
        functions_found=$((functions_found + 1))
    fi
done
# Scalar functions
for fn in "totimespan|todatetime|tostring|toint|toreal|tolong" "extract\b|extract_all" "case\(|iff\(" "coalesce" "strcat|strlen|substring" "parse_json|parse_url|bag_keys" "bin\(|bin_at" "format_datetime|format_timespan"; do
    if grep -qiE "$fn" $all_agents 2>/dev/null; then
        functions_found=$((functions_found + 1))
    fi
done
# Tabular operators
for fn in "annotate " "mv-expand|mv-apply" "search " "fieldstats" "otel-log-stats" "log_template_hash|extract_log_template"; do
    if grep -qiE "$fn" $all_agents 2>/dev/null; then
        functions_found=$((functions_found + 1))
    fi
done

# 21 total function groups checked. Score: 1 point per function, max 15
task6=$((functions_found > 15 ? 15 : functions_found))
note "+$task6  T6: $functions_found / 21 function groups covered"

score=$((score + task6))
echo "Task 6 (Function Coverage): $task6 / 15"

# ─── SUMMARY ──────────────────────────────────────────────────────────
echo ""
echo "Details:"
for n in "${notes[@]}"; do echo "$n"; done
echo ""
echo "TOTAL SCORE: $score / 100"
echo "$score"
