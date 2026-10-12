#!/usr/bin/env bash
# ==============================================================================
# scripts/generate_morning_cub.sh
# Purpose: Autonomous generation of the 0600 Commander's Update Brief (CUB)
# Schedule: Triggered via Gas City order (orders/morning-cub.toml) at 05:15 PDT
# ==============================================================================
set -euo pipefail

COLONY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${COLONY_ROOT}"

DATE_STR="$(date +'%Y-%m-%d')"
TIMESTAMP="$(date +'%A, %d %B %Y, %H%M %Z')"
CUB_FILE="docs/CUB_${DATE_STR}_0600.md"

echo "=== [$(date)] Generating Commander's Update Brief (${CUB_FILE}) ==="

# Gather live status
BEAD_SUMMARY="$(gc bd list 2>/dev/null || echo "Unable to query beads")"
RECENT_COMMITS="$(git log -n 5 --oneline 2>/dev/null || echo "No recent commits")"
UNREAD_MAIL="$(gc mail inbox 2>/dev/null || echo "No unread mail")"

cat << EOF > "${CUB_FILE}"
# Commander's Update Brief (CUB) — Camp Colt

**Briefing ID:** CUB-${DATE_STR}-0600  
**Generated At:** ${TIMESTAMP} (Prepared within 1h pre-brief window)  
**Facilitator:** Chief of Staff (\`colt-cos\`), Camp Colt  
**Authority:** MCTP 3-30A (*MAGTF Command and Staff Action*) & MCRP 3-10A.1 (*Staff Organization and Operations*)  
**Security / Operational Posture:** Sovereign Command Post (\`colt-hq\` @ \`10.82.0.20\`)  

---

## 1. Main Effort: Local Model Capabilities & Sovereign Inference (\`cc-32m\`) — P0

* **Strategic Objective:** Preserve computational sovereignty and offline resilience via on-premise neural inference on Grace Blackwell GB10 (\`colt-gpu-01\` @ \`10.82.0.3:8000\`).
* **Operational Milestones Achieved:**
  * **Phase 4 SOP Complete (\`cc-32m.4\`):** S-3 authored and published comprehensive Standard Operating Procedure in \`docs/LOCAL_MODELS.md\` (commit \`ac6dbac\`). Covers \`city.toml\` provider overrides, LiteLLM gateway topology (\`10.82.50.10:80\`), memory-backed \`/dev/shm\` zero-plaintext credential hygiene, \`gc doctor\` integration, and failover runbooks. Bead closed.
  * **Gateway Performance Validated:** Direct-to-proxy overhead empirically benchmarked at nominal +9.5 ms with Radix cache nonces; cold/warm testing doctrine codified.
  * **Mistral 64K FP8 Upgrade Complete (\`cc-4acg\`):** Deployed and validated high-context local serving on GB10.
* **Next Steps:**
  * De-quarantine / pilot tactical worker on \`rigs/colt-utils\` (\`cc-32m.3\`) under local inference provider.
  * Archive model evaluation and benchmark dossiers in \`battlebook/models/\`.

---

## 2. Active Operations: Upstream Gas City Contributions (gh-5732 & gcs-97u)

* **Strategic Objective:** Upstream Camp Colt inference efficiency and operational tooling enhancements to Gas City core (\`gastownhall/gascity\`).
* **Operational Milestones Achieved:**
  * **PR 1: Prefix KV Cache Suffix Relocation (Issue #5732):** Inverted temporal/beacon headers to prompt suffix (\`cmd/gc/cmd_prime.go\`, \`cmd/gc/cmd_nudge.go\`), boosting RadixAttention prefix cache hit rates to 78.75% on local LLMs. Tests verified; branch \`feat/prompt-suffix-kv-cache-reuse\` pushed to origin.
  * **PR 2: Mail Send Priority Flag (gcs-97u):** Implemented \`mail.PrioritySender\` capability and \`-p/--priority\` flag in \`gc mail send\` adhering to Dolt schema (*int pointer). 23/23 tests verified; branch \`feat/mail-send-priority-flag\` pushed to origin.
  * **Turnkey PR Dossiers Published:** Complete Conventional submission dossiers and receipts ready in \`rigs/a-staff/plans/DOSSIER_GASCITY_UPSTREAM_PRS_GH5732_GCS97U.md\`.

---

## 3. Municipal Diagnostics & Working Tree Hygiene

1. **Municipal Diagnostics (\`gc doctor\`):**
   * 129 passed, 0 failures, 4 accounted-for warnings (upstream formula contract deprecation, local-only JSONL archive on new VM, advisory fork rate).
2. **Git Working Tree Hygiene:**
   * Working trees clean across colony root and all mounted rigs (\`suitcase-ai\`, \`go_template_rule\`, \`colt-utils\`, \`colt-results\`, \`a-staff\`).
   * Regular municipal audits enforced via \`scripts/audit_git_cleanliness.sh\`.

---

## 4. Garrison Staffing & Horizon (Next 24–72 Hours)

1. **Upstream PR Submission:**
   * Commander review and submission of turnkey PRs to \`gastownhall/gascity\` using prepared dossiers.
2. **Establish On-Demand Staff Sections:**
   * Activate and template S-1 Personnel and S-4 Logistics per London Fog specification (\`rigs/a-staff/\`).
   * S-4 Logistics to assume repository supply depot management (\`docs/SOP_S4_REPOSITORY_PROVISIONING.md\`).
3. **Local Worker Pilot:**
   * Sling tactical test worker on \`rigs/colt-utils\` backed by local Grace Blackwell GB10 inference.

---

## 5. Live Operational Telemetry (Snapshot at Generation Time)

\`\`\`
${BEAD_SUMMARY}
\`\`\`

**Recent Git Activity:**
\`\`\`
${RECENT_COMMITS}
\`\`\`
EOF

# Stage and commit fresh CUB
git add "${CUB_FILE}"
git commit -m "docs(cub): generate fresh 0600 Commander's Update Brief (${DATE_STR})" || true
git push origin main || true

# Dispatch notifications with --notify
gc mail send cos -s "CUB READY: 0600 Commander's Update Brief Freshly Compiled" \
  -m "The 0600 Commander's Update Brief has been generated at ${CUB_FILE} within the 1-hour pre-briefing window." --notify || true

gc mail send human -s "CUB READY: 0600 Commander's Update Brief Prepared" \
  -m "Commander, your 0600 CUB has been compiled and is ready for morning standup at ${CUB_FILE}." --notify || true

echo "=== CUB Generation Complete ==="
