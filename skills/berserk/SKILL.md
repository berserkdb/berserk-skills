---
name: berserk
description: |
  Run KQL queries against Berserk using the bzrk CLI. Use this skill whenever:
  (1) Executing KQL queries to search logs, traces, or metrics
  (2) Investigating issues by querying data around specific timestamps
  (3) Debugging problems by examining trace data
  (4) Exploring schema, field distributions, or service topology
  (5) Correlating logs and traces via traceId/spanId

  Make sure to use this skill whenever the user mentions querying observability data, searching logs, investigating traces, looking at metrics, debugging production issues, or exploring telemetry data — even if they don't explicitly mention "Berserk" or "bzrk".

  Triggers: "run bzrk", "query traces", "search logs", "investigate", "look at traces around", "what errors", "check metrics"
---

# Berserk

**Route investigation tasks to the right specialist agent:**

| Task | Agent | When to use |
|------|-------|-------------|
| Incident triage | `berserk:incident-triage` | Something is broken — find root cause across logs, traces, and metrics |
| Trace analysis | `berserk:trace-analysis` | Explain why a request was slow or failed — build cause-and-effect narrative |
| Log investigation | `berserk:otel-log` | Searching errors, log patterns, severity analysis, service log volume |
| Trace investigation | `berserk:otel-trace` | Span queries, latency percentiles, trace correlation, service dependencies |
| Metrics investigation | `berserk:otel-metric` | Metric discovery, time-series queries, histogram analysis, spike detection |
| General exploration | `berserk:explore` | Schema discovery, unfamiliar instances, mixed-signal queries, fieldstats |

Use `berserk:incident-triage` when the user reports a problem ("errors are up", "service is slow", "something broke"). Use `berserk:trace-analysis` when they have a specific trace or slow request to investigate. Use the signal-specific agents for targeted queries. Use `berserk:explore` when the signal type is unknown or the task spans multiple signal types.

**For inline help** (KQL syntax questions, bzrk flag reference), use the quick reference below.

## Quick Reference

### Installation

```bash
curl -fsSL https://go.bzrk.dev | bash
```

### Profiles and tables

Profiles are named configurations pointing to Berserk instances:

```bash
bzrk profile list                # List configured profiles
bzrk -P <profile> search "<KQL>" # Query using a specific profile
```

Discover tables with:

```bash
bzrk -P <profile> search ".show tables"
```

### Query syntax

```bash
bzrk -P <profile> search "<KQL>" --since "<TIME>" [--until "<TIME>"] --desc "<why>"
```

### Common options

| Option      | Description                               |
| ----------- | ----------------------------------------- |
| `--json`    | Output as JSON                            |
| `--csv`     | Output as CSV                             |
| `--since`   | Start time (default: "1h ago")            |
| `--until`   | End time (default: "now")                 |
| `--stats`   | Show execution statistics                 |
| `--timeout` | Query timeout in seconds (default: 300)   |
| `--agent`   | Enable agent mode (auto-detected usually) |
| `--desc`    | Short description of WHY the query is run |

### Time formats

- Relative: `"1h ago"`, `"2d ago"`, `"30m ago"`
- Absolute: `"2024-01-01"`, `"2024-01-01T10:30:00"`
- Special: `"now"`, `"today"`, `"yesterday"`

### Permissive mode

Berserk uses permissive field resolution by default — bare field names automatically resolve without needing a `$raw` prefix:

```
where severity_text == "ERROR"          ✅ works (permissive)
where $raw.severity_text == "ERROR"     ❌ unnecessary
```

For arithmetic on dynamic fields, use `annotate` to declare types:

```
<table> | annotate response_time:real | summarize avg(response_time) by bin($time, 5m)
```

Use bracket notation for OTel attribute keys containing dots:

```
resource.attributes['service.name']     ✅ correct
resource.attributes.service.name        ❌ ambiguous
```

### OTel data structure

Berserk stores logs, traces, and metrics in a **single unified table** as separate rows. Detect signal type by which columns are populated:

| Signal    | Detection                        | Key fields                                                        |
| --------- | -------------------------------- | ----------------------------------------------------------------- |
| **Logs**    | `where isnotnull(body)`          | `body`, `severity_text`, `severity_number`, `attributes`          |
| **Traces**  | `where isnotnull($time_end)`     | `name`, `trace_id`, `span_id`, `parent_span_id`, `duration`, `kind` |
| **Metrics** | `where isnotnull(metric.name)`   | `metric.name`, `metric.type`, `value`, `sum`, `count`            |

Common fields across all signals:

- `$time` — event timestamp
- `resource.attributes['service.name']` — service identifier
- `resource.attributes['service.version']` — deployed version
- `trace_id` — trace correlation (logs and traces)

### Known limitations

`distinct` and `union` (of non-datatable sources) are not yet supported.
