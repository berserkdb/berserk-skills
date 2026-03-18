#!/usr/bin/env bash
# E2E eval: spawns the incident-triage agent against a known incident,
# then scores whether it reaches the correct conclusions.
#
# Ground truth (2026-03-18 telemetry gap):
# 1. Services were UP (not down)
# 2. The OTel collector/pipeline was the problem
# 3. The collector deadlocked/froze (not crashed)
# 4. block_on_overflow or queue-related config caused it
# 5. tjalfe was involved (scaled to 0, or exporter interaction)
#
# Score: number of correct conclusions (0-5)
set -euo pipefail

AGENT_PROMPT_FILE="${1:-agents/incident-triage.md}"
OUTFILE="/tmp/triage-eval-output-$$.txt"
SCORE=0

if [[ ! -f "$AGENT_PROMPT_FILE" ]]; then
  echo "Agent prompt not found: $AGENT_PROMPT_FILE"
  exit 1
fi

AGENT_PROMPT=$(cat "$AGENT_PROMPT_FILE")

echo ">>> Spawning triage agent (this takes 2-5 minutes)..."

# Run the triage agent non-interactively with the incident prompt
claude -p \
  --model opus \
  --append-system-prompt "$AGENT_PROMPT" \
  --allowedTools "Bash(bzrk:*) Bash(kubectl:*)" \
  --max-budget-usd 1.00 \
  --dangerously-skip-permissions \
  "Investigate why there was a telemetry gap for the nursery service (and potentially other services) on 2026-03-18. The gap appears to be from roughly 2026-03-17 21:46Z to 2026-03-18 13:45Z. All services had zero telemetry during this period. Determine the root cause — were services down, or was something else going on? Present your findings." \
  > "$OUTFILE" 2>&1

echo ">>> Agent output captured ($(wc -l < "$OUTFILE") lines)"
echo ">>> Scoring against ground truth..."

OUTPUT=$(cat "$OUTFILE")

# Scoring function
check_conclusion() {
  local name="$1" pattern="$2"
  if echo "$OUTPUT" | grep -qiP "$pattern"; then
    SCORE=$((SCORE + 1))
    echo "  PASS [$name]"
  else
    echo "  MISS [$name]"
  fi
}

# 1. Services were UP
check_conclusion "services-up" \
  "services.*(were|was|kept|still|actually).*(up|running|alive|operational)|not.*actually.*down|were not down|pipeline.*(broke|broken|failed|issue)|telemetry.*(pipeline|collection).*(broke|broken|failed|issue)"

# 2. OTel collector/pipeline was the problem
check_conclusion "collector-problem" \
  "collector.*(deadlock|froze|stall|block|hung|silent|problem|issue|cause|fail)|pipeline.*(deadlock|froze|stall|block|broke|broken|fail)|otel.*(collector|agent).*(problem|issue|cause|fail|deadlock|froze)"

# 3. Collector deadlocked/froze (not crashed — same instance)
check_conclusion "deadlock-not-crash" \
  "deadlock|froze|frozen|stall|hung|block.*overflow|blocked.*goroutine|same.*instance|did.*not.*crash|didn.*crash|not.*restart"

# 4. block_on_overflow or queue config
check_conclusion "queue-config" \
  "block.on.overflow|queue.*full|queue.*size|queue.*overflow|queue.*block|exporter.*queue|queue.*capac"

# 5. tjalfe involvement
check_conclusion "tjalfe" \
  "tjalfe.*(scaled|down|replica|involved|exporter|interact|cause|alongside|fail|crash|died)|tjalfe"

echo ""
echo "=== E2E Triage Eval Score ==="
echo "Score: $SCORE / 5"
echo "Output file: $OUTFILE"
echo "$SCORE"
