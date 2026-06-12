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

| Task                  | Agent                     | When to use                                                                 |
| --------------------- | ------------------------- | --------------------------------------------------------------------------- |
| Incident triage       | `berserk:incident-triage` | Something is broken — find root cause across logs, traces, and metrics      |
| Trace analysis        | `berserk:trace-analysis`  | Explain why a request was slow or failed — build cause-and-effect narrative |
| Log investigation     | `berserk:otel-log`        | Searching errors, log patterns, severity analysis, service log volume       |
| Trace investigation   | `berserk:otel-trace`      | Span queries, latency percentiles, trace correlation, service dependencies  |
| Metrics investigation | `berserk:otel-metric`     | Metric discovery, time-series queries, histogram analysis, spike detection  |
| General exploration   | `berserk:explore`         | Schema discovery, unfamiliar instances, mixed-signal queries, fieldstats    |

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

Every bag field is `dynamic`. How a `dynamic` is handled depends on **where** it appears, and the
two contexts behave differently on purpose:

**1. Comparisons / scan predicates — compared by native type, never coerced.** A bare
`where field == "x"` works directly on a dynamic field and keeps the segment indexes engaged
(bloom / SHAR / range). **Never wrap a scan predicate in `tostring()` / `tolower()` / `tolong()` / any
function** — it forces per-row evaluation and disables pruning (see _Making queries fast_). A type
that can't match is simply not equal (e.g. a numeric field `== "5"` is `false`, not coerced).

For a **case-insensitive** match use `=~` (and `!~`), never `tolower(field) == "..."`. `=~` is a real
operator that prunes: its chunk bloom is case-folded, so it skips chunks just like `==` — on dynamic
fields too. `==` / `!=` stay case-sensitive.

```
where resource['service.name'] == "query"     ✅ bare — prunes chunks
where level =~ "error"                         ✅ case-insensitive AND prunes (case-folded bloom)
where tolower(level) == "error"                ❌ function in a filter — defeats pruning; use =~
where tostring(resource['service.name']) == "query"   ❌ defeats the index, same result
```

**2. Typed function arguments — auto-coerced via the `asXXX` family (extract-or-null).** When a
dynamic field is passed to a function/operator that expects a concrete type, the binder injects the
matching extractor (`asstring` / `aslong` / `asdouble` / `asdatetime` / …). `asT` **extracts** the
value if it is already that type (or a dynamic carrying it), otherwise yields **null** — it never
converts across types. So bag fields feed typed functions with no explicit cast, _when the stored
value is that type_:

```
extend lvl = tolower(level)                    ✅ asstring(level) extracted, lowered (a projection — for a filter use `level =~ "error"`)
project code = substring(attributes.path, 0, 8) ✅ when path is a string
extend evt = parse_json(body)                  ✅ string → parse; already-structured → passthrough
summarize avg(value) by bin(timestamp, 5m)     ✅ value auto-coerces numeric; timestamp is native datetime
```

**Use an explicit `to*()` only to cross types — and only in `project`/`extend`, never in a filter.**
`asXXX` won't parse a string into a number/datetime (that would reify a new value); when a field is
stored as the "wrong" type you must convert deliberately:

```
extend t = todatetime(attributes.event_time)   // event_time is a STRING → parse it (asdatetime would be null)
extend n = tolong(attributes.count_str)         // numeric stored as a string → parse it
```

If a typed function returns unexpected nulls, the field isn't the type you assumed — check
`gettype(field)`, then add the explicit `to*()` in a projection. Arithmetic on a dynamic numeric
auto-coerces (`value * 2` works); `annotate <col>:real` is still useful to fix a column's type once
up front for a whole pipeline.

Use bracket notation for OTel attribute keys containing dots:

```
resource['service.name']     ✅ correct
resource.service.name        ❌ ambiguous
```

### OTel data structure

Berserk stores logs, traces, and metrics in a **single unified table** as separate rows. Detect signal type by which columns are populated:

| Signal      | Detection                      | Key fields                                                                    |
| ----------- | ------------------------------ | ----------------------------------------------------------------------------- |
| **Logs**    | `where isnotnull(body)`        | `body`, `severity_text`, `severity_number`, `attributes`                      |
| **Traces**  | `where isnotnull(end_time)`    | `span_name`, `trace_id`, `span_id`, `parent_span_id`, `duration`, `span_kind` |
| **Metrics** | `where isnotnull(metric_name)` | `metric_name`, `metric_type`, `value`, `sum`, `count`                         |

Common fields across all signals:

- `timestamp` — event timestamp
- `resource['service.name']` — service identifier
- `resource['service.version']` — deployed version
- `trace_id` — trace correlation (logs and traces)

### Known limitations

`distinct` and `union` (of non-datatable sources) are not yet supported.
