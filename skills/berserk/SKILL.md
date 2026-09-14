---
name: berserk
description: |
  Query Berserk logs, traces and metrics with the bzrk CLI. Use for schema
  discovery, KQL construction, trace/log correlation, metric analysis and
  interpreting streamed results. Includes Berserk KQL extensions and guidance
  for using an available Berserk MCP server alongside the CLI.
---

# Berserk

This skill focuses on how to formulate, run and refine queries with `bzrk`.
The same KQL runs through Berserk MCP's `query` tool. When MCP is connected,
use `list_databases`, `list_tables`, `discover_fields` and `get_docs` for discovery
and current operator documentation. MCP also exposes alerts, workflows,
connections and dashboards; follow its tool contracts for those operations.
MCP is self-contained and does not require this skill or the CLI.

Choose the interface the user requested. CLI profiles and MCP database arguments
are different routing mechanisms: verify that both target the intended data
before comparing results. CLI `--since` has no default; MCP `query.since` defaults
to one hour. MCP timeouts are in milliseconds; CLI `--timeout` is in seconds.

The Claude plugin additionally supplies specialist agents (`berserk:otel-log`,
`berserk:otel-trace`, `berserk:otel-metric`, `berserk:explore`,
`berserk:incident-triage`, `berserk:trace-analysis`). Use them when available and
appropriate; a standalone skill installation does not include these agents.

## How to query

1. Identify the question: existence, a threshold, exact totals, newest events,
   or a relationship across spans. This determines the query and when it can stop.
2. Select the profile and time window. Honor a specified historical interval;
   for an unspecified recent issue start around 30 minutes and widen as needed.
3. Discover tables and fields. Start with leading `search "term"` for an unknown
   error source, or `fieldstats` for unfamiliar structured data. Empty results
   can mean wrong routing, wrong window, a field-type mismatch, or term mismatch.
4. Filter stored fields early, then project, convert or aggregate. Check the
   input signal, stored types, units and metric temporality before interpreting it.
5. Inspect coverage and warnings. Refine the query based on evidence; distinguish
   a sampled listing or threshold witness from a complete answer.

Examples use `T` as a placeholder for a discovered table and `<profile>` for a
configured profile. Replace them before running. Quote KQL as shell data: prefer
single quotes around queries with double-quoted literals; escape literal `$table`
if using shell double quotes. Never let the shell expand KQL expressions.

## Quick Reference

### CLI availability

Check `bzrk --help` and `bzrk search --help` for the installed build's flags.
If the CLI is missing, use an available MCP or report the missing prerequisite.
CLI documentation is available at https://docs.bzrk.dev/.

### Profiles and tables

Profiles are named configurations pointing to Berserk instances:

```bash
bzrk profile list                # List configured profiles
bzrk -P <profile> search "<KQL>" # Query using a specific profile
```

Profiles can be **repo-bound** via a `.bzrk_config` file: such a profile only resolves when bzrk
runs from inside that repository. On `Profile '<name>' not found`, cd into the project directory
and retry before concluding the profile does not exist.

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

| Query                      | in `rewrite_journal_sweeper` | in `Found rewrite journals` | in `journal-sweeper` |
| -------------------------- | ---------------------------- | --------------------------- | -------------------- |
| `search "journal"`         | ✅ `_` delimits              | ❌ the term is `journals`   | ✅ `-` delimits      |
| `search "journals"`        | ❌                           | ✅                          | ❌                   |
| `search "journal_sweeper"` | ✅                           | ❌                          | ❌ literal `_` ≠ `-` |
| `search "journal*"`        | ✅                           | ✅ `*` → `hasprefix`        | ✅                   |

Wildcards: `"pre*"` → `hasprefix`, `"*suf"` → `hassuffix`, `"*mid*"` → `contains`, and bare
`search "*"` matches every row.

**An empty full-text result is usually a plural or delimiter mismatch, not missing data.** Retry
with the exact term or a `*` wildcard before suspecting the emitter or the pipeline.

### Common options

| Option        | Description                               |
| ------------- | ----------------------------------------- |
| `--json`      | Output as JSON                            |
| `--csv`       | Output as CSV                             |
| `--since`     | Start time (no default; pass explicitly)   |
| `--until`     | End time (default: "now")                 |
| `--stats`     | Show execution statistics                 |
| `--timeout`   | Query timeout in seconds (default: 300)   |
| `--agent`     | Enable agent mode (auto-detected usually) |
| `--no-stream` | Print only the completed result           |
| `--desc`      | Short description of WHY the query is run |

### Time bounds and field discovery

A table scan needs a bound on `timestamp` or `ingest_time`; otherwise it fails
with `MissingTimeFilter`. CLI `--since`/`--until`, `--ingest-since`/`--ingest-until`
and in-query bounds intersect. A wider KQL bound cannot widen a narrower CLI
window. Prefer explicit CLI bounds so the requested interval is visible.

