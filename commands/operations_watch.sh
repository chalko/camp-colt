#!/usr/bin/env bash
# commands/operations_watch.sh
# Generic Operations Watch Patrol & Stagnation Detection Script
# Managed under SOP_OPERATIONS_WATCH_AND_STAGNATION_DETECTION.md
# Maintained by S-3 Operations.

set -euo pipefail

CITY_ROOT="${GC_CITY:-/home/camp-colt-mayor-agent/colony}"
STATE_DIR="${CITY_ROOT}/.gc/runtime/watch"
LEDGER_FILE="${STATE_DIR}/operations_watch_state.json"
mkdir -p "${STATE_DIR}" 2>/dev/null || true

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# 1. Phase 0A: Check inbound unread mail for s3-operations explicitly (JSON)
INBOUND_MAIL=$(gc mail inbox s3-operations --json 2>/dev/null || echo '{"messages":[]}')

# 2. Phase 0B: Peer staff unread mail check including cos (JSON)
CORE_BILLETS=("cos" "mayor" "s6-signal" "colt-sysadmin" "s1-personnel" "s4-logistics")
for billet in "${CORE_BILLETS[@]}"; do
    PEER_MAIL=$(gc mail inbox "${billet}" --json 2>/dev/null || echo '{"messages":[]}')
done

# 3. Phase 1: Query active beads across city and active rigs (JSON)
ACTIVE_CITY_BEADS=$(gc bd list --json 2>/dev/null || echo '[]')
ACTIVE_GASCITY_BEADS=$(gc bd --rig gascity list --json 2>/dev/null || echo '[]')
ACTIVE_SUITCASE_BEADS=$(gc bd --rig suitcase-ai list --json 2>/dev/null || echo '[]')
ACTIVE_SESSIONS=$(gc session list --json 2>/dev/null || echo '{"sessions":[]}')

# Log execution checkpoint
echo "[${NOW}] Operations Watch Patrol executed across city, gascity, and suitcase-ai rigs via --json interfaces." >> "${STATE_DIR}/watch.log"
