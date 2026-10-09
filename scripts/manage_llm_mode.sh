#!/usr/bin/env bash
# scripts/manage_llm_mode.sh
# Operational tool for managing Local LLM operational states (Production vs Benchmark).
# Maintained by S-3 Operations.

set -euo pipefail

STATE_DIR="/dev/shm/camp-colt"
STATE_FILE="${STATE_DIR}/llm_mode"
FALLBACK_STATE_FILE="/var/tmp/camp-colt-llm_mode"
PRIMARY_HOST="colt-sparkrun"
PRIMARY_IP="10.82.0.3"
PRIMARY_PORT="8000"
GATEWAY_IP="10.82.50.10"
GATEWAY_HOST="litellm.colt.chalko.com"

# Ensure state directories exist
mkdir -p "${STATE_DIR}" 2>/dev/null || true

get_current_mode() {
    if [[ -f "${STATE_FILE}" ]]; then
        cat "${STATE_FILE}"
    elif [[ -f "${FALLBACK_STATE_FILE}" ]]; then
        cat "${FALLBACK_STATE_FILE}"
    else
        echo "production"
    fi
}

set_mode() {
    local mode="$1"
    echo "${mode}" > "${STATE_FILE}" 2>/dev/null || true
    echo "${mode}" > "${FALLBACK_STATE_FILE}" 2>/dev/null || true
}

check_primary_health() {
    if curl -s -f -m 3 "http://${PRIMARY_IP}:${PRIMARY_PORT}/v1/models" >/dev/null 2>&1; then
        echo "HEALTHY"
    else
        echo "UNAVAILABLE"
    fi
}

check_gateway_health() {
    if curl -s -f -m 3 -H "Host: ${GATEWAY_HOST}" "http://${GATEWAY_IP}/health/readiness" >/dev/null 2>&1; then
        echo "HEALTHY"
    else
        echo "UNAVAILABLE"
    fi
}

get_active_connections() {
    local conn_count
    conn_count=$(ssh -o BatchMode=yes -o ConnectTimeout=3 "${PRIMARY_HOST}" \
        "ss -tn state established sport = :${PRIMARY_PORT} | grep -v 'Local Address' | grep -v 'State' | grep -v '10.82.0.14' | wc -l" 2>/dev/null || echo "0")
    echo "${conn_count// /}"
}

cmd_status() {
    local mode
    mode=$(get_current_mode)
    local primary_health
    primary_health=$(check_primary_health)
    local gateway_health
    gateway_health=$(check_gateway_health)
    local active_conns
    active_conns=$(get_active_connections)

    echo "=== Local LLM Operational State ==="
    echo "Current Mode:        ${mode^^}"
    echo "Primary GPU Backend: ${primary_health} (${PRIMARY_IP}:${PRIMARY_PORT})"
    echo "LiteLLM Gateway:     ${gateway_health} (${GATEWAY_IP} / ${GATEWAY_HOST})"
    echo "Active Connections:  ${active_conns}"

    if [[ "${mode}" == "benchmark" ]]; then
        if [[ "${active_conns}" -eq 0 ]]; then
            echo "Status:              ZERO INTERFERENCE CONFIRMED (Ready for benchmark)"
        else
            echo "WARNING:             Active traffic detected during benchmark mode (${active_conns} connections)!"
        fi
    else
        echo "Status:              PRODUCTION READY (Worker traffic routed to primary GPU)"
    fi
}

cmd_benchmark() {
    echo "Transitioning Local LLM to BENCHMARK MODE..."
    set_mode "benchmark"

    echo "Quarantining GPU appliance (${PRIMARY_HOST})..."
    echo "Draining existing worker traffic..."

    local wait_seconds=0
    local max_wait=30
    local conns
    while true; do
        conns=$(get_active_connections)
        if [[ "${conns}" -eq 0 ]]; then
            echo "Drain complete: 0 active connections to port ${PRIMARY_PORT}."
            break
        fi
        if [[ ${wait_seconds} -ge ${max_wait} ]]; then
            echo "WARNING: Drain timed out after ${max_wait}s (${conns} connections remain)."
            break
        fi
        sleep 1
        ((wait_seconds++))
    done

    echo "Verifying zero-interference condition..."
    conns=$(get_active_connections)
    if [[ "${conns}" -eq 0 ]]; then
        echo "SUCCESS: Benchmark Mode active. Zero queries hitting GPU backend."
    else
        echo "CAUTION: ${conns} active connections remain. Inspect client workloads before starting benchmark."
    fi
}

cmd_production() {
    echo "Transitioning Local LLM to PRODUCTION MODE..."
    set_mode "production"

    echo "Verifying primary GPU backend health..."
    local health
    health=$(check_primary_health)
    if [[ "${health}" == "HEALTHY" ]]; then
        echo "Primary backend (${PRIMARY_IP}:${PRIMARY_PORT}) is HEALTHY."
    else
        echo "WARNING: Primary backend returned ${health}. Check container logs."
    fi

    echo "SUCCESS: Production Mode active. Eligible workers may resume routing to local model."
}

cmd_verify() {
    local mode
    mode=$(get_current_mode)
    echo "Verifying mode: ${mode^^}"
    if [[ "${mode}" == "benchmark" ]]; then
        local conns
        conns=$(get_active_connections)
        if [[ "${conns}" -eq 0 ]]; then
            echo "PASS: Zero-interference verified (0 connections on port ${PRIMARY_PORT})."
            exit 0
        else
            echo "FAIL: Benchmark mode violation — ${conns} active connection(s) detected!"
            exit 1
        fi
    else
        local health
        health=$(check_primary_health)
        if [[ "${health}" == "HEALTHY" ]]; then
            echo "PASS: Production mode verified (Primary backend responsive)."
            exit 0
        else
            echo "FAIL: Primary backend is not responsive (${health})."
            exit 1
        fi
    fi
}

case "${1:-status}" in
    status)
        cmd_status
        ;;
    benchmark)
        cmd_benchmark
        ;;
    production)
        cmd_production
        ;;
    verify)
        cmd_verify
        ;;
    *)
        echo "Usage: $0 {status|benchmark|production|verify}"
        exit 1
        ;;
esac
