#!/usr/bin/env bash
# municipal_hygiene.sh - Automated Municipal Hygiene for Camp Colt
# Reaps dormant sessions, clears stale worker leases, and maintains CGroup hygiene.
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

echo "[$(date -Iseconds)] Municipal hygiene patrol completed."
