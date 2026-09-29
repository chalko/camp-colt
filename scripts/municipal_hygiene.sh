#!/usr/bin/env bash
# municipal_hygiene.sh - Automated Municipal Hygiene for Camp Colt
# Reaps dormant sessions, clears stale worker leases, and reaps detached ACP processes.
set -euo pipefail

CITY_DIR="/home/camp-colt-mayor-agent/colony"
export PATH="/home/linuxbrew/.linuxbrew/bin:$PATH"

echo "[$(date -Iseconds)] Running municipal hygiene patrol..."

# 1. Prune dormant/asleep/drained sessions older than 5 minutes
gc session prune --city "$CITY_DIR" --state asleep,suspended,drained --before 5m || true

# 2. Lease management deferred strictly to native Gas City Health Patrol per Command Directive (cc-wisp-gij3i)

# 3. Targeted process reaper for detached/orphaned opencode ACP processes
ACTIVE_IDS=$(gc session list --city "$CITY_DIR" --json 2>/dev/null | jq -r '[.sessions[]? | select(.state=="active") | .id] | .[]' 2>/dev/null || true)

REAPED_COUNT=0
for pid in $(pgrep -x opencode 2>/dev/null || true); do
  if [ ! -r "/proc/$pid/environ" ]; then
    continue
  fi

  sess_id=$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | grep "^GC_SESSION_ID=" | cut -d= -f2 || true)
  ppid=$(ps -p "$pid" -o ppid= 2>/dev/null | tr -d ' ' || true)

  if [ -z "$sess_id" ] || ! echo "$ACTIVE_IDS" | grep -qw "$sess_id"; then
    echo "[$(date -Iseconds)] Reaping detached opencode PID $pid (session: '${sess_id:-none}', parent: $ppid)..."
    kill -TERM "$pid" 2>/dev/null || true
    if [ -n "$ppid" ] && [ "$ppid" -gt 1 ]; then
      kill -TERM "$ppid" 2>/dev/null || true
    fi
    sleep 0.2
    kill -9 "$pid" 2>/dev/null || true
    if [ -n "$ppid" ] && [ "$ppid" -gt 1 ]; then
      kill -9 "$ppid" 2>/dev/null || true
    fi
    REAPED_COUNT=$((REAPED_COUNT + 1))
  fi
done

if [ "$REAPED_COUNT" -gt 0 ]; then
  echo "[$(date -Iseconds)] Reaped $REAPED_COUNT detached opencode process(es)."
else
  echo "[$(date -Iseconds)] Opencode process hygiene verified: zero detached orphans."
fi

echo "[$(date -Iseconds)] Municipal hygiene patrol completed."