```bash
bzrk -P <profile> search 'T | fieldstats with limit=1000 depth=2' --since "30m ago" --desc "discover stored field types"
bzrk -P <profile> search 'T | fieldstats with field="*status*"' --since "30m ago" --desc "find status fields"
bzrk -P <profile> search 'T | sort by timestamp desc | take 50' --since "30m ago" --desc "newest 50 events"
```

`fieldstats` reports paths, types, cardinality and value hints. A sample can miss
rare fields; a field/value glob scans for matching leaves and may scan the whole
window if nothing matches. Widen discovery deliberately, not by removing bounds.

## Data model and query strategy

Logs, traces, and metrics share a table as separate rows. Discover actual table
and field names; an empty discovery result describes only the selected window.
Common fields include `timestamp`, `resource['service.name']`,
`resource['service.version']`, and `trace_id`.

For OTel signal selection, prefer predicates that allow chunk pruning:

- Logs: `where observed_time >= datetime(1970-01-01)`. Fields include `body`,
  `severity_text`, `severity_number`, and `attributes`. `isnotnull(body)` alone
  misses attribute-only logs; require a body only when the task needs one.
- Spans: `where end_time >= datetime(1970-01-01)`. Fields include `span_name`,
  `trace_id`, `span_id`, `parent_span_id`, `duration`, and `span_kind`.
- Metrics: `annotate metric_name:string | where isnotnull(metric_name)`.
  Inspect metric type and temporality before choosing an aggregation.

Choose the window to answer the question. For an unspecified recent issue, start
with `since: "30m ago"`, then widen if needed (3h → 6h → 2d → 7d). For an explicit
historical incident, query that interval directly. Use `since`/`until` parameters
for the scan window; additional KQL time predicates intersect that window.

For an unfamiliar error term, leading `search "term"` searches across tables;
`$table` identifies the source. Search matches whole terms case-insensitively,
not arbitrary substrings: `"journal"` does not match `"journals"`; `"journal*"`
matches a prefix and `"*journal*"` a substring. Narrow to a table and selective
fields once found. `fieldstats` discovers dynamic paths, types and sample values;
use a bounded sample (`with limit=1000`) and field/depth filters for wide data.

Search synonyms as separate terms: `search "ai" or "llm"`, never one quoted blob like `search "ai OR llm"`.

## Berserk KQL essentials

- Bare fields resolve permissively; no `$raw.` prefix is needed. Bracket-quote
  literal OTel keys containing dots: `resource['service.name']`.
- Keep filters on stored fields where possible: `where severity_text == "ERROR"`
  or `where severity_text =~ "error"`. Wrapping fields in `tostring`/`tolower`
  can prevent index pruning. Use `=~` for case-insensitive equality.
- Dynamic comparisons use stored values: numeric `500` differs from string
  `"500"`. Typed function arguments can automatically extract compatible dynamic
  values using the `as*` family; extraction is not string parsing. Inspect
  `gettype(field)` on unexpected nulls. Use `to*` in `extend`/`project` when
  conversion is intended, then filter the converted value if necessary.
- `annotate` declares dynamic field types for subsequent operations:
  `T | annotate value:real | summarize avg(value) by bin(timestamp, 5m)`.
  It also supports nested objects and arrays, e.g.
  `annotate payload:{count:long, tags:[string]}`. Annotations propagate through
  projections. Only dynamic columns can be annotated; a known scalar type is
  rejected. Numeric datetime annotations interpret Unix nanoseconds, while
  timespan annotations interpret 100 ns ticks; annotation is not `as*` extraction
  or string parsing.
- Missing fields are null. `where` keeps only true. Ordering against null and
  its negation are null: `not(duration > 5s)` drops missing durations. Use
  `isnull`/`isnotnull` explicitly when missing data should be included.
- `take N` is an arbitrary subset, not the newest N. For newest results use an
  explicit timestamp ordering. Exact totals, extrema, averages and absence
  require complete coverage; partial counts can prove a threshold, not absence.
  Only `status=complete` means the scan completed without dropped data. Inspect
  `warnings`, `partial_failures`, and sampling/approximation semantics as well;
  scan completion does not make an approximate aggregate exact.

### Timestamp and duration units

Berserk stores datetime/timestamp values as **nanoseconds since the Unix epoch**.
A `timespan` uses **100 ns ticks**: 10,000 ticks = 1 ms; 10,000,000 ticks = 1 s.
Do not apply a nanosecond divisor to a timespan. Prefer typed arithmetic:
`(end_time - timestamp) / 1ms` or `duration / 1ms` for milliseconds, when the
fields have the corresponding datetime/timespan types.

