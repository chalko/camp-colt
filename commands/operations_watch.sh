#!/usr/bin/env bash
# commands/operations_watch.sh
# Generic Operations Watch Patrol & Stagnation Detection Protocol
# S-3 Operations & S-6 Signal & Cyber Section — Camp Colt
# Governed under SOP_OPERATIONS_WATCH_AND_STAGNATION_DETECTION.md
#
# Invariants Enforced:
# 1. Zero LLM / Zero Token Footprint: 100% deterministic bash + jq.
# 2. Automated P1 Failure Escalation: Dual-alerts s6-signal and s3-operations on failure.
# 3. Dynamic State Ledger: Tracks active convoys, workers, and beads across intervals (.gc/runtime/watch/operations_watch_state.json).
# 4. Stagnation Detection Engine:
#    - Convoys: Tracks progress (closed/total) and active lead beads across intervals.
#    - Workstreams: Tracks both in_progress and assigned/routed open beads.
#    - 1-2 Stagnant Ticks (15-30m): Targeted session nudge to worker/assignee.
#    - 4 Stagnant Ticks (>=60m): Escalates [P1 ESCALATION] to Chief of Staff (cos).
#    - CoS Zero-Noise Invariant: Zero mail to CoS on normal progress (<4 stalls).
# 5. Continuous Operational Visibility:
#    - Replaces vanity bead counts with Active Convoys, Active Workers, and Active Workstreams.
#    - Overwrites operations_watch_summary.md and nudges S-3 Operations watch officer.

set -euo pipefail

CITY_ROOT="${GC_CITY:-/home/camp-colt-mayor-agent/colony}"
STATE_DIR="${CITY_ROOT}/.gc/runtime/watch"
LEDGER_FILE="${STATE_DIR}/operations_watch_state.json"
SUMMARY_FILE="${STATE_DIR}/operations_watch_summary.md"
LOG_FILE="${STATE_DIR}/watch.log"

mkdir -p "${STATE_DIR}" 2>/dev/null || true

log() {
    local msg="$1"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local line="[${timestamp}] ${msg}"
    echo "${line}"
    echo "${line}" >> "${LOG_FILE}" 2>/dev/null || true
}

handle_failure() {
    local line_no="$1"
    local exit_code="$2"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    echo "[${timestamp}] [CRITICAL] operations_watch.sh failed at line ${line_no} with exit code ${exit_code}" >&2

    local diagnostics="Timestamp: ${timestamp}
Script: commands/operations_watch.sh
Line: ${line_no}
Exit Code: ${exit_code}
Working Directory: ${PWD}
City Root: ${CITY_ROOT}"

    local subject="[P1] ALERT: operations_watch.sh Execution Failure (Line ${line_no}, Code ${exit_code})"

    # Dispatch to s6-signal
    local mail_output_s6
    mail_output_s6=$(gc mail send s6-signal --notify -s "${subject}" -m "${diagnostics}" --json 2>/dev/null || true)
    local bead_id_s6
    bead_id_s6=$(echo "${mail_output_s6}" | jq -r '.id // empty' 2>/dev/null || true)
    if [ -n "${bead_id_s6}" ]; then
        gc bd update "${bead_id_s6}" -p P1 >/dev/null 2>&1 || true
    fi

    # Dispatch to s3-operations
    local mail_output_s3
    mail_output_s3=$(gc mail send s3-operations --notify -s "${subject}" -m "${diagnostics}" --json 2>/dev/null || true)
    local bead_id_s3
    bead_id_s3=$(echo "${mail_output_s3}" | jq -r '.id // empty' 2>/dev/null || true)
    if [ -n "${bead_id_s3}" ]; then
        gc bd update "${bead_id_s3}" -p P1 >/dev/null 2>&1 || true
    fi
}

trap 'handle_failure $LINENO $?' ERR

DRY_RUN=false
for arg in "$@"; do
    case "${arg}" in
        --dry-run)
            DRY_RUN=true
            ;;
        --help|-h)
            echo "Usage: commands/operations_watch.sh [--dry-run]"
            exit 0
            ;;
        *)
            echo "Unknown argument: ${arg}" >&2
            false
            ;;
    esac
done

