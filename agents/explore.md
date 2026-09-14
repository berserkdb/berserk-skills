---
name: explore
description: Explore unfamiliar Berserk logs, traces and metrics to answer a concrete investigation question.
tools: [Bash, Read, Grep, Glob]
model: sonnet
---

## Exploration workflow

Establish the environment, interval and kind of answer: a sample, existence,
exact total, trend, or relationship between spans. Discover tables and fields
unless that information is already known. A leading search is useful when an
error's source table is unknown. Narrow using discovered fields before expensive
aggregation. Report the selected window, evidence, and remaining uncertainty.
Search relevant source code when it can explain an observed log or span.

```sh
bzrk -P <profile> search '.show tables' --desc "discover tables"
bzrk -P <profile> search 'T | fieldstats with limit=1000 depth=2' --since "<start>" --until "<end>" --desc "discover fields"
bzrk -P <profile> search 'search "connection refused" | summarize n=count() by table=$table | top 5 by n desc' --since "<start>" --until "<end>" --desc "locate connection errors"
```

## Query execution

Use `bzrk --help`, `bzrk search --help`, and `bzrk profile list` to check the
installed CLI and available profiles. Use the profile, database and time window
requested by the user; repo-bound profiles require the corresponding working
directory. If the CLI or credentials are missing, report that prerequisite.

Examples use `T` for a discovered table, `<profile>` for a configured profile,
and `<start>`/`<end>` for explicit time bounds. Replace these before executing;
add discovered environment/service filters as appropriate. A trace ID alone is
not a time bound. Use single-quoted KQL so the shell preserves `$raw` and quoted
field paths. Pass `--desc` to explain the question, and inspect the result's
coverage before interpreting it.

These instructions include shared Berserk query guidance. Read the bundled
`skills/berserk/SKILL.md` when you need more CLI or query details. Use current
Berserk reference documentation for unfamiliar operators; an available MCP
`get_docs` can supply that reference. Do not assume a parent agent's context
or tools are available in this specialist's session.

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

## Metrics

Each metric row is one OTel data point. `$raw` refers to that whole underlying record — every stored field. The common OTel fields are surfaced as typed columns (`value`, `metric_name`, `aggregation_temporality`, …) and bare names resolve against the record automatically (permissive mode), so you rarely write `$raw` yourself. You pass `$raw` to the OTel counter/histogram aggregates specifically because they operate on the *entire* data point — value, temporality, and timing together — not a single column, which is what lets them handle cumulative-vs-delta correctly. `otel_rate` reads `metric_hash` from its input and handles each series separately, then sums their rates. Group by `metric_hash` when you want separate output series, not as a correctness requirement. Preserve that field inside the metric record; dropping it makes unrelated series indistinguishable. Pick the aggregate by metric kind:

- **Counter** — `otel_rate($raw)`: the per-second rate of the monotonic counter   (bytes, requests, drops). This is the OTel equivalent of `rate(value, timestamp)`.
- **Histogram** — `otel_histogram_merge($raw)` to merge buckets, or   `otel_histogram_percentile($raw, <p>)` for a percentile (e.g. p95 latency). Inspect temporality and choose bins with enough observations. Cumulative histograms need multiple snapshots for a percentile over the interval; delta histograms can contribute from one snapshot. Filter invalid percentile results with `isnotnull(p95) and isfinite(p95)`. `isnotnull` alone keeps NaN. Plain histogram merging sums cumulative snapshots; its count is not a per-bin observation delta.
- **Gauge** — plain `avg(value)` / `max(value)`; a gauge is   already an instantaneous value, so no OTel function and no `$raw`.

Canonical shape (per-series counter rate, largest series first):

    <table>
    | where metric_name == '<name>'
    | make-series value = otel_rate($raw) on timestamp step 1m by metric_hash
    | top 1000 by series_max(value) desc

`make-series` needs a `step`; add explicit `from <start> to <end>` only when you want a fixed axis rather than the scanned window.

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
