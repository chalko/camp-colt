#!/usr/bin/env bash
# commands/signal_mail_watch.sh
# Automated 5-Minute Signal Mail Watchdog & Priority Nudge Engine
# S-6 Signal & Cyber Section — Camp Colt
# Governed under SOP_SIGNAL_COMMUNICATIONS_WATCH_AND_PRIORITY_DELIVERY.md
#
# Invariants Enforced:
# 1. Zero LLM / Zero Token Footprint: 100% deterministic bash + jq.
# 2. Automated Failure Escalation: Dispatches P1 gc mail --notify to s6-signal on any failure.
# 3. Graduated Priority Thresholds:
#    - P0 (Immediate): > 0m unread
#    - P1 (High):      > 15m unread
#    - P2 (Normal):    > 1h unread
#    - P3 (Low):       > 8h unread
#    - P4 (Deferred):  > 24h unread
# 4. State Ledger & Idempotency: Prevents duplicate nudges within cooldown windows (15m).

set -euo pipefail

CITY_ROOT="${GC_CITY:-/home/camp-colt-mayor-agent/colony}"
STATE_DIR="${CITY_ROOT}/.gc/runtime/watch"
LEDGER_FILE="${STATE_DIR}/signal_mail_watch_state.json"
LOG_FILE="${STATE_DIR}/signal_mail_watch.log"
COOLDOWN_SECONDS=900  # 15 minutes

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

    echo "[${timestamp}] [CRITICAL] signal_mail_watch.sh failed at line ${line_no} with exit code ${exit_code}" >&2

    local diagnostics="Timestamp: ${timestamp}
Script: commands/signal_mail_watch.sh
Line: ${line_no}
Exit Code: ${exit_code}
Working Directory: ${PWD}
City Root: ${CITY_ROOT}"

    local subject="[P1] ALERT: signal_mail_watch.sh Execution Failure (Line ${line_no}, Code ${exit_code})"

    local mail_output
    mail_output=$(gc mail send s6-signal --notify -s "${subject}" -m "${diagnostics}" --json 2>/dev/null || true)

    local bead_id
    bead_id=$(echo "${mail_output}" | jq -r '.id // empty' 2>/dev/null || true)
    if [ -n "${bead_id}" ]; then
        gc bd update "${bead_id}" -p P1 >/dev/null 2>&1 || true
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
            echo "Usage: commands/signal_mail_watch.sh [--dry-run]"
            exit 0
            ;;
        *)
            echo "Unknown argument: ${arg}" >&2
            false
            ;;
    esac
done

NOW_SEC=$(date +%s)
NOW_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Initialize or validate state ledger
if [ ! -f "${LEDGER_FILE}" ] || ! jq empty "${LEDGER_FILE}" 2>/dev/null; then
    echo '{"nudges":{},"last_run":null}' > "${LEDGER_FILE}"
fi

# 1. Query active sessions
SESSIONS_JSON=$(gc session list --json)
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

# 2. Query open message beads
MESSAGES_JSON=$(gc bd list --type message --status open --json)

log "Signal Mail Watch scan started. Scanning unread messages."

