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

### The `search` operator

`search "term"` as the **first** operator scans **every table**, so you do not need to know (or
look up) which table holds the data — that is what makes it the right way to open an
investigation. Each row carries a `$table` column naming its source table:

```bash
bzrk -P <profile> search 'search "connection refused" | summarize n=count() by table=$table' --since "1h ago" --desc "which tables log this"
```

Narrow it once you know where to look: `search in (T1, T2) "term"`, or `<table> | search "term"`
mid-pipeline. `search` also spans **all columns**, so a row can match on a field you were not
thinking about — `scope_name`, a resource attribute, an attribute value — not only `body`.

**Whole terms, not substrings.** `search "x"` lowers to `has "x"`: a case-insensitive literal
match that must sit on **term boundaries**. A boundary is any non-alphanumeric character (or the
start/end of the value), so `_`, `-`, `.`, `/`, `:` and whitespace all delimit — the same rule
Microsoft Kusto uses. Nothing is stemmed, and the lookup string is matched literally rather than
re-tokenized:

| Query                        | in `rewrite_journal_sweeper` | in `Found rewrite journals` | in `journal-sweeper`   |
| ---------------------------- | ---------------------------- | --------------------------- | ---------------------- |
| `search "journal"`           | ✅ `_` delimits              | ❌ the term is `journals`   | ✅ `-` delimits        |
| `search "journals"`          | ❌                           | ✅                          | ❌                     |
| `search "journal_sweeper"`   | ✅                           | ❌                          | ❌ literal `_` ≠ `-`   |
| `search "journal*"`          | ✅                           | ✅ `*` → `hasprefix`        | ✅                     |

Wildcards: `"pre*"` → `hasprefix`, `"*suf"` → `hassuffix`, `"*mid*"` → `contains`, and bare
`search "*"` matches every row.

**An empty full-text result is usually a plural or delimiter mismatch, not missing data.** Retry
with the exact term or a `*` wildcard before suspecting the emitter or the pipeline.

### Common options

| Option        | Description                               |
| ------------- | ----------------------------------------- |
| `--json`      | Output as JSON                            |
| `--csv`       | Output as CSV                             |
| `--since`     | Start time (default: "1h ago")            |
| `--until`     | End time (default: "now")                 |
| `--stats`     | Show execution statistics                 |
| `--timeout`   | Query timeout in seconds (default: 300)   |
| `--agent`     | Enable agent mode (auto-detected usually) |
| `--no-stream` | Print only the completed result           |
| `--desc`      | Short description of WHY the query is run |

### Streaming results (Claude Code Monitor)

`bzrk search` streams **replacement snapshots over the same `--since`/`--until` window**. Each increment is whatever has been scanned so far — more coverage of that window, not a different range. Slice scheduling often starts at the right edge of the grid, but that is not a guarantee (concurrent workers, cache reuse, joins). Never infer "this is the newest data" or "this `min(timestamp)` is global" from an early increment. An increment looks like a finished table; it is only a lower bound (or a partial listing) you can test.

**Do not wait for `# Query Complete` by default.** Arm a Monitor, and on each increment check a **decidable predicate**. If it holds, `kill` the query. Completeness is only required when a partial cannot decide the question.

Write the predicate *before* starting the query. Examples:

- existence: any matching row
- threshold: `n >= 1000`, ingested bytes `>= 10000000`
- newest-N: `take 50` already full

A running `count()` / `sum(bytes)` **can** stop early when the question is a threshold (partial is a lower bound). Exact `min`/`max`/`avg`/`count` over the whole requested window, or absence ("none at all"), cannot.

**Claude Code:** background `bzrk search` (no `--no-stream`). Monitor increment **headers** (`grep --line-buffered`; plain `grep` delays events). Headers do not contain the summarize values — on each `# Increment N`, Read `incremental/PrimaryResult/N.tsv` and evaluate the predicate. Persistent watch (`persistent: true`).

```bash
log=$(mktemp)
bzrk -P <profile> search "<KQL>" --since "<TIME>" --desc "<why>" >"$log" 2>&1 &
echo $! >"${log}.pid"
# Monitor command (headers only — you Read the TSV on each wake):
tail -F "$log" | grep --line-buffered -E '^# (Increment|Query Complete)'
```

On `# Increment N`: Read the TSV → if predicate holds, `kill "$(cat "${log}.pid")"` and treat the result as **partial** (say so). On `# Query Complete` without the predicate firing, that is the final result.

Never treat increment 1 as the answer just because it has a table. `| head` of a streaming run is the same bug.

If Monitor is unavailable, `--no-stream` (final only) — you lose early-stop.

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

**3. Nulls in comparisons — uneven on purpose, and Kleene under negation.** Absent fields read as
null, and null comparisons follow Microsoft Kusto's tiers: against a **concrete value** they are
two-valued (`null == 4` → `false`, `null != 4` → `true` — so `where i != 5` **keeps** null rows);
against **another null** or under **ordering** they are null (`null == null` → null, `null < 4` →
null). A `where` keeps a row only on definitive `true`, and `not`/`and`/`or` are three-valued —
the practical traps:

```
where not(duration > 5s)                       ⚠️ DROPS rows where duration is null (not(null) = null)
where not(duration > 5s) or isnull(duration)   ✅ "not above threshold, or unknown"
where x == int(null)                           ❌ never true — not a null check; use isnull(x)
```

**Dynamics compare by the STORED value — never parsed.** `where attrs.status == 500` matches the
*number* 500, not the string `"500"`. This is a deliberate divergence from ADX, which parses and
even truncates (`dynamic(2.5) == long(2)` is true there; false here — `dynamic(2.0) == 2` is true
in both, free numeric widening). If an ADX-idiomatic comparison comes back empty, the stored type
isn't what you assumed: check `gettype(field)` and normalize with `to*()` in a projection, never in
the filter.

> _Rollout note: `=~` pruning is on master (Dev now; Valhalla at the next release after v1.0.118).
> The null/dynamic comparison semantics above land with rustytrace#3436 (in review) — older engines
> two-value everything (`null == null` → `false`, `not(x > 5)` keeps null rows) and evaluate
> `dynamic(4) == 4` as `false`._

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
