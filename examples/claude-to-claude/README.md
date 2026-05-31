# Example: Claude-to-Claude Communication

This example shows two Claude Code sessions communicating via `peer-bridge.sh`.

## Setup

### Session A — Orchestrator (this terminal)

```bash
# 1. Clone the repo
git clone https://github.com/yourusername/ai-agent-bridge
cd ai-agent-bridge

# 2. Start the bridge pointing at your task inbox
TARGET_ROLE="image-agent" ./bridge/peer-bridge.sh --inbox ./inbox
```

### Session B — Image Agent (separate terminal / IDE window)

Open a second Claude Code session (or use a separate IDE window).
In the Claude Code chat, tell Claude to set its summary:

```
Please run: set_summary as "image-agent: ready for image generation tasks"
```

Claude will call the `set_summary` MCP tool, making it discoverable.

## Drop a task

```bash
mkdir -p inbox
cat > inbox/task-001.md << 'EOF'
---
from: orchestrator
type: image-request
---

Please generate a thumbnail image for this article.
Title: "How I recovered 3 hours per week with AI automation"
Style: professional, warm tones, 1024x572px
EOF
```

The bridge detects the file, finds Session B by its summary keyword `image-agent`,
and forwards the message. Session B's Claude receives it and begins generating.

## How peer discovery works

```
peer-bridge.sh
  └─ POST localhost:7899/list-peers
       └─ filter: summary contains "image-agent"
            └─ POST localhost:7899/send-message {to_id: <peer>, text: <content>}
```

The `claude-peers` MCP server (bundled with Claude Code) manages peer registration
and message routing between sessions on the same machine.

## One-shot delivery

If you only need to send a single file rather than watch an inbox:

```bash
./bridge/file-bridge.sh --role "image-agent" --file inbox/task-001.md
```

## Scheduled dispatch

To send a recurring task (e.g., a daily report request at 09:00):

```bash
# Run once every 24h
./bridge/cron-dispatch.sh \
  --role "report-agent" \
  --template examples/templates/daily-report.md \
  --interval 86400
```

Use `{{DATE}}` and `{{TIME}}` in your template — they are substituted at send time.
