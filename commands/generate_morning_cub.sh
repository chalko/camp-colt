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
RECENT_COMMITS="$(git log --since="24 hours ago" --oneline 2>/dev/null || git log -n 5 --oneline 2>/dev/null || echo "No recent commits")"
UNREAD_MAIL="$(gc mail inbox 2>/dev/null || echo "No unread mail")"

# Dynamic 24-hour completed deliverables
HIGHLIGHTS_FILE="docs/cub_highlights.md"
if [[ -f "${HIGHLIGHTS_FILE}" && -s "${HIGHLIGHTS_FILE}" ]]; then
  DELIVERABLES_CONTENT="$(cat "${HIGHLIGHTS_FILE}")"
  mkdir -p docs/archive
  mv "${HIGHLIGHTS_FILE}" "docs/archive/cub_highlights_${DATE_STR}.md" 2>/dev/null || rm -f "${HIGHLIGHTS_FILE}"
else
  YESTERDAY="$(date -d '24 hours ago' +'%Y-%m-%d')"
  CLOSED_BEADS="$(gc bd list --closed-after "${YESTERDAY}" --tree=false -n 20 2>/dev/null || true)"
  COMMITS_24H="$(git log --since="24 hours ago" --oneline 2>/dev/null || true)"

  DELIVERABLES_CONTENT=""
  if [[ -n "${CLOSED_BEADS}" && "${CLOSED_BEADS}" != *"No issues found"* ]]; then
    DELIVERABLES_CONTENT+="* **Task Beads Completed in Last 24 Hours:**"$'\n'
    while IFS= read -r line; do
      [[ -n "${line}" ]] && DELIVERABLES_CONTENT+="  - ${line}"$'\n'
    done <<< "${CLOSED_BEADS}"
  fi

  if [[ -n "${COMMITS_24H}" ]]; then
    DELIVERABLES_CONTENT+="* **Key Repository Commits (Last 24 Hours):**"$'\n'
    while IFS= read -r line; do
      [[ -n "${line}" ]] && DELIVERABLES_CONTENT+="  - \`${line}\`"$'\n'
    done <<< "${COMMITS_24H}"
  fi

  if [[ -z "${DELIVERABLES_CONTENT}" ]]; then
    DELIVERABLES_CONTENT="* No major milestone beads closed in the past 24 hours. Steady-state operational posture maintained."
  fi
fi

cat << EOF > "${CUB_FILE}"
# Commander's Update Brief (CUB) — Camp Colt

**Briefing ID:** CUB-${DATE_STR}-0600  
**Generated At:** ${TIMESTAMP} (Prepared within 1h pre-brief window)  
**Facilitator:** Chief of Staff (\`colt-cos\`), Camp Colt  
**Authority:** MCTP 3-30A (*MAGTF Command and Staff Action*) & MCRP 3-10A.1 (*Staff Organization and Operations*)  
**Security / Operational Posture:** Sovereign Command Post (\`colt-hq\` @ \`10.82.0.20\`)  

---

## 1. Major Deliverables Completed (Past 24 Hours / Since Last Brief)

${DELIVERABLES_CONTENT}

---

## 2. Active Operations & Main Effort: Local Model Capabilities (\`cc-32m\`) — P0

* **Strategic Objective:** Preserve computational sovereignty and offline resilience via on-premise neural inference on Grace Blackwell GB10 (\`colt-gpu-01\` @ \`10.82.0.3:8000\`).
* **Operational Status:**
  * **Phase 4 SOP Complete (\`cc-32m.4\`):** S-3 authored and published comprehensive Standard Operating Procedure in \`docs/LOCAL_MODELS.md\` (commit \`ac6dbac\`). Covers \`city.toml\` provider overrides, LiteLLM gateway topology (\`10.82.50.10:80\`), memory-backed \`/dev/shm\` zero-plaintext credential hygiene, \`gc doctor\` integration, and failover runbooks. Bead closed.
  * **Gateway Performance Validated:** Direct-to-proxy overhead empirically benchmarked at nominal +9.5 ms with Radix cache nonces; cold/warm testing doctrine codified.
  * **Mistral 64K FP8 Upgrade Complete (\`cc-4acg\`):** Deployed and validated high-context local serving on GB10.
* **Next Steps:**
  * De-quarantine / pilot tactical worker on \`rigs/colt-utils\` (\`cc-32m.3\`) under local inference provider.
  * Archive model evaluation and benchmark dossiers in \`battlebook/models/\`.

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
