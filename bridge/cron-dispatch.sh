#!/bin/bash
# cron-dispatch.sh — Scheduled task dispatch to a target peer
# Reads a task template, substitutes {{DATE}} / {{TIME}} placeholders,
# and sends it to the target peer on a cron-like schedule.
#
# Usage: ./bridge/cron-dispatch.sh --role ROLE --template FILE --interval SECONDS
# Example: ./bridge/cron-dispatch.sh --role "report-agent" --template ./tasks/daily-report.md --interval 86400

set -euo pipefail

ROLE=""
TEMPLATE=""
INTERVAL=3600
PEERS_URL="${PEERS_URL:-http://localhost:7899}"
ONCE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role)      ROLE="$2";      shift 2 ;;
    --template)  TEMPLATE="$2";  shift 2 ;;
    --interval)  INTERVAL="$2";  shift 2 ;;
    --peers-url) PEERS_URL="$2"; shift 2 ;;
    --once)      ONCE=true;      shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

[[ -z "$ROLE" ]]     && { echo "Error: --role is required" >&2; exit 1; }
[[ -z "$TEMPLATE" ]] && { echo "Error: --template is required" >&2; exit 1; }
[[ -f "$TEMPLATE" ]] || { echo "Error: template not found: $TEMPLATE" >&2; exit 1; }

log() { echo "[cron-dispatch] $(date '+%Y-%m-%d %H:%M:%S') $*"; }

discover_peer() {
  curl -sf -X POST "$PEERS_URL/list-peers" \
    -H "Content-Type: application/json" -d '{}' | \
    jq -r --arg role "$ROLE" \
      '.[] | select(.summary != null and (.summary | ascii_downcase | contains($role | ascii_downcase))) | .id' \
    2>/dev/null | head -1
}

dispatch() {
  local now date time message peer_id payload result
  now=$(date +%s)
  date=$(date '+%Y-%m-%d')
  time=$(date '+%H:%M')

  message=$(sed "s/{{DATE}}/$date/g; s/{{TIME}}/$time/g" "$TEMPLATE")

  peer_id=$(discover_peer)
  if [[ -z "$peer_id" ]]; then
    log "No peer found for role '$ROLE' — skipping"
    return 1
  fi

  payload=$(jq -n --arg to "$peer_id" --arg text "$message" '{to_id: $to, text: $text}')
  result=$(curl -sf -X POST "$PEERS_URL/send-message" \
    -H "Content-Type: application/json" -d "$payload" 2>/dev/null || echo '{}')

  if echo "$result" | jq -e '.ok == true' > /dev/null 2>&1; then
    log "Dispatched to $peer_id (role: $ROLE)"
    return 0
  else
    log "Dispatch failed: $result"
    return 1
  fi
}

log "Starting. role=$ROLE template=$TEMPLATE interval=${INTERVAL}s"

while true; do
  dispatch || true
  "$ONCE" && break
  sleep "$INTERVAL"
done
