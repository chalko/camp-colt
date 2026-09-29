#!/usr/bin/env bash
# municipal_hygiene.sh - Automated Municipal Hygiene for Camp Colt
# Reaps dormant sessions, clears stale worker leases, and maintains CGroup/process hygiene.
set -euo pipefail

CITY_DIR="/home/camp-colt-mayor-agent/colony"
export PATH="/home/linuxbrew/.linuxbrew/bin:$PATH"

echo "[$(date -Iseconds)] Running municipal hygiene patrol..."

# 1. Prune dormant/asleep/drained sessions older than 15 minutes
gc session prune --city "$CITY_DIR" --state asleep,suspended,drained --before 15m || true

# 2. Reclaim stale leases across rigs (older than 10m grace window)
for rig_dir in "$CITY_DIR"/rigs/*; do
  if [ -d "$rig_dir/.beads" ]; then
    bd --directory "$rig_dir" reclaim --older-than 10m || true
  fi
done

# 3. Reap orphaned ACP worker processes (opencode acp)
# Count how many sessions are legitimately active with transport/command opencode acp
ACTIVE_ACP=$(gc session list --city "$CITY_DIR" --json 2>/dev/null | jq -r '[.sessions[]? | select(.command=="opencode acp" and .state=="active")] | length' 2>/dev/null || echo "0")

# Count actual running opencode binary instances (exact process name match)
RUNNING_OPENCODE=$(pgrep -c -x opencode 2>/dev/null || echo "0")

if [ "$ACTIVE_ACP" -eq 0 ] && [ "$RUNNING_OPENCODE" -gt 0 ]; then
  echo "[$(date -Iseconds)] Found $RUNNING_OPENCODE orphaned opencode processes with 0 active ACP sessions. Reaping..."
  pkill -x opencode || true
  pkill -f "sh -c opencode acp" || true
elif [ "$RUNNING_OPENCODE" -gt "$ACTIVE_ACP" ]; then
  echo "[$(date -Iseconds)] Warning: Running opencode processes ($RUNNING_OPENCODE) exceed active sessions ($ACTIVE_ACP)."
else
  echo "[$(date -Iseconds)] Opencode process hygiene verified: $RUNNING_OPENCODE running matching $ACTIVE_ACP active sessions."
fi

echo "[$(date -Iseconds)] Municipal hygiene patrol completed."
