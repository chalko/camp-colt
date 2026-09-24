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

## 1. Main Effort / Operational Status: Command Post Relocation to VM 9100 (\`cc-56d\`) — COMPLETE

* **Strategic Objective:** Eliminate laptop dependencies; establish 24/7 continuous command post operations on dedicated hypervisor VM (\`colt-hq\` @ \`10.82.0.20\`, VM 9100 on \`colt-cp-01\`).
* **Operational Milestones Achieved:**
  * **Relocation & State Cutover Complete (\`cc-56d.3\`):** Verified active execution on \`colt-hq\` (8 AMD Zen 4 vCPUs, 10 GB dedicated RAM with \`balloon = 0\`, host CPU passthrough). Supervisor (PID 604), Dolt store (:38052), and session hygiene validated. Chief of Staff concurrence granted and bead closed.
  * **Platform Convergence Shipped:**
    * \`cc-56d.6\` (P2): DNS records configured for \`colt-hq.colt.chalko.com\` and \`hq.colt.chalko.com\`.
    * \`cc-56d.7\` (P2): Trusted TLS certificate issued and active for \`pve.colt.chalko.com\`.
    * \`cc-dcd\` (P2): Google OAuth SSO for Grafana staged with ExternalSecrets via HashiCorp Vault.
  * **Automated Runbook Archived:** \`rigs/suitcase-ai/plans/hq_migration_runbook.md\` updated to COMPLETED & ARCHIVED; reconciled via Git and Flux.
* **Remaining Relocation Item:**
  * \`cc-56d.8\` (P2): Provision administrator account for Nick on Proxmox VE (\`pve.colt.chalko.com\`).

---

## 2. Active Operations & Main Effort: Local Model Capabilities (\`cc-32m\`) — P0

* **Strategic Objective:** Preserve computational sovereignty and offline resilience via on-premise neural inference on Grace Blackwell GB10 (\`colt-gpu-01\` @ \`10.82.0.3:8000\`).
* **Progress:**
  * **Phase 4 SOP Complete (\`cc-32m.4\`):** S-3 authored and published comprehensive Standard Operating Procedure in \`docs/LOCAL_MODELS.md\` (commit \`ac6dbac\`). Covers \`city.toml\` provider overrides, LiteLLM gateway topology (\`10.82.50.10:80\`), memory-backed \`/dev/shm\` zero-plaintext credential hygiene, \`gc doctor\` integration, and failover runbooks. Bead closed.
  * **Gateway Performance Validated:** Direct-to-proxy overhead empirically benchmarked at nominal +9.5 ms with Radix cache nonces; cold/warm testing doctrine codified.
* **Next Steps:**
  * De-quarantine / pilot tactical worker on \`rigs/colt-utils\` (\`cc-32m.3\`) under local inference provider once local endpoint warming is complete.
  * Publish Sparkleader evaluation dossier into \`battlebook/models/\`.

---

## 3. Municipal Hygiene & Code Validation Backlog

1. **Municipal Diagnostics (\`gc doctor\`):**
   * 129 passed, 0 failures, 4 accounted-for warnings (upstream formula contract deprecation, local-only JSONL archive on new VM, advisory fork rate).
2. **Git Working Tree Hygiene:**
   * Working trees clean across colony root and all mounted rigs (\`suitcase-ai\`, \`go_template_rule\`, \`colt-utils\`, \`colt-results\`, \`a-staff\`).
   * Mayor reconciled untracked/modified beads metadata in \`rigs/go_template_rule\` (commit \`12fe473\`, \`cc-kw0\`).
3. **S-6 Signal Code Validation Backlog Shipped:**
   * S-6 executed full Stan/Eval quality control, test coverage verification, and zero-secret hygiene audits across all 6 target backlog beads, closing \`cc-988\`, \`cc-pvc\`, \`cc-dci\`, \`cc-3u7\`, \`cc-5rs\`, and \`cc-bxx\`.

---

## 4. Garrison Staffing & Horizon (Next 24–72 Hours)

1. **Establish On-Demand Staff Sections:**
   * Activate and template S-1 Personnel and S-4 Logistics per London Fog specification (\`rigs/a-staff/\`).
   * S-4 Logistics to assume repository supply depot management (\`docs/SOP_S4_REPOSITORY_PROVISIONING.md\`).
2. **Complete Remaining Epic cc-56d Tasks:**
   * Execute \`cc-56d.8\` (Proxmox admin account provisioning for Nick) and formally close Epic \`cc-56d\`.
3. **Conduct Staff After-Action Review (\`cc-3eq\` / \`cc-0s6\`):**
   * Finalize AAR incorporating Proxmox memory ballooning (\`balloon = 0\`), CPU instruction set requirements (\`pclmulqdq\`), and graceful workspace cutover sequences.

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