NOW_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Initialize or validate state ledger
if [ ! -f "${LEDGER_FILE}" ] || ! jq empty "${LEDGER_FILE}" 2>/dev/null; then
    echo '{"beads":{},"convoys":{},"last_run":null}' > "${LEDGER_FILE}"
fi

# 1. Phase 0: Check inbound unread mail for s3-operations
INBOUND_MAIL=$(gc mail inbox s3-operations --json 2>/dev/null || echo '{"messages":[]}')
UNREAD_COUNT=$(echo "${INBOUND_MAIL}" | jq '.messages | length' 2>/dev/null || echo '0')

# 2. Phase 1: Query active sessions and active convoys
SESSIONS_JSON=$(gc session list --json 2>/dev/null || echo '{"sessions":[]}')
SESSION_COUNT=$(echo "${SESSIONS_JSON}" | jq '.sessions | length' 2>/dev/null || echo '0')

ACTIVE_SESSION_MAP=$(echo "${SESSIONS_JSON}" | jq -c '
  [ .sessions[]? | select(.state == "active" and .closed != true) ] |
  reduce .[] as $s ({};
    (if $s.id then .[$s.id] = $s.id else . end) |
    (if $s.alias then .[$s.alias] = $s.id else . end) |
    (if $s.name then .[$s.name] = $s.id else . end) |
    (if $s.agent_name then .[$s.agent_name] = $s.id else . end) |
    (if $s.template then .[$s.template] = $s.id else . end)
  )
')

TACTICAL_WORKERS=$(echo "${SESSIONS_JSON}" | jq -c '
  [ .sessions[]? | select(.state == "active" and .closed != true and ((.template // "") | test("operator|worker|polecat|coder"))) ]
' 2>/dev/null || echo '[]')
TACTICAL_WORKER_COUNT=$(echo "${TACTICAL_WORKERS}" | jq 'length' 2>/dev/null || echo '0')

# Query active convoys
CONVOYS_RAW=$(gc convoy list --json 2>/dev/null || echo '{"convoys":[]}')
if [ -z "${CONVOYS_RAW}" ] || ! echo "${CONVOYS_RAW}" | jq empty 2>/dev/null; then
    CONVOYS_RAW='{"convoys":[]}'
fi
CONVOYS_LIST=$(echo "${CONVOYS_RAW}" | jq -c '
  if type == "object" and .convoys then .convoys
  elif type == "array" then .
  else [] end
' 2>/dev/null || echo '[]')
if [ -z "${CONVOYS_LIST}" ] || ! echo "${CONVOYS_LIST}" | jq empty 2>/dev/null; then
    CONVOYS_LIST='[]'
fi
CONVOY_CHILDREN=$(echo "${CONVOYS_LIST}" | jq -c '[ .[]?.child_ids[]? ] // []' 2>/dev/null || echo '[]')
if [ -z "${CONVOY_CHILDREN}" ] || ! echo "${CONVOY_CHILDREN}" | jq empty 2>/dev/null; then
    CONVOY_CHILDREN='[]'
fi

# 3. Phase 2: Query beads across rig scopes
CITY_BEADS=$(gc bd list --json 2>/dev/null || echo '[]')
if [ -z "${CITY_BEADS}" ] || ! echo "${CITY_BEADS}" | jq empty 2>/dev/null; then
    CITY_BEADS='[]'
fi
GASCITY_BEADS=$(gc bd --rig gascity list --json 2>/dev/null || echo '[]')
if [ -z "${GASCITY_BEADS}" ] || ! echo "${GASCITY_BEADS}" | jq empty 2>/dev/null; then
    GASCITY_BEADS='[]'
fi
SUITCASE_BEADS=$(gc bd --rig suitcase-ai list --json 2>/dev/null || echo '[]')
if [ -z "${SUITCASE_BEADS}" ] || ! echo "${SUITCASE_BEADS}" | jq empty 2>/dev/null; then
    SUITCASE_BEADS='[]'
fi

# Combine all unclosed non-message beads
ALL_UNCLOSED_BEADS=$(jq -c -n \
  --argjson city "${CITY_BEADS}" \
  --argjson gascity "${GASCITY_BEADS}" \
  --argjson suitcase "${SUITCASE_BEADS}" '
  [
    ($city[]?     | . + {rig: "city"}),
    ($gascity[]?  | . + {rig: "gascity"}),
    ($suitcase[]? | . + {rig: "suitcase-ai"})
  ] |
  [ .[] | select((.status == "in_progress" or .status == "open") and .issue_type != "message") ]
' 2>/dev/null || echo '[]')
if [ -z "${ALL_UNCLOSED_BEADS}" ] || ! echo "${ALL_UNCLOSED_BEADS}" | jq empty 2>/dev/null; then
    ALL_UNCLOSED_BEADS='[]'
fi

# Filter genuine active workstreams:
# 1. in_progress
# 2. open with an assignee or routed_to
# 3. child bead of an active convoy
COMBINED_BEADS=$(echo "${ALL_UNCLOSED_BEADS}" | jq -c --argjson cc "${CONVOY_CHILDREN}" '
  [ .[] | select(
    .status == "in_progress" or
    ((.assignee != null and .assignee != "" and .assignee != "-") or
     (.metadata["gc.routed_to"] != null and .metadata["gc.routed_to"] != "") or
     (.metadata["routed_to"] != null and .metadata["routed_to"] != "") or
     (.id as $bid | $cc | index($bid) != null))
  ) ]
' 2>/dev/null || echo '[]')
if [ -z "${COMBINED_BEADS}" ] || ! echo "${COMBINED_BEADS}" | jq empty 2>/dev/null; then
    COMBINED_BEADS='[]'
fi

TOTAL_UNCLOSED=$(echo "${ALL_UNCLOSED_BEADS}" | jq 'length')
BEAD_COUNT=$(echo "${COMBINED_BEADS}" | jq 'length')
BACKLOG_COUNT=$((TOTAL_UNCLOSED - BEAD_COUNT))
[ "${BACKLOG_COUNT}" -lt 0 ] && BACKLOG_COUNT=0

PREV_STATE=$(cat "${LEDGER_FILE}")
NEW_STATE_CONVOYS="{}"
NEW_STATE_BEADS="{}"
STAGNANT_NOTICES=0
ESCALATIONS_DISPATCHED=0

# --- Evaluate Active Convoys ---
CONVOY_ROWS=""
ACTIVE_CONVOY_COUNT=0

if [ "$(echo "${CONVOYS_LIST}" | jq 'length')" -gt 0 ]; then
    while read -r convoy_record; do
        [ -z "${convoy_record}" ] && continue

        c_id=$(echo "${convoy_record}" | jq -r '.id')
        c_title=$(echo "${convoy_record}" | jq -r '.title // "Untitled"')
        c_status=$(echo "${convoy_record}" | jq -r '.status // "open"')
        c_owner=$(echo "${convoy_record}" | jq -r '.fields.owner // "unassigned"')
        c_closed=$(echo "${convoy_record}" | jq -r '.progress.closed // 0')
        c_total=$(echo "${convoy_record}" | jq -r '.progress.total // 0')
        c_children=$(echo "${convoy_record}" | jq -c '.child_ids // []')

        # Only evaluate open convoys
        [ "${c_status}" != "open" ] && continue
        ACTIVE_CONVOY_COUNT=$((ACTIVE_CONVOY_COUNT + 1))

        # Identify active lead bead
        lead_bead=""
        for ch_id in $(echo "${c_children}" | jq -r '.[]'); do
            ch_status=$(echo "${COMBINED_BEADS}" | jq -r --arg cid "${ch_id}" '.[] | select(.id == $cid) | .status' 2>/dev/null || true)
            if [ "${ch_status}" = "in_progress" ]; then
                lead_bead="${ch_id} (in_progress)"
                break
            elif [ "${ch_status}" = "open" ] && [ -z "${lead_bead}" ]; then
                lead_bead="${ch_id} (open)"
            fi
        done
        [ -z "${lead_bead}" ] && lead_bead="none"

        prev_convoy=$(echo "${PREV_STATE}" | jq -r --arg id "${c_id}" '.convoys[$id] // empty' 2>/dev/null || true)
        c_stagnant_ticks=0
        c_escalated=false

        if [ -n "${prev_convoy}" ]; then
            prev_c_closed=$(echo "${prev_convoy}" | jq -r '.closed // 0')
            prev_c_ticks=$(echo "${prev_convoy}" | jq -r '.stagnant_ticks // 0')
            prev_c_esc=$(echo "${prev_convoy}" | jq -r '.escalated // false')

            if [ "${c_closed}" -eq "${prev_c_closed}" ]; then
                c_stagnant_ticks=$((prev_c_ticks + 1))
                c_escalated="${prev_c_esc}"
            else
                c_stagnant_ticks=0
                c_escalated=false
            fi
        fi

        c_status_display="Normal Progress"
        if [ "${c_stagnant_ticks}" -ge 4 ]; then
            c_status_display="CRITICAL STAGNATION (>=60m)"
            is_active_convoy=false
            if [ -n "${c_owner}" ] && [ "${c_owner}" != "unassigned" ] && [ "${c_owner}" != "-" ]; then
                is_active_convoy=true
            fi

            if [ "${is_active_convoy}" = true ] && [ "${c_escalated}" != "true" ]; then
                log "ESCALATION: Convoy ${c_id} stagnant for ${c_stagnant_ticks} ticks. Escalating to Chief of Staff."
                esc_subject="[P1 ESCALATION] Convoy Stagnation: ${c_id}"
                esc_body="Operations Watch Convoy Stagnation Escalation:
Convoy: ${c_id} (${c_title})
Owner: ${c_owner}
Progress: ${c_closed}/${c_total} closed
Active Lead Bead: ${lead_bead}
Stagnant Duration: ${c_stagnant_ticks} consecutive watch intervals (>=60m).
Action: S-3 Operations review and Command re-baselining required."

                if [ "${DRY_RUN}" = false ]; then
                    mail_res=$(gc mail send cos --notify -s "${esc_subject}" -m "${esc_body}" --json 2>/dev/null || true)
                    esc_id=$(echo "${mail_res}" | jq -r '.id // empty' 2>/dev/null || true)
                    if [ -n "${esc_id}" ]; then
                        gc bd update "${esc_id}" -p P1 >/dev/null 2>&1 || true
                    fi
                else
                    log "[DRY-RUN] Would escalate convoy to cos: ${esc_subject}"
                fi
                c_escalated=true
                ESCALATIONS_DISPATCHED=$((ESCALATIONS_DISPATCHED + 1))
            fi
        elif [ "${c_stagnant_ticks}" -ge 1 ]; then
            c_duration_min=$((c_stagnant_ticks * 15))
            c_status_display="Stagnant (${c_duration_min}m)"
            log "NOTICE: Convoy ${c_id} unchanged for ${c_stagnant_ticks} tick(s) (${c_duration_min}m)."
            STAGNANT_NOTICES=$((STAGNANT_NOTICES + 1))
        fi

        CONVOY_ROWS="${CONVOY_ROWS}
| \`${c_id}\` | ${c_title} | ${c_owner} | ${c_closed}/${c_total} closed | ${lead_bead} | ${c_status} | ${c_stagnant_ticks} | ${c_status_display} |"

        NEW_STATE_CONVOYS=$(echo "${NEW_STATE_CONVOYS}" | jq -c \
          --arg id "${c_id}" \
          --arg title "${c_title}" \
          --arg owner "${c_owner}" \
          --argjson closed "${c_closed}" \
          --argjson total "${c_total}" \
          --arg lead "${lead_bead}" \
          --argjson ticks "${c_stagnant_ticks}" \
          --argjson esc "${c_escalated}" '
          .[$id] = {
            id: $id,
            title: $title,
            owner: $owner,
            closed: $closed,
            total: $total,
            lead_bead: $lead,
            stagnant_ticks: $ticks,
            escalated: $esc
          }
        ')
    done < <(echo "${CONVOYS_LIST}" | jq -c '.[]')
fi

# --- Format Active Tactical Workers ---
WORKER_ROWS=""
if [ "${TACTICAL_WORKER_COUNT}" -gt 0 ]; then
    while read -r w_record; do
        [ -z "${w_record}" ] && continue
        w_id=$(echo "${w_record}" | jq -r '.id')
        w_template=$(echo "${w_record}" | jq -r '.template // "unknown"')
        w_dir=$(echo "${w_record}" | jq -r '.work_dir // "-"')
        w_state=$(echo "${w_record}" | jq -r '.state // "active"')
        w_created=$(echo "${w_record}" | jq -r '.created_at // "-"')

        WORKER_ROWS="${WORKER_ROWS}
| \`${w_id}\` | ${w_template} | ${w_dir} | ${w_state} | ${w_created} |"
    done < <(echo "${TACTICAL_WORKERS}" | jq -c '.[]')
fi

# --- Evaluate Active Workstreams (Beads) ---
SUMMARY_ROWS=""

if [ "${BEAD_COUNT}" -gt 0 ]; then
    while read -r bead_record; do
        [ -z "${bead_record}" ] && continue

        bead_id=$(echo "${bead_record}" | jq -r '.id')
        bead_title=$(echo "${bead_record}" | jq -r '.title // "Untitled"')
        bead_status=$(echo "${bead_record}" | jq -r '.status // "open"')
        bead_rig=$(echo "${bead_record}" | jq -r '.rig // "city"')
        bead_assignee=$(echo "${bead_record}" | jq -r '.assignee // ""')
        bead_updated=$(echo "${bead_record}" | jq -r '.updated_at // .created_at // ""')

        # Check stagnation against previous state
        prev_record=$(echo "${PREV_STATE}" | jq -r --arg id "${bead_id}" '.beads[$id] // empty' 2>/dev/null || true)

        stagnant_ticks=0
        escalated=false

        if [ -n "${prev_record}" ]; then
            prev_status=$(echo "${prev_record}" | jq -r '.status')
            prev_updated=$(echo "${prev_record}" | jq -r '.updated_at')
            prev_ticks=$(echo "${prev_record}" | jq -r '.stagnant_ticks // 0')
            prev_escalated=$(echo "${prev_record}" | jq -r '.escalated // false')

            if [ "${bead_status}" = "${prev_status}" ]; then
                if [ "${bead_updated}" = "${prev_updated}" ]; then
                    stagnant_ticks=$((prev_ticks + 1))
                    escalated="${prev_escalated}"
                else
                    stagnant_ticks=0
                    escalated=false
                fi
            else
                stagnant_ticks=0
                escalated=false
            fi
        fi

        # Evaluate Stagnation Interventions
        status_display="Normal Progress"
        if [ "${stagnant_ticks}" -ge 4 ]; then
            status_display="CRITICAL STAGNATION (>=60m)"
            is_active_workstream=false
            if [ "${bead_status}" = "in_progress" ] || { [ -n "${bead_assignee}" ] && [ "${bead_assignee}" != "unassigned" ] && [ "${bead_assignee}" != "-" ]; }; then
                is_active_workstream=true
            fi

            if [ "${is_active_workstream}" = true ] && [ "${escalated}" != "true" ]; then
                log "ESCALATION: Bead ${bead_id} stagnant for ${stagnant_ticks} ticks. Escalating to Chief of Staff."
                escalate_subject="[P1 ESCALATION] Workstream Stagnation: ${bead_id}"
                escalate_body="Operations Watch Stagnation Escalation:
Bead: ${bead_id} [${bead_rig}]
Title: ${bead_title}
Assignee: ${bead_assignee}
Status: ${bead_status}
Stagnant Duration: ${stagnant_ticks} consecutive watch intervals (>=60m).
Action: Chief of Staff intervention required."

                if [ "${DRY_RUN}" = false ]; then
                    mail_res=$(gc mail send cos --notify -s "${escalate_subject}" -m "${escalate_body}" --json 2>/dev/null || true)
                    esc_id=$(echo "${mail_res}" | jq -r '.id // empty' 2>/dev/null || true)
                    if [ -n "${esc_id}" ]; then
                        gc bd update "${esc_id}" -p P1 >/dev/null 2>&1 || true
                    fi
                else
                    log "[DRY-RUN] Would escalate to cos: ${escalate_subject}"
                fi
                escalated=true
                ESCALATIONS_DISPATCHED=$((ESCALATIONS_DISPATCHED + 1))
            fi
        elif [ "${stagnant_ticks}" -ge 1 ]; then
            duration_min=$((stagnant_ticks * 15))
            status_display="Stagnant (${duration_min}m)"
            log "NOTICE: Bead ${bead_id} unchanged for ${stagnant_ticks} tick(s) (${duration_min}m)."

            # Target worker / assignee session nudge
            target_sid=$(echo "${ACTIVE_SESSION_MAP}" | jq -r --arg a "${bead_assignee}" '.[$a] // empty')
            if [ -n "${target_sid}" ]; then
                nudge_msg="Operations Watch Stagnation Notice: Bead ${bead_id} has shown no progress for ${stagnant_ticks} interval(s) (${duration_min}m). Please verify worker status."
                if [ "${DRY_RUN}" = false ]; then
                    gc session nudge "${target_sid}" "${nudge_msg}" >/dev/null 2>&1 || true
                else
                    log "[DRY-RUN] Would nudge ${target_sid}: ${nudge_msg}"
                fi
                STAGNANT_NOTICES=$((STAGNANT_NOTICES + 1))
            fi
        fi

        # Append to summary table
        SUMMARY_ROWS="${SUMMARY_ROWS}
| \`${bead_id}\` | ${bead_rig} | ${bead_title} | ${bead_assignee:-unassigned} | ${bead_status} | ${stagnant_ticks} | ${status_display} |"

        # Record in new state
        NEW_STATE_BEADS=$(echo "${NEW_STATE_BEADS}" | jq -c \
          --arg id "${bead_id}" \
          --arg title "${bead_title}" \
          --arg status "${bead_status}" \
          --arg rig "${bead_rig}" \
          --arg assignee "${bead_assignee}" \
          --arg updated "${bead_updated}" \
          --argjson ticks "${stagnant_ticks}" \
          --argjson esc "${escalated}" '
          .[$id] = {
            id: $id,
            title: $title,
            status: $status,
            rig: $rig,
            assignee: $assignee,
            updated_at: $updated,
            stagnant_ticks: $ticks,
            escalated: $esc
          }
        ')

    done < <(echo "${COMBINED_BEADS}" | jq -c '.[]')
fi

# Write updated state ledger
NEW_STATE=$(jq -n \
  --arg last_run "${NOW_ISO}" \
  --argjson convoys "${NEW_STATE_CONVOYS}" \
  --argjson beads "${NEW_STATE_BEADS}" '
  {
    last_run: $last_run,
    convoys: $convoys,
    beads: $beads
  }
')
echo "${NEW_STATE}" > "${LEDGER_FILE}.tmp"
mv "${LEDGER_FILE}.tmp" "${LEDGER_FILE}"

# Overwrite markdown summary for instant human/officer visibility
cat << EOF > "${SUMMARY_FILE}"
# Camp Colt Operations Watch Summary

- **Last Watch Tick**: ${NOW_ISO}
- **Inbound Unread Mail (s3-operations)**: ${UNREAD_COUNT}
- **Active Convoys & OPORDs**: ${ACTIVE_CONVOY_COUNT}
- **Active Tactical Workers**: ${TACTICAL_WORKER_COUNT}
- **Active Workstreams Tracked**: ${BEAD_COUNT}
- **Backlog Queue (Unassigned)**: ${BACKLOG_COUNT}
- **Stagnation Notices**: ${STAGNANT_NOTICES}
- **Command Escalations**: ${ESCALATIONS_DISPATCHED}

## Active Convoys & OPORDs
| Convoy ID | Title | Owner | Progress | Active Lead Bead | Status | Stagnant Ticks | Stagnation Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |${CONVOY_ROWS:-
| None | - | No active convoys | - | - | Idle | 0 | Normal Progress |}

## Active Tactical Workers
| Session ID | Template | Target Workdir | Status | Freshness |
| :--- | :--- | :--- | :--- | :--- |${WORKER_ROWS:-
| None | - | - | No active tactical workers | - |}

## Active Workstreams Tracked
| Bead ID | Rig / Scope | Title | Assignee | Status | Stagnant Ticks | Stagnation Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |${SUMMARY_ROWS:-
| None | - | No active workstreams | - | - | 0 | Idle |}
EOF

# Notify Watch Officer (S-3 Operations session)
OFFICER_NUDGE="Operations Watch Patrol tick (${NOW_ISO}): Data gathered (${UNREAD_COUNT} unread mail, ${ACTIVE_CONVOY_COUNT} convoys, ${TACTICAL_WORKER_COUNT} workers, ${BEAD_COUNT} active beads, ${BACKLOG_COUNT} backlog). Watch Officer review required."

if [ "${DRY_RUN}" = false ]; then
    gc session nudge s3-operations "${OFFICER_NUDGE}" 2>/dev/null || true
else
    log "[DRY-RUN] Would nudge s3-operations: ${OFFICER_NUDGE}"
fi

log "Operations Watch Patrol completed successfully. Summary updated at ${SUMMARY_FILE}."