# Filter breached messages and output JSON lines:
BREACHED_JSONL=$(echo "${MESSAGES_JSON}" | jq -c --argjson now "${NOW_SEC}" '
  .[] |
  # Exclude messages already marked as read
  select((.metadata["mail.read"] // "") != "true" and ((.labels // []) | index("read") | not)) |
  # Detect priority (native field takes precedence, then bracketed tags, then keywords)
  (
    if (.priority != null and (.priority | tostring | test("^[0-4]$"))) then
      (.priority | tostring | tonumber)
    elif (.priority != null and (.priority | tostring | test("^P[0-4]$"; "i"))) then
      (.priority | tostring | sub("^P"; ""; "i") | tonumber)
    elif ((.title // "") | test("\\[P0\\]")) then 0
    elif ((.title // "") | test("\\[P1\\]")) then 1
    elif ((.title // "") | test("\\[P2\\]")) then 2
    elif ((.title // "") | test("\\[P3\\]")) then 3
    elif ((.title // "") | test("\\[P4\\]")) then 4
    elif ((.title // "") | test("\\b(URGENT|CRITICAL)\\b"; "i")) then 0
    elif ((.title // "") | test("\\b(PRIORITY|ALERT)\\b"; "i")) then 1
    elif ((.title // "") | test("\\bFYI\\b"; "i")) then 4
    else 2
    end
  ) as $prio |
  # Parse created_at to epoch seconds
  ((.created_at | sub("\\.[0-9]+"; "") | fromdateiso8601?) // 0) as $created |
  ($now - $created) as $age |
  (
    if $prio == 0 then 0
    elif $prio == 1 then 900
    elif $prio == 2 then 3600
    elif $prio == 3 then 28800
    elif $prio == 4 then 86400
    else 3600
    end
  ) as $thresh |
  select($age >= $thresh) |
  {
    id: .id,
    recipient: (.assignee // .metadata["gc.routed_to"] // .metadata["gc.run_target"] // .metadata["mail.to"] // ""),
    sender: (.sender // .metadata["mail.from_display"] // "unknown"),
    priority: $prio,
    age_min: ($age / 60 | floor)
  }
')

NUDGES_DISPATCHED=0

if [ -n "${BREACHED_JSONL}" ]; then
    while read -r record; do
        [ -z "${record}" ] && continue

        msg_id=$(echo "${record}" | jq -r '.id')
        recipient=$(echo "${record}" | jq -r '.recipient')
        sender=$(echo "${record}" | jq -r '.sender')
        prio=$(echo "${record}" | jq -r '.priority')
        age_min=$(echo "${record}" | jq -r '.age_min')

        [ -z "${msg_id}" ] && continue

        # Check cooldown in ledger
        last_nudged=$(jq -r --arg id "${msg_id}" '.nudges[$id] // 0' "${LEDGER_FILE}" 2>/dev/null || echo 0)
        time_since_last=$((NOW_SEC - last_nudged))
        if [ "${time_since_last}" -lt "${COOLDOWN_SECONDS}" ]; then
            continue
        fi

        # Check active session for recipient
        target_sid=$(echo "${ACTIVE_SESSION_MAP}" | jq -r --arg r "${recipient}" '.[$r] // empty')
        if [ -z "${target_sid}" ]; then
            log "Notice: Recipient '${recipient}' has no active session; skipping session nudge."
            continue
        fi

        # Format age display
        if [ "${age_min}" -lt 60 ]; then
            age_display="${age_min}m"
        else
            hours=$((age_min / 60))
            rem_min=$((age_min % 60))
            if [ "${rem_min}" -gt 0 ]; then
                age_display="${hours}h${rem_min}m"
            else
                age_display="${hours}h"
            fi
        fi

        nudge_text="Unread [P${prio}] mail ${msg_id} from ${sender} pending ${age_display}. Process via gc mail read ${msg_id}."

        log "BREACH: P${prio} mail ${msg_id} to ${recipient} (age ${age_display}). Targeting session ${target_sid}."

        if [ "${DRY_RUN}" = false ]; then
            if gc session nudge "${target_sid}" "${nudge_text}" >/dev/null 2>&1; then
                # Record in state ledger
                jq --arg id "${msg_id}" --argjson ts "${NOW_SEC}" '.nudges[$id] = $ts' "${LEDGER_FILE}" > "${LEDGER_FILE}.tmp"
                mv "${LEDGER_FILE}.tmp" "${LEDGER_FILE}"
                NUDGES_DISPATCHED=$((NUDGES_DISPATCHED + 1))
            else
                log "Error: Failed to nudge session ${target_sid} for message ${msg_id}."
            fi
        else
            log "[DRY-RUN] Would nudge ${target_sid}: ${nudge_text}"
            NUDGES_DISPATCHED=$((NUDGES_DISPATCHED + 1))
        fi

    done <<< "${BREACHED_JSONL}"
fi

# Prune ledger entries older than 48 hours (172800s) and update last_run
CUTOFF_SEC=$((NOW_SEC - 172800))
jq --argjson cutoff "${CUTOFF_SEC}" --arg last_run "${NOW_ISO}" '
  .last_run = $last_run |
  .nudges |= with_entries(select(.value >= $cutoff))
' "${LEDGER_FILE}" > "${LEDGER_FILE}.tmp" 2>/dev/null && mv "${LEDGER_FILE}.tmp" "${LEDGER_FILE}"

log "Signal Mail Watch completed. Dispatched ${NUDGES_DISPATCHED} nudges."