Numeric KQL conversions have a different contract from timestamp storage:
`tolong(datetime)` returns .NET ticks since 0001-01-01, and `todatetime(number)`
expects those ticks. To convert Unix nanoseconds use
`unixtime_nanoseconds_todatetime(value)`, not `todatetime(value)`.
`tolong(timespan)` returns duration ticks; `tolong(duration) / 10000.0` yields ms.
A raw numeric OTel attribute or metric is not necessarily a timespan: discover
its type and unit rather than inferring them from its name.

## Extensions worth using

- **`trace-find`** finds traces through span relationships and correlated logs.
  Example: `T | trace-find { resource['service.name'] == "api" } >> { status_code == "ERROR" }`.
  `>` means child, `>>` descendant, `~` sibling, and `::` correlated log.
  Predicates within one block apply to the same span; separate blocks joined by
  `and` are existence checks anywhere in the trace. A chained relationship is
  evaluated as independent checks, not necessarily one continuous path.
  Default output is one row per matching trace, not raw spans. Its attached
  `summarize` aggregates collected rows of each matching trace, not just the
  predicate matches. `within` (default 5m) controls collection windows, not a
  strict trace-duration filter; long traces need an appropriate window. Keep
  logs in the input when correlating them. Read the trace-find reference for
  structural syntax, collection/early-stop limits, and output clauses.
- **`otel-log-stats`** explores log attributes and patterns in one pass.
- **`otel_rate` / `otel_increase`** handle OTel counters; **`otel_delta`** measures
  signed change. **`otel_histogram_percentile`** merges histogram observations;
  a percentile of histogram sums or averages is not a request percentile.
  Fetch their docs for input columns, temporality, grouping and sample needs.
- **`events[*].name`** can filter array elements without `mv-expand`; consult
  the relevant docs before assuming multiple predicates match the same element.
- **`fork`** shares a source scan across branches; **`bin_auto(timestamp)`**
  adapts chart bins to the requested window. Metric rate/percentile bins must
  still accommodate the emission interval.

## Keep queries fast

Berserk prunes chunks via bloom / range indexes and only reads what a query needs — write queries that let it prune, and never pull down more than you must:

- Choose a window matching the question; start narrow for an unspecified recent issue.

- **Filter on a selective, reasonably long string** (a service name, an error   signature, an id) so the bloom index skips chunks. An unfiltered aggregate like   `<table> | count` is a full-table scan — it must read every chunk. Put a pruning   `where` before the aggregation.
- **Answering "how many …?" with no window named:** never run an unfiltered   count over a wide range. Count a narrow window (30m–1h), report it as a windowed   number ("~N rows in the last hour"), and offer to widen if the user wants a   longer horizon. Honor an explicit historical interval directly.
- **Approximate and limit.** Prefer `dcount()` (approximate) over exact distinct   counts, and cap rows with `take` / `limit`. A "naked" table reference with   nothing after it already resolves to `<table> | tail 2000`, so a bare `<table>`   is a cheap recent-rows peek — not a scan.
- **Order after aggregating when possible.** Sort the small output of a `summarize` for ranked groups. Use raw timestamp ordering when the question requires newest rows.
- **Peek before you commit.** When log-pattern / `fieldstats` / OTel-stats helpers   don't fit, `<query> | take 2` is the fastest way to see the shape of the data   before writing the real query.

## Metrics

Each metric row is one OTel data point. `$raw` refers to that whole underlying record — every stored field. The common OTel fields are surfaced as typed columns (`value`, `metric_name`, `aggregation_temporality`, …) and bare names resolve against the record automatically (permissive mode), so you rarely write `$raw` yourself. You pass `$raw` to the OTel counter/histogram aggregates specifically because they operate on the *entire* data point — value, temporality, and timing together — not a single column, which is what lets them handle cumulative-vs-delta correctly. Group by `metric_hash` (one series per label set — required for counter rates, or per-pod values mix and produce wrong rates). Pick the aggregate by metric kind:

- **Counter** — `otel_rate($raw)`: the per-second rate of the monotonic counter   (bytes, requests, drops). This is the OTel equivalent of `rate(value, timestamp)`.
- **Histogram** — `otel_histogram_merge($raw)` to merge buckets, or   `otel_histogram_percentile($raw, <p>)` for a percentile (e.g. p95 latency). Keep   the bin ≥ 2 scrape intervals — a single-snapshot bin reads NaN.
- **Gauge** — plain `avg(value)` / `max(value)`; a gauge is   already an instantaneous value, so no OTel function and no `$raw`.

Canonical shape (per-series counter rate, largest series first):

    <table>
    | where metric_name == '<name>'
    | make-series value = otel_rate($raw) on timestamp step 1m by metric_hash
    | top 1000 by series_max(value) desc

`make-series` needs a `step`; add explicit `from <start> to <end>` only when you want a fixed axis rather than the scanned window.

## Log pattern discovery

