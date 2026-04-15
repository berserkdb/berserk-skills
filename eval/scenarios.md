# Test Scenarios for Agent Quality

Reference scenarios the agent should handle efficiently. Use these during iteration to validate that changes improve real-world query efficiency.

## Scenario 1: "Find errors in the last hour"
**Ideal query count**: 2 (discover table + query)
**Anti-pattern**: Running fieldstats before a simple error search
**Optimal**:
```bash
bzrk -P prod search ".show tables"
bzrk -P prod search "<table> | where severity_text == 'ERROR' | take 20" --since "1h ago"
```

## Scenario 2: "What services are deployed?"
**Ideal query count**: 2 (discover table + summarize)
**Key**: Use bare `resource['service.name']` — no $raw needed
**Optimal**:
```bash
bzrk -P prod search ".show tables"
bzrk -P prod search "<table> | summarize count() by tostring(resource['service.name']) | order by count_ desc"
```

## Scenario 3: "Investigate slow requests for service X"
**Ideal query count**: 3 (discover + find traces + drill into slow ones)
**Key**: Agent should know to filter traces by end_time and use duration, not run fieldstats first

## Scenario 4: "What's causing the spike in errors?"
**Ideal query count**: 3 (discover + otel-log-stats + log_template patterns)
**Key**: otel-log-stats gives service+severity breakdown in ONE query, skip separate fieldstats

## Scenario 5: "Show me metrics for service X"
**Ideal query count**: 3 (discover + list metric names + query specific metric)
**Key**: Should go straight to metric_name filter, not explore entire schema

## Scenario 6: "Unfamiliar instance — explore everything"
**Ideal query count**: 4 (discover + fieldstats depth=1 + otel-log-stats + targeted query)
**Key**: This is the ONLY scenario where full discovery is warranted

## Raw Field Resolution Principles
- Bare field names auto-resolve to $raw properties (permissive mode default)
- `where level == "INFO"` works — no need for `where $raw.level == "INFO"`
- Use `annotate response_time:real` when doing arithmetic on auto-projected fields
- Only use explicit $raw when processing the full JSON blob via jq on TSV files
- Bracket notation `resource['service.name']` is preferred for dotted OTel keys
