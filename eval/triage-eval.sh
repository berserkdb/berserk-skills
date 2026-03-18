#!/usr/bin/env bash
# Eval script: scores incident-triage.md against 5 incident scenarios.
# Each scenario defines diagnostic steps the agent SHOULD instruct.
# Score = total steps covered / total expected steps * 100
set -euo pipefail

FILE="${1:-agents/incident-triage.md}"
if [[ ! -f "$FILE" ]]; then echo "File not found: $FILE"; exit 1; fi

TOTAL=0
COVERED=0

check() {
  local scenario="$1" step="$2" pattern="$3"
  TOTAL=$((TOTAL + 1))
  if grep -qiP "$pattern" "$FILE"; then
    COVERED=$((COVERED + 1))
  else
    echo "MISS [$scenario] $step"
  fi
}

# === Scenario 1: Telemetry pipeline broken (services up, no data arriving) ===
# The agent MUST distinguish this from "services down"
check "pipeline-break" "check if collector/agent itself has telemetry" "collector|agent.*telem|agent.*log|otel.*(collector|agent)|collector.*health"
check "pipeline-break" "check if ANY source has data during the gap" "any.*(source|service|signal).*during|anything.*ingest|zero.*telemetry.*any|any.*kind.*during"
check "pipeline-break" "look for backlog flush pattern on recovery" "backlog|flush|burst.*recov|cluster.*timestamp|logs.*with.*timestamps.*at.*start"
check "pipeline-break" "consider ingestion pipeline as a cause" "ingest.*pipeline|pipeline.*broken|collection.*pipeline|telemetry.*pipeline|ingest.*fail"
check "pipeline-break" "explicitly list both hypotheses (down vs pipeline)" "down.*pipeline|pipeline.*down|services.*down.*vs|distinguish|telemetry.*gap.*cause|ambig"

# === Scenario 2: All services down simultaneously (cluster event) ===
check "cluster-down" "check for simultaneous shutdown pattern" "simultan|all.*service.*stop|all.*service.*down|cluster.*event|within.*seconds"
check "cluster-down" "check kubernetes events/history" "kubectl|kubernetes.*event|pod.*event|k8s.*event"
check "cluster-down" "check for node-level events" "node.*event|node.*drain|node.*shutdown|involvedObject.*Node"
check "cluster-down" "check rollout/deployment history" "rollout.*history|deployment.*history|kubectl.*rollout"
check "cluster-down" "check pod restart counts" "restart.*count|pod.*restart|last.*state|OOMKill"

# === Scenario 3: Single service degradation (one service erroring) ===
check "single-svc" "isolate affected service by error rate" "error.*rate.*by.*service|service.*error|affected.*service"
check "single-svc" "check service version changes" "version|deploy|service.version|make_set.*version"
check "single-svc" "find source code for error messages" "source.*code|grep.*code|working.*directory|Grep.*substring|find.*code.*produc"

# === Scenario 4: Partial outage (some services up, some down) ===
check "partial" "compare which services have telemetry vs not" "which.*service|per.*service|service.*telem|each.*service"
check "partial" "check for dependency failures" "depend|downstream|upstream|cascade"
check "partial" "check service-to-service communication" "service.*commun|inter.*service|call.*between|client.*server"

# === Scenario 5: Deployment-caused gap (rolling restart with brief gap) ===
check "deploy-gap" "check for version changes across the gap" "version.*before.*after|version.*gap|version.*change|new.*version|different.*build"
check "deploy-gap" "check for rolling update patterns" "rolling.*update|rolling.*restart|old.*pod.*new.*pod|coexist"
check "deploy-gap" "check gap duration is consistent with deployment" "duration.*deploy|minutes.*restart|brief.*gap|expected.*time"
check "deploy-gap" "look at cold-start errors after restart" "cold.*start|transient.*error.*restart|startup.*error|warm"

# === Scenario 6: Ambiguous gap — agent must NOT jump to conclusions ===
check "no-premature" "warn against assuming services down from telemetry absence alone" "do not assume|don.t assume|must not.*conclude|cannot.*conclude|absence.*not.*proof|ambiguous"
check "no-premature" "present multiple hypotheses when evidence is inconclusive" "both.*hypothes|multiple.*hypothes|two.*possib|either.*or|ambig.*state"
check "no-premature" "recommend external verification when telemetry alone is insufficient" "external.*monitor|outside.*berserk|kubernetes.*pod.*history|recommend.*check|manual.*verif|gap.*in.*summary"

# === Scenario 7: Recovery pattern analysis ===
check "recovery" "analyze first logs after gap for restart indicators" "first.*log.*after|log.*after.*gap|resume.*mid.*operation|first.*telemetry"
check "recovery" "check for version differences before vs after gap" "version.*before|version.*after|compare.*version"
check "recovery" "note whether services resumed mid-operation or fresh" "mid.*operation|clean.*restart|fresh.*start|resume"

# === Scenario 8: Duration-based reasoning ===
check "duration" "flag unusually long gaps as suspicious" "long.*gap|hours.*not.*normal|maintenance.*window|stuck.*deploy|unusually.*long"
check "duration" "compare gap duration to expected deployment time" "minutes.*restart|typically.*complete|expected.*duration|rolling.*update.*minutes|much.*longer"

# === Scenario 9: Agent should check per-service telemetry boundaries ===
check "boundaries" "check last/first timestamp per service around gap" "last.*log.*before|first.*log.*after|last.*telemetry|earliest.*telemetry|boundary|per.*service.*time"
check "boundaries" "detect if all services stopped within a narrow window" "within.*second|narrow.*window|simultaneously|same.*time.*bucket"

# === Scenario 10: Decision tree clarity ===
check "decision-tree" "provide a decision framework or flowchart" "decision.*framework|decision.*tree|flowchart|if.*then.*else|diagnostic.*step"
check "decision-tree" "distinguish at least 3 gap causes (down, pipeline, deployment)" "services.*down|pipeline.*broken|deploy|partial.*outage|rolling"

# === Scenario 11: Specific diagnostic queries the agent should know ===
check "queries" "query to find last/first timestamp per service" "min.*time.*by.*service|max.*time.*by.*service|earliest.*by.*svc|latest.*by.*svc|last.*per.*service|first.*per.*service"
check "queries" "query to check total telemetry volume during gap window" "count.*during.*gap|total.*during|any.*telemetry.*during|count.*by.*bin.*gap"
check "queries" "query to compare service versions before and after" "version.*before.*gap|version.*after.*gap|versions.*before|versions.*after"

# === Scenario 12: Per-service gap boundary timing (the key diagnostic) ===
check "gap-timing" "query last timestamp per service before gap" "max.*time.*by.*svc|last.*timestamp.*per.*service|latest.*per.*service|last.*time.*each|summarize.*max.*time.*by"
check "gap-timing" "query first timestamp per service after gap" "min.*time.*by.*svc|first.*timestamp.*per.*service|earliest.*per.*service|first.*time.*each|summarize.*min.*time.*by"

# === Score ===
if [[ $TOTAL -eq 0 ]]; then
  echo "0"
  exit 0
fi
SCORE=$(python3 -c "print(round($COVERED * 100 / $TOTAL, 1))")
echo ""
echo "=== Triage Eval Score ==="
echo "Covered: $COVERED / $TOTAL"
echo "Score: $SCORE"
