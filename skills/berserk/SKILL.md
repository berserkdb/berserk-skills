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

**For investigation tasks** (searching errors, debugging issues, exploring data, running queries), delegate to the `berserk:explore` agent using the Agent tool. It runs autonomously with full bzrk/KQL knowledge and returns a summary.

**For inline help** (KQL syntax questions, bzrk flag reference), use the quick reference below.

## Quick Reference

### Installation

```bash
curl -fsSL https://go.bzrk.dev | bash
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

### Known limitations

`now()`, `ago()`, `top`, `distinct`, `union`, `coalesce()`, `format_datetime()` are not yet supported.
