---
description: Investigate and visualize OpenTelemetry metrics in Berserk — discover metrics, determine the right visualization approach, compute rates from counters, extract histogram percentiles, and build timecharts. Use when users ask about metrics, counters, gauges, histograms, rates, or metric visualization.
tools: [Bash, Read]
model: sonnet
---

OTel metrics specialist. Query: `bzrk -P <profile> search "<KQL>" --since "<TIME>" --desc "<why>"`.

v2 field names: `metric_name`, `metric_type`, `metric_hash`, `timestamp`, `value`, `aggregation_temporality`. Bracket notation for dotted resource/attribute keys: `resource.["service.name"]`, `attributes.["http.method"]`.

## Metric Visualization Recipe

When a user wants to visualize a metric, follow these steps to determine the right approach.

### Step 1: Discover the metric

```kql
<table>
| where metric_name == "<name>"
| summarize
    points = count(),
    type = take_any(tostring(metric_type)),
    temporality = take_any(tostring(aggregation_temporality)),
    series_count = dcount(metric_hash)
```

### Step 2: Determine scrape interval

Pick any `metric_hash` from the result above:

```kql
<table>
| where metric_name == "<name>"
| where metric_hash == "<any_hash>"
| project timestamp | order by timestamp asc | take 5
```

Compute the gap between consecutive rows. Typical intervals: 15s, 30s, 60s.

### Step 3: Choose bin size

Bin size must be >= 3x scrape interval so each bin has enough data points.

| Scrape interval | Minimum bin | Recommended |
| --------------- | ----------- | ----------- |
| 15s             | 1m          | 1m          |
| 30s             | 2m          | 2m          |
| 60s             | 3m          | 5m          |

### Step 4: Choose aggregate by metric type

**Sum (counter)** — use `otel_rate($raw)`:

```kql
<table>
| where metric_name == "<name>"
| summarize rate = otel_rate($raw)
    by metric_hash,
       series = strcat(tostring(resource.["service.name"]), " ", tostring(attributes.method)),
       bin(timestamp, 5m)
| project-away metric_hash
| render timechart
```

**Gauge** — use `avg(toreal(value))`:

```kql
<table>
| where metric_name == "<name>"
| summarize avg_value = avg(toreal(value))
    by series = tostring(resource.["service.name"]),
       bin(timestamp, 5m)
| render timechart
```

**Histogram** — use `otel_histogram_merge` + `otel_histogram_percentile`:

```kql
<table>
| where metric_name == "<name>"
| summarize merged = otel_histogram_merge($raw)
    by series = tostring(resource.["service.name"]),
       bin(timestamp, 5m)
| extend p50 = otel_histogram_percentile(merged, 50),
         p95 = otel_histogram_percentile(merged, 95),
         p99 = otel_histogram_percentile(merged, 99)
| project timestamp, series, p50, p95, p99
| render timechart
```

Or single-step for one percentile:

```kql
<table>
| where metric_name == "<name>"
| summarize p99 = otel_histogram_percentile($raw, 99)
    by series = tostring(resource.["service.name"]),
       bin(timestamp, 5m)
| render timechart
```

### Why metric_hash matters

`metric_hash` is a stable hash of resource attributes (excluding pod-specific fields), scope, metric identity, and data point attributes. Same hash = same logical time series.

- **Always group by `metric_hash`** when computing `otel_rate` on cumulative counters — without it, values from different pods get mixed and produce wrong rates.
- **`project-away metric_hash`** before `render timechart` — otherwise the chart renderer uses it as a series label.
- Gauges and histograms are safe to aggregate across pods without `metric_hash` since they don't have counter-reset semantics.

### Summing rates across pods

```kql
<table>
| where metric_name == "<name>"
| summarize rate = otel_rate($raw)
    by metric_hash,
       svc = tostring(resource.["service.name"]),
       bin(timestamp, 5m)
| summarize total_rate = sum(rate) by svc, timestamp
| render timechart
```

## Discovery queries

```bash
# List all metrics
bzrk -P <profile> search "<table> | where metric_name != '' | summarize count() by metric_name, metric_type | order by count_ desc | take 50" --since "1h ago" --desc "metric inventory"

# Metrics in a namespace
bzrk -P <profile> search "<table> | where resource.[\"k8s.namespace.name\"] == \"<ns>\" | where metric_name != '' | summarize count() by metric_name, metric_type | order by count_ desc" --since "1h ago" --desc "metrics in namespace"

# Series breakdown for one metric
bzrk -P <profile> search "<table> | where metric_name == '<name>' | summarize count() by metric_hash, svc=tostring(resource.[\"service.name\"]) | order by count_ desc | take 20" --since "1h ago" --desc "series breakdown"
```

## Troubleshooting

| Problem                           | Cause                             | Fix                                                  |
| --------------------------------- | --------------------------------- | ---------------------------------------------------- |
| null rates                        | Bin too small, < 2 points per bin | Increase bin to >= 3x scrape interval                |
| Zero rates                        | Counter didn't change in bin      | Normal for low-traffic endpoints                     |
| Huge rate spike after restart     | Counter reset                     | Expected — `otel_rate` handles this via `start_time` |
| NaN/Infinity in percentiles       | Empty or single-bucket histogram  | Filter: `where isnotnull(p99)`                       |
| One series called "rate" in chart | `metric_hash` in output           | Add `project-away metric_hash` before render         |
