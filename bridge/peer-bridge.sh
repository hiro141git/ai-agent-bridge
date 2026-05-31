#!/bin/bash
# peer-bridge.sh — AI Agent Bridge core daemon
# Watches an inbox directory and forwards task files to a target peer
# discovered via claude-peers API (localhost:7899)
#
# Usage: ./peer-bridge.sh [--inbox DIR] [--role ROLE] [--peers-url URL]

set -euo pipefail

INBOX="${INBOX:-./inbox}"
TARGET_ROLE="${TARGET_ROLE:-}"
PEERS_URL="${PEERS_URL:-http://localhost:7899}"
POLL_INTERVAL="${POLL_INTERVAL:-3}"
PROCESSED_FILE="${PROCESSED_FILE:-.processed}"
ID_CACHE_FILE=".peer-id-cache"
ID_CACHE_TTL=300  # 5 minutes

while [[ $# -gt 0 ]]; do
  case "$1" in
    --inbox)   INBOX="$2";       shift 2 ;;
    --role)    TARGET_ROLE="$2"; shift 2 ;;
    --peers-url) PEERS_URL="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

mkdir -p "$INBOX"
touch "$PROCESSED_FILE"

log() { echo "[peer-bridge] $*"; }

# Discover target peer by role keyword in summary
# Uses exponential backoff: 1s → 2s → 4s → 8s → max 30s
discover_peer() {
  local cached age
  if [[ -f "$ID_CACHE_FILE" ]]; then
    cached=$(cat "$ID_CACHE_FILE")
    age=$(( $(date +%s) - $(stat -f %m "$ID_CACHE_FILE" 2>/dev/null || stat -c %Y "$ID_CACHE_FILE") ))
    if [[ -n "$cached" && "$age" -lt "$ID_CACHE_TTL" ]]; then
      echo "$cached"; return 0
    fi
  fi

  local found
  found=$(curl -sf -X POST "$PEERS_URL/list-peers" \
    -H "Content-Type: application/json" -d '{}' | \
    jq -r --arg role "$TARGET_ROLE" \
      '.[] | select(.summary != null and (.summary | ascii_downcase | contains($role | ascii_downcase))) | .id' \
    2>/dev/null | head -1)

  if [[ -n "$found" ]]; then
    echo "$found" > "$ID_CACHE_FILE"
    log "Peer discovered: $found (role: $TARGET_ROLE)"
    echo "$found"; return 0
  fi

  echo "" > "$ID_CACHE_FILE"
  return 1
}

# Send a message to a peer, with one cache-invalidating retry on failure
send_to_peer() {
  local peer_id="$1" message="$2" fname="$3"
  local payload result

  payload=$(jq -n \
    --arg to "$peer_id" \
    --arg text "$message" \
    '{to_id: $to, text: $text}')

  result=$(curl -sf -X POST "$PEERS_URL/send-message" \
    -H "Content-Type: application/json" -d "$payload" 2>/dev/null || echo '{}')

  if echo "$result" | jq -e '.ok == true' > /dev/null 2>&1; then
    return 0
  fi

  # Retry: invalidate cache and rediscover
  rm -f "$ID_CACHE_FILE"
  peer_id=$(discover_peer 2>/dev/null) || return 1
  [[ -z "$peer_id" ]] && return 1

  payload=$(jq -n \
    --arg to "$peer_id" \
    --arg text "$message" \
    '{to_id: $to, text: $text}')

  result=$(curl -sf -X POST "$PEERS_URL/send-message" \
    -H "Content-Type: application/json" -d "$payload" 2>/dev/null || echo '{}')

  echo "$result" | jq -e '.ok == true' > /dev/null 2>&1
}

# Hash-based processed tracking (re-sends if file content changes)
file_hash() { md5 -q "$1" 2>/dev/null || md5sum "$1" | cut -d' ' -f1; }

is_processed() {
  local fname hash
  fname=$(basename "$1")
  hash=$(file_hash "$1")
  grep -qF "${fname}:${hash}" "$PROCESSED_FILE" 2>/dev/null
}

mark_processed() {
  local fname hash
  fname=$(basename "$1")
  hash=$(file_hash "$1")
  echo "${fname}:${hash}" >> "$PROCESSED_FILE"
}

# Exponential backoff state per file
declare -A BACKOFF_DELAY BACKOFF_UNTIL
MAX_BACKOFF=30

next_backoff() {
  local key="$1"
  local cur="${BACKOFF_DELAY[$key]:-1}"
  local next=$(( cur * 2 ))
  [[ "$next" -gt "$MAX_BACKOFF" ]] && next=$MAX_BACKOFF
  BACKOFF_DELAY[$key]=$next
  BACKOFF_UNTIL[$key]=$(( $(date +%s) + cur ))
}

reset_backoff() {
  unset "BACKOFF_DELAY[$1]" "BACKOFF_UNTIL[$1]"
}

in_backoff() {
  local key="$1" now
  now=$(date +%s)
  [[ -n "${BACKOFF_UNTIL[$key]:-}" && "${BACKOFF_UNTIL[$key]}" -gt "$now" ]]
}

log "Starting. inbox=$INBOX role=${TARGET_ROLE:-any} peers=$PEERS_URL"

while true; do
  for f in "$INBOX"/*.md; do
    [[ -f "$f" ]] || continue
    fname=$(basename "$f")

    is_processed "$f" && continue
    in_backoff "$fname" && continue

    log "Detected: $fname"
    message=$(tail -n +5 "$f")  # skip first 4 lines (frontmatter)

    peer_id=$(discover_peer 2>/dev/null) || { next_backoff "$fname"; continue; }
    [[ -z "$peer_id" ]] && { next_backoff "$fname"; continue; }

    if send_to_peer "$peer_id" "$message" "$fname"; then
      log "Sent: $fname → $peer_id"
      mark_processed "$f"
      reset_backoff "$fname"
    else
      log "Send failed: $fname (will retry)"
      next_backoff "$fname"
    fi
  done

  sleep "$POLL_INTERVAL"
done
