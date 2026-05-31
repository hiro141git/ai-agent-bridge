#!/usr/bin/env bash
# test-peer-bridge.sh — Integration tests for peer-bridge.sh
# Requires: bash 4+, jq (for backoff tests; bash 3 runs only file_hash + processed tests)
# Run: bash tests/test-peer-bridge.sh

set -euo pipefail

BASH_MAJOR="${BASH_VERSINFO[0]:-3}"

PASS=0
FAIL=0
BRIDGE="./bridge/peer-bridge.sh"
TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# ── helpers ──────────────────────────────────────────────────────────────────

pass() { echo "  ✓ $1"; PASS=$(( PASS + 1 )); }
fail() { echo "  ✗ $1: $2"; FAIL=$(( FAIL + 1 )); }

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then pass "$label"; else fail "$label" "expected '$expected', got '$actual'"; fi
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qF "$needle"; then pass "$label"; else fail "$label" "'$needle' not found in output"; fi
}

# ── unit: file_hash ───────────────────────────────────────────────────────────

echo "=== file_hash ==="

f="$TMPDIR_TEST/sample.md"
echo "hello world" > "$f"

h1=$(md5 -q "$f" 2>/dev/null || md5sum "$f" | cut -d' ' -f1)
h2=$(md5 -q "$f" 2>/dev/null || md5sum "$f" | cut -d' ' -f1)
assert_eq "identical files produce same hash" "$h1" "$h2"

echo "changed" >> "$f"
h3=$(md5 -q "$f" 2>/dev/null || md5sum "$f" | cut -d' ' -f1)
if [[ "$h1" != "$h3" ]]; then pass "changed content produces different hash"; else fail "changed content produces different hash" "hash did not change"; fi

# ── unit: processed tracking ─────────────────────────────────────────────────

echo ""
echo "=== processed tracking ==="

PROCESSED="$TMPDIR_TEST/.processed"
touch "$PROCESSED"

task="$TMPDIR_TEST/task-001.md"
cat > "$task" << 'EOF'
---
from: orchestrator
type: task
---
Generate thumbnail for article 1.
EOF

fname=$(basename "$task")
hash=$(md5 -q "$task" 2>/dev/null || md5sum "$task" | cut -d' ' -f1)
entry="${fname}:${hash}"

# Not yet processed
if ! grep -qF "$entry" "$PROCESSED"; then pass "new file not in processed list"; else fail "new file not in processed list" "unexpectedly found"; fi

# Mark processed
echo "$entry" >> "$PROCESSED"
if grep -qF "$entry" "$PROCESSED"; then pass "mark_processed writes entry"; else fail "mark_processed writes entry" "entry not found"; fi

# Re-check
if grep -qF "$entry" "$PROCESSED"; then pass "is_processed detects existing entry"; else fail "is_processed detects existing entry" "entry not found"; fi

# Content change → new hash
echo "updated content" >> "$task"
hash2=$(md5 -q "$task" 2>/dev/null || md5sum "$task" | cut -d' ' -f1)
entry2="${fname}:${hash2}"
if ! grep -qF "$entry2" "$PROCESSED"; then pass "updated file treated as unprocessed"; else fail "updated file treated as unprocessed" "old hash matched new content"; fi

# ── unit: backoff logic ───────────────────────────────────────────────────────

echo ""
echo "=== backoff logic ==="

if [[ "$BASH_MAJOR" -lt 4 ]]; then
  echo "  (skipped — bash 4+ required for associative arrays; install bash via Homebrew on macOS)"
else

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

in_backoff() {
  local key="$1" now
  now=$(date +%s)
  [[ -n "${BACKOFF_UNTIL[$key]:-}" && "${BACKOFF_UNTIL[$key]}" -gt "$now" ]]
}

reset_backoff() { unset "BACKOFF_DELAY[$1]" "BACKOFF_UNTIL[$1]"; }

key="task-001.md"
# shellcheck disable=SC2034  # used inside declare -A scope
if ! in_backoff "$key"; then pass "no backoff initially"; else fail "no backoff initially" "in_backoff returned true"; fi

next_backoff "$key"
if in_backoff "$key"; then pass "in_backoff true after first failure"; else fail "in_backoff true after first failure" "returned false"; fi
assert_eq "delay doubles on second call" "2" "${BACKOFF_DELAY[$key]}"

next_backoff "$key"
assert_eq "delay doubles again" "4" "${BACKOFF_DELAY[$key]}"

# Fill to max
for _ in 1 2 3 4 5; do next_backoff "$key"; done
if [[ "${BACKOFF_DELAY[$key]}" -le "$MAX_BACKOFF" ]]; then pass "delay capped at MAX_BACKOFF=$MAX_BACKOFF"; else fail "delay capped" "got ${BACKOFF_DELAY[$key]}"; fi

reset_backoff "$key"
if ! in_backoff "$key"; then pass "reset clears backoff"; else fail "reset clears backoff" "still in backoff"; fi

fi  # end bash 4+ guard

# ── syntax check ─────────────────────────────────────────────────────────────

echo ""
echo "=== syntax check ==="

for script in bridge/*.sh; do
  if bash -n "$script" 2>/dev/null; then pass "bash -n $script"; else fail "bash -n $script" "syntax error"; fi
done

# ── summary ──────────────────────────────────────────────────────────────────

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
