# ai-agent-bridge

A lightweight toolkit for connecting multiple AI agents (Claude Code, Hermes, and others) via peer-to-peer discovery and file-based communication.

## What it does

`ai-agent-bridge` solves the problem of **AI agents running in silos**. When you run Claude Code, Hermes, or other AI agents simultaneously, they can't easily communicate or hand off tasks to each other.

This toolkit provides:

- **Peer discovery** — find running AI agent sessions by their declared role (via `claude-peers` API)
- **File bridge** — reliable file-based message passing with automatic retry and backoff
- **Cron dispatch** — schedule tasks from one agent to another
- **Delivery confirmation** — hash-based tracking to avoid duplicate processing

## Architecture

```
Claude Code (Session A)          Claude Code (Session B)
      │                                   │
      │  1. Write task file               │
      ▼                                   │
  inbox/*.md  ──── peer-bridge.sh ────▶  │  2. Discover peer by summary
                                          ▼
                               claude-peers API (localhost:7899)
                                          │
                               3. Send message to Session B
```

## Quick start

```bash
# Install
git clone https://github.com/yourusername/ai-agent-bridge
cd ai-agent-bridge && chmod +x bridge/*.sh

# Start the bridge (watches inbox/ and forwards to a target peer)
./bridge/peer-bridge.sh --inbox ./inbox --role "my-agent-role"

# In the target agent session, declare your role
# (Claude Code: set_summary with your role name)
```

## Bridge scripts

| Script | Description |
|---|---|
| `bridge/peer-bridge.sh` | Core daemon: watches inbox, discovers peers by summary, forwards with retry |
| `bridge/file-bridge.sh` | Simple file drop — write a file to trigger the remote agent |
| `bridge/cron-dispatch.sh` | Scheduled dispatch: run a task on a remote agent at set intervals |

## Requirements

- macOS or Linux
- `curl`, `jq`
- `claude-peers` MCP server running at `localhost:7899` (included with Claude Code)

## Use cases

- **Image generation pipeline**: Lachesis (orchestrator) → Antigravity IDE (image agent)
- **Research + write**: Claude Code research session → Claude Code writing session
- **Scheduled reports**: Cron agent → Slack/Discord notification agent

## Contributing

PRs welcome. See [CONTRIBUTING.md](.github/CONTRIBUTING.md).

## License

MIT
