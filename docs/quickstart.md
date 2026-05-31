# Quickstart

## Prerequisites

- macOS or Linux
- `curl` and `jq` installed
- Claude Code running with the `claude-peers` MCP plugin enabled

## 1. Clone and install

```bash
git clone https://github.com/yourusername/ai-agent-bridge
cd ai-agent-bridge
chmod +x bridge/*.sh
```

## 2. Start the target agent session

In your target agent (e.g., an image generation Claude Code session), set its summary so it can be discovered:

```
# In the target Claude Code session, ask Claude to run:
set_summary: my-image-agent: ready for tasks
```

## 3. Start the bridge

```bash
TARGET_ROLE="my-image-agent" ./bridge/peer-bridge.sh --inbox ./inbox
```

## 4. Drop a task

```bash
cat > ./inbox/task-001.md << 'EOF'
---
from: orchestrator
type: task
---

Please generate a thumbnail image for article 156.
Title: "AIに相談し続けて、気づいたら誰も自分に反論しなくなっていた"
EOF
```

The bridge will detect the file, find the peer with "my-image-agent" in its summary, and forward the message.

## Real-world example

See `examples/claude-to-claude/` for a complete setup of two Claude Code sessions communicating via peer-bridge.