To find recurring log shapes — templatize each body and count how often each pattern occurs — use:

    <table>
    | where isnotnull(body)
    | summarize take_any_body = take_any(tostring(body)), count = count()
      by hash = log_template_hash(tostring(body))
    | extend p = extract_log_template(take_any_body), rex = log_template_regex(take_any_body)
    | project p, count, rex
    | top 500 by count desc

### Finding traces, not just individual spans

Use `trace-find` when the question relates multiple spans or correlated logs.
Ordinary `where` filters individual rows and cannot express those relationships.

```bash
bzrk -P <profile> search 'T | trace-find { severity_text == "ERROR" } | take 20' --since "30m ago" --desc "sample traces carrying error logs"
bzrk -P <profile> search 'T | trace-find { status_code == "ERROR" } summarize errors=countif(status_code == "ERROR"), rows=count()' --since "30m ago" --desc "count errors within matching traces"
```

- One `{ A and B }` block requires the same row to satisfy both. `{ A } and { B }`
  requires both to exist in the trace, possibly on different spans.
- `>` is child, `>>` descendant, `<` parent, `<<` ancestor, `~` sibling;
  `::` links spans to correlated logs. Keep log rows in the input for correlation.
- Chaining `{ A } >> { B } >> { C }` checks the two relationships independently;
  do not assume the same B span connects both. A root span has no ancestor.
- Default output is one row per matching trace. Attached `summarize` aggregates
  collected trace rows, not only predicate matches; grouping by trace_id is implicit.
  A subsequent `| summarize` instead aggregates the trace-find output rows.
- `within` defaults to 5m and is a collection-window hint, not a strict duration
  predicate. The engine can widen it. Choose a window appropriate for long traces;
  use an output duration predicate for an actual duration constraint.
- Unordered `| take N` can stop after collecting N traces, an arbitrary subset.
  Later matches beyond the collected window may be absent. Do not call it newest-N
  or a complete trace history. Trace duration is a timespan; `/ 1ms` yields milliseconds.

For full syntax and collection limits consult MCP `get_docs("trace-find")` or the
Berserk query-language reference. Keep field names based on discovery.

### Streaming results and deciding when to stop

`bzrk search` streams replacement snapshots over the same requested window.
Each snapshot contains the scan's current coverage, not necessarily the newest
data. Do not concatenate snapshots or infer a global minimum/maximum from one.

Choose a stopping condition based on the question. Existence and thresholds on
monotonically increasing counts can be decided early; exact totals, averages,
newest-N and absence require complete coverage. Sums are lower bounds only if
contributions are non-negative; partial averages and percentiles are not bounds.

```bash
bzrk -P <profile> search 'T | summarize n=count()' --since "30m ago" --stop-when "n >= 50" --allow-partial --desc "are there at least 50 rows"
```

`--stop-when` accepts `<ident> <op> <number>`: `rows` or a column, with
`>= <= > < == !=`. A column predicate reads the FIRST row only. For a threshold
on any group, sort the aggregate descending to put its maximum first. Only stop
when the condition cannot be undone by further scanning; equality of a running
count is not evidence of the final count. MCP's `stop_when` explicitly prevents
non-absorbing predicates from cancelling; do not assume CLI flags do the same.

`--stop-cmd` handles a condition over a completed snapshot TSV. It receives the
absolute file path as `$1` (also `BZRK_SNAPSHOT_TSV`, `BZRK_INCREMENT`, `BZRK_ROWS`).
Exit 0 stops, 1 continues, any other code aborts. It is Unix-only and mutually
exclusive with `--stop-when`.

Agent output headers include absolute paths to saved TSV files. Read those paths
to inspect full results instead of rerunning the query or constructing cache
paths. `# Stopped Early` is a partial answer; report the threshold witness and
window, not an exact total. `# Query Complete` indicates the scan ended, but
inspect warnings and dropped-data signals before claiming complete data.
Approximate aggregates remain approximate even after a complete scan.

Incomplete results normally exit 3. Use `--allow-partial` when an intentional
partial answer meets the request; the flag changes exit handling, not coverage.
`--no-stream` requests final-only output and conflicts with the stop flags.
Use built-in stopping controls rather than a shell pipeline to `head`, which
can truncate a query without establishing the answer.

### Time formats

- Relative: `"1h ago"`, `"2d ago"`, `"30m ago"`
- Absolute: `"2024-01-01"`, `"2024-01-01T10:30:00"`
- Special: `"now"`, `"today"`, `"yesterday"`

### Reference and compatibility

The current reference includes `distinct` and real-table `union`. Pipeline-subquery
union arms have restrictions on nested operators and downstream processing;
consult MCP `get_docs("union")` when available, or https://docs.bzrk.dev/.
Do not infer full ADX compatibility or deployed capabilities from remembered
release notes. Report unsupported syntax and use an equivalent query only when
it preserves the requested answer.
