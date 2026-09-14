# Berserk Skills

Give your coding agent the knowledge to investigate logs, traces, and metrics in
[Berserk](https://berserk.dev). Explore unfamiliar data, write Berserk KQL, follow
requests across services, and turn telemetry into answers you can check.

This repository provides a portable **Berserk skill** for agents such as Codex,
Cursor, OpenCode, and Claude Code, plus **specialist agents** for the Claude Code
plugin.

## What you can do

- Find errors and recurring log patterns, then connect them to your source code.
- Follow distributed traces to investigate slow requests and failures.
- Explore service metrics, latency distributions, and changes over time.
- Discover fields and stored types before building a query.
- Use Berserk extensions such as `annotate` and `trace-find`, with guidance on
  time windows, units, and incomplete results.

## Get started

You need access to a Berserk instance. For CLI-based investigations, install
[`bzrk`](https://docs.bzrk.dev/) and configure a profile for your instance. Check
that the CLI is available and your profile appears:

```sh
bzrk --help
bzrk profile list
```

Then choose the installation that fits your agent.

### Portable skill

Use the [Agent Skills CLI](https://github.com/vercel-labs/skills) to choose an
agent and installation scope:

```sh
npx skills add berserkdb/berserk-skills
```

This installs the Berserk skill. The specialist agents listed below are included
with the Claude Code plugin.

To download the repository for inspection or manual setup:

```sh
git clone https://github.com/berserkdb/berserk-skills.git
```

The standalone skill lives in [`skills/berserk/SKILL.md`](skills/berserk/SKILL.md).
Follow your agent's instructions for loading a local skill.

### Claude Code plugin

Run these commands in Claude Code to install the skill and specialist agents:

```text
/plugin marketplace add berserkdb/berserk-skills
/plugin install berserk@berserk-skills
```

See [Claude Code's plugin guide](https://code.claude.com/docs/en/discover-plugins)
for installation scopes and plugin management.

## Ask a question

Tell your agent which environment to investigate and the time range you care
about. For example:

> Use my staging profile to find the most common checkout errors in the last hour.

> Investigate why payment requests became slower after the latest deployment.

> Follow this trace ID and show where the request spent its time.

> Compare API error rates before and after 14:00 UTC today.

The skill guides the agent through discovery, query construction, and result
interpretation. It explains how to distinguish a complete answer from a sample
or a partial scan, and how to refine a query when more evidence is needed.

## Using Berserk MCP

The skill focuses on querying with `bzrk`. If your agent is connected to a
Berserk MCP server, it can also discover databases and fields, run KQL, and fetch
operator documentation with `get_docs` through MCP tools.

Berserk MCP supplies its own instructions and works independently of this skill
and the CLI. When both are available, tell your agent which interface to use and
which environment to target.

## Claude Code specialist agents

The plugin includes agents for focused investigations. You can ask Claude to use
one by name, such as “Use the incident-triage agent to investigate checkout errors.”

| Agent | Focus |
| --- | --- |
| [`explore`](agents/explore.md) | Discover data and investigate service behavior |
| [`otel-log`](agents/otel-log.md) | Search logs, group errors, and analyze log patterns |
| [`otel-trace`](agents/otel-trace.md) | Explore spans, latency, and service relationships |
| [`otel-metric`](agents/otel-metric.md) | Analyze gauges, counters, and histograms |
| [`incident-triage`](agents/incident-triage.md) | Correlate logs, traces, and metrics during an incident |
| [`trace-analysis`](agents/trace-analysis.md) | Follow critical paths and cascading failures |
| [`cluster-admin`](agents/cluster-admin.md) | Inspect and manage a Berserk cluster with appropriate access |

## Updates

For skills installed with the Agent Skills CLI:

```sh
npx skills update
```

For the Claude Code plugin, refresh the marketplace and update the plugin from
your terminal:

```sh
claude plugin marketplace update berserk-skills
claude plugin update berserk@berserk-skills
```

For a manually downloaded copy, fetch the latest revision and replace the copy
your agent uses.

## Maintained with Berserk

The Berserk skill is **maintained in the Berserk source repository** and generated
from the same guidance used by Berserk MCP and the in-app assistant. This keeps
query semantics, extensions, and time-unit guidance aligned across interfaces.
This repository distributes the generated skill and the Claude Code plugin;
specialist agents are maintained here.

For questions, feedback, or corrections, contact [support@berserk.dev](mailto:support@berserk.dev).

[Berserk](https://berserk.dev) · [Documentation](https://docs.bzrk.dev/) · [License](LICENSE)
