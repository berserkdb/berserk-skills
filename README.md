# Berserk Skills

Agent skills and subagents for querying [Berserk](https://berserk.dev) from AI coding agents.

## What's Included

| Component                    | Description                                                                                                             |
| ---------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| **berserk** skill            | Teaches Claude how to use the `bzrk` CLI — triggered automatically when you mention logs, traces, metrics, or debugging |
| **explore** agent            | General-purpose data exploration — schema discovery, error investigation, service health checks                         |
| **cluster-admin** agent      | Manage and troubleshoot a Berserk cluster — service health, datasets, segments, ingest tokens, merge tasks              |
| **otel-log** agent           | Investigate OpenTelemetry logs — error patterns, log templates, severity analysis, service-level log exploration        |
| **otel-trace** agent         | Investigate OpenTelemetry traces — span analysis, latency debugging, trace correlation, service dependency mapping      |
| **otel-metric** agent        | Investigate OpenTelemetry metrics — gauge/sum/histogram analysis, metric discovery, time-series queries                 |
| **incident-triage** agent    | Investigate production incidents — correlate errors, latency spikes, and log patterns to find root cause                |
| **trace-analysis** agent     | Analyze distributed traces — build cause-and-effect narratives, identify critical paths and cascading failures          |

## Claude Code

### Install via Plugin Marketplace

```
/plugin marketplace add berserkdb/berserk-skills
/plugin install berserk@berserk-skills
```

### Install Manually

```bash
git clone https://github.com/berserkdb/berserk-skills.git /tmp/berserk-skills
cp -r /tmp/berserk-skills/skills/berserk .claude/skills/
cp -r /tmp/berserk-skills/agents .claude/agents/
```

### Prerequisites

Install the `bzrk` CLI:

```bash
curl -fsSL https://go.bzrk.dev | bash
```

Configure a profile pointing to your Berserk instance:

```bash
bzrk profile list
```

### Usage

Once installed, just ask Claude to query your data:

- "Search for errors in the last hour"
- "Look at traces around 2024-01-07T08:38:00Z"
- "What services are logging?"
- "Investigate connection refused errors"

The agents are invoked automatically when Claude needs to do focused investigation without filling up your main conversation with query results. The **berserk** skill routes tasks to the appropriate specialist agent based on the query type.

You can also invoke agents explicitly:

- "Use the explore agent to check what services are logging"
- "Use the incident-triage agent to investigate the production outage"
- "Use the trace-analysis agent to analyze trace abc123"

### Claude Agent SDK

Use the berserk-explore agent programmatically:

```typescript
import { query } from "@anthropic-ai/claude-agent-sdk";

for await (const message of query({
  prompt: "Investigate error rates across services in the last 6 hours",
  options: {
    allowedTools: ["Bash", "Read", "Grep", "Glob", "Agent"],
    settingSources: ["project"], // loads CLAUDE.md + installed plugins
  },
})) {
  if ("result" in message) console.log(message.result);
}
```

Or define agents inline without the plugin:

```typescript
import { query } from "@anthropic-ai/claude-agent-sdk";
import { readFileSync } from "fs";

const agentPrompt = readFileSync("agents/explore.md", "utf-8");

for await (const message of query({
  prompt: "What services have the highest error rates?",
  options: {
    allowedTools: ["Bash", "Read", "Grep", "Glob", "Agent"],
    agents: {
      explore: {
        description: "Explore and query observability data in Berserk",
        prompt: agentPrompt,
        tools: ["Bash", "Read", "Grep", "Glob"],
        model: "sonnet",
      },
    },
  },
})) {
  if ("result" in message) console.log(message.result);
}
```

## OpenCode

[OpenCode](https://opencode.ai) discovers skills from `.claude/skills/` automatically:

```bash
git clone https://github.com/berserkdb/berserk-skills.git /tmp/berserk-skills
cp -r /tmp/berserk-skills/skills/berserk .claude/skills/
```

Or install globally for all projects:

```bash
cp -r /tmp/berserk-skills/skills/berserk ~/.claude/skills/
```

## Other Agents

Support for Cursor, GitHub Copilot, and other coding agents is planned. Contributions welcome.
