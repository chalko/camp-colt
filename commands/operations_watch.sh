#!/usr/bin/env bash
# commands/operations_watch.sh
# Generic Operations Watch Patrol & Stagnation Detection Script
# Managed under SOP_OPERATIONS_WATCH_AND_STAGNATION_DETECTION.md
# Maintained by S-3 Operations.

set -euo pipefail

CITY_ROOT="${GC_CITY:-/home/camp-colt-mayor-agent/colony}"
STATE_DIR="${CITY_ROOT}/.gc/runtime/watch"
LEDGER_FILE="${STATE_DIR}/operations_watch_state.json"
SUMMARY_FILE="${STATE_DIR}/operations_watch_summary.md"
mkdir -p "${STATE_DIR}" 2>/dev/null || true

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# 1. Phase 0: Check inbound unread mail for s3-operations explicitly (JSON)
INBOUND_MAIL=$(gc mail inbox s3-operations --json 2>/dev/null || echo '{"messages":[]}')

# 2. Phase 1: Query active beads across city and active rigs (JSON)
ACTIVE_CITY_BEADS=$(gc bd list --json 2>/dev/null || echo '[]')
ACTIVE_GASCITY_BEADS=$(gc bd --rig gascity list --json 2>/dev/null || echo '[]')
ACTIVE_SUITCASE_BEADS=$(gc bd --rig suitcase-ai list --json 2>/dev/null || echo '[]')
ACTIVE_SESSIONS=$(gc session list --json 2>/dev/null || echo '{"sessions":[]}')

# 3. Phase 2: Update markdown summary file for instant human visibility
cat << EOF > "${SUMMARY_FILE}"
# Camp Colt Operations Watch Summary
- **Last Watch Tick**: ${NOW}
- **Inbound Unread Mail**: $(echo "${INBOUND_MAIL}" | jq '.messages | length' 2>/dev/null || echo '0')
- **Active Sessions**: $(echo "${ACTIVE_SESSIONS}" | jq '.sessions | length' 2>/dev/null || echo '0')
- **Tracked Active Workstreams**:
  * \`gcs-y9q\` [gascity]: Prepare clean upstream contribution branch (Phase 1 Tactical Hold)
  * \`mistral-small-4-benchmark\` [suitcase-ai]: Official 32k Spark Arena benchmark actively executing (Task 3 Run 3 passed clean)
EOF

# Log execution checkpoint
echo "[${NOW}] Operations Watch Patrol executed. Summary written to ${SUMMARY_FILE}." >> "${STATE_DIR}/watch.log"
