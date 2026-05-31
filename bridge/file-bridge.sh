#!/bin/bash
# file-bridge.sh — One-shot file drop to a target peer
# Discovers a peer by role and sends the contents of a file as a message.
#
# Usage: ./bridge/file-bridge.sh --role ROLE --file FILE [--peers-url URL]
# Example: ./bridge/file-bridge.sh --role "my-agent" --file ./tasks/task-001.md

set -euo pipefail

ROLE=""
FILE=""
PEERS_URL="${PEERS_URL:-http://localhost:7899}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role)      ROLE="$2";      shift 2 ;;
    --file)      FILE="$2";      shift 2 ;;
    --peers-url) PEERS_URL="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

[[ -z "$ROLE" ]] && { echo "Error: --role is required" >&2; exit 1; }
[[ -z "$FILE" ]] && { echo "Error: --file is required" >&2; exit 1; }
[[ -f "$FILE" ]] || { echo "Error: file not found: $FILE" >&2; exit 1; }

peer_id=$(curl -sf -X POST "$PEERS_URL/list-peers" \
  -H "Content-Type: application/json" -d '{}' | \
  jq -r --arg role "$ROLE" \
    '.[] | select(.summary != null and (.summary | ascii_downcase | contains($role | ascii_downcase))) | .id' \
  2>/dev/null | head -1)

if [[ -z "$peer_id" ]]; then
  echo "Error: no peer found with role '$ROLE'" >&2
  exit 1
fi

message=$(cat "$FILE")
payload=$(jq -n --arg to "$peer_id" --arg text "$message" '{to_id: $to, text: $text}')

result=$(curl -sf -X POST "$PEERS_URL/send-message" \
  -H "Content-Type: application/json" -d "$payload" 2>/dev/null || echo '{}')

if echo "$result" | jq -e '.ok == true' > /dev/null 2>&1; then
  echo "Sent: $(basename "$FILE") → $peer_id (role: $ROLE)"
else
  echo "Error: send failed. Response: $result" >&2
  exit 1
fi
