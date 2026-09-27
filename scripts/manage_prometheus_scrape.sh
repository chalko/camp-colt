#!/usr/bin/env bash
# scripts/manage_prometheus_scrape.sh
# Operational tool for dynamically adjusting Prometheus scrape intervals during missions.
# Allows switching vLLM/NIM, LiteLLM, and DCGM scrape intervals to 5s for fine-grained
# telemetry during benchmark execution, and restoring to 30s baseline afterwards.
# Maintained by Platform Chief (colt-sysadmin) & S-3 Operations.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLONY_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

KUBECONFIG_PATH="${KUBECONFIG:-${COLONY_ROOT}/rigs/suitcase-ai/colt-kubeconfig}"
NAMESPACE="monitoring"
SECRET_NAME="kube-prometheus-stack-prometheus-scrape-confg"
SECRET_KEY="additional-scrape-configs.yaml"
PROMETHEUS_POD="prometheus-kube-prometheus-stack-prometheus-0"

STATE_DIR="/dev/shm/camp-colt"
STATE_FILE="${STATE_DIR}/prometheus_scrape_mode"
mkdir -p "${STATE_DIR}" 2>/dev/null || true

check_prereqs() {
    if [[ ! -f "${KUBECONFIG_PATH}" ]]; then
        if [[ -f "${COLONY_ROOT}/rigs/suitcase-ai/colt-kubeconfig" ]]; then
            KUBECONFIG_PATH="${COLONY_ROOT}/rigs/suitcase-ai/colt-kubeconfig"
        else
            echo "ERROR: Kubeconfig not found" >&2
            exit 1
        fi
    fi
    if ! KUBECONFIG="${KUBECONFIG_PATH}" kubectl -n "${NAMESPACE}" get secret "${SECRET_NAME}" >/dev/null 2>&1; then
        echo "ERROR: Cannot reach cluster or secret ${SECRET_NAME} in namespace ${NAMESPACE}" >&2
        exit 1
    fi
}

generate_scrape_yaml() {
    local mode="$1"
    local interval="${2:-5s}"
    local timeout="${3:-4s}"

    if [[ "${mode}" == "mission" ]]; then
        cat <<YAML
- job_name: nvidia-dcgm
  scrape_interval: ${interval}
  scrape_timeout: ${timeout}
  static_configs:
  - labels:
      node: colt-gpu-01
    targets:
    - nvidia-dcgm-exporter.monitoring.svc.cluster.local:9400
- job_name: proxmox-exporter
  metrics_path: /pve
  params:
    target:
    - 10.82.0.2
  static_configs:
  - targets:
    - proxmox-exporter.monitoring.svc.cluster.local:9221
- job_name: litellm
  scrape_interval: ${interval}
  scrape_timeout: ${timeout}
  metrics_path: /metrics/
  static_configs:
  - targets:
    - litellm.litellm.svc.cluster.local:4000
- job_name: nim-engine
  scrape_interval: ${interval}
  scrape_timeout: ${timeout}
  static_configs:
  - labels:
      node: colt-gpu-01
    targets:
    - nemotron-49b.nim-system.svc.cluster.local:8000
YAML
    else
        cat <<YAML
- job_name: nvidia-dcgm
  static_configs:
  - labels:
      node: colt-gpu-01
    targets:
    - nvidia-dcgm-exporter.monitoring.svc.cluster.local:9400
- job_name: proxmox-exporter
  metrics_path: /pve
  params:
    target:
    - 10.82.0.2
  static_configs:
  - targets:
    - proxmox-exporter.monitoring.svc.cluster.local:9221
- job_name: litellm
  metrics_path: /metrics/
  static_configs:
  - targets:
    - litellm.litellm.svc.cluster.local:4000
- job_name: nim-engine
  static_configs:
  - labels:
      node: colt-gpu-01
    targets:
    - nemotron-49b.nim-system.svc.cluster.local:8000
YAML
    fi
}

cmd_status() {
    check_prereqs
    echo "=== Prometheus Telemetry Scrape Status ==="
    echo "Cluster Secret: ${NAMESPACE}/${SECRET_NAME}"
    echo "Kubeconfig:     ${KUBECONFIG_PATH}"
    echo "------------------------------------------"

    local current_yaml
    current_yaml=$(KUBECONFIG="${KUBECONFIG_PATH}" kubectl -n "${NAMESPACE}" get secret "${SECRET_NAME}" -o json | jq -r ".data[\"${SECRET_KEY}\"]" | base64 -d)

    echo "Active Scrape Jobs in Secret:"
    echo "${current_yaml}" | grep -E "job_name|scrape_interval" | while read -r line; do
        echo "  ${line}"
    done
    echo "------------------------------------------"

    if echo "${current_yaml}" | grep -q "scrape_interval: 5s"; then
        echo "Active Mode: HIGH-RESOLUTION MISSION MODE (5s scrape cadence)"
    elif echo "${current_yaml}" | grep -q "scrape_interval:"; then
        local custom_interval
        custom_interval=$(echo "${current_yaml}" | grep "scrape_interval:" | head -n1 | awk '{print $2}')
        echo "Active Mode: CUSTOM SCRAPE CADENCE (${custom_interval})"
    else
        echo "Active Mode: DEFAULT PRODUCTION BASELINE (30s default cadence)"
    fi
}

cmd_set_mission() {
    local interval="${1:-5s}"
    local timeout="${2:-4s}"
    local dry_run="${3:-false}"

    check_prereqs
    echo "Preparing to set Prometheus scrape interval to ${interval} (timeout ${timeout})..."

    local new_yaml
    new_yaml=$(generate_scrape_yaml "mission" "${interval}" "${timeout}")

    if [[ "${dry_run}" == "true" ]]; then
        echo "=== DRY-RUN: Generated Secret YAML ==="
        echo "${new_yaml}"
        return 0
    fi

    KUBECONFIG="${KUBECONFIG_PATH}" kubectl -n "${NAMESPACE}" create secret generic "${SECRET_NAME}" \
        --from-literal="${SECRET_KEY}=${new_yaml}" \
        --dry-run=client -o yaml | KUBECONFIG="${KUBECONFIG_PATH}" kubectl apply -f -

    echo "high-res-${interval}" > "${STATE_FILE}" 2>/dev/null || true
    echo "Successfully applied ${interval} scrape cadence to ${SECRET_NAME}."
    echo "Waiting 3 seconds for prometheus-config-reloader to pick up changes..."
    sleep 3
    KUBECONFIG="${KUBECONFIG_PATH}" kubectl -n "${NAMESPACE}" logs "${PROMETHEUS_POD}" -c config-reloader --tail=3 || true
}

cmd_restore_default() {
    local dry_run="${1:-false}"

    check_prereqs
    echo "Restoring Prometheus scrape interval to default 30s baseline..."

    local new_yaml
    new_yaml=$(generate_scrape_yaml "default")

    if [[ "${dry_run}" == "true" ]]; then
        echo "=== DRY-RUN: Generated Secret YAML ==="
        echo "${new_yaml}"
        return 0
    fi

    KUBECONFIG="${KUBECONFIG_PATH}" kubectl -n "${NAMESPACE}" create secret generic "${SECRET_NAME}" \
        --from-literal="${SECRET_KEY}=${new_yaml}" \
        --dry-run=client -o yaml | KUBECONFIG="${KUBECONFIG_PATH}" kubectl apply -f -

    echo "default-30s" > "${STATE_FILE}" 2>/dev/null || true
    echo "Successfully restored default scrape cadence to ${SECRET_NAME}."
    echo "Waiting 3 seconds for prometheus-config-reloader to pick up changes..."
    sleep 3
    KUBECONFIG="${KUBECONFIG_PATH}" kubectl -n "${NAMESPACE}" logs "${PROMETHEUS_POD}" -c config-reloader --tail=3 || true
}

usage() {
    cat <<EOF
Usage: $0 [command] [options]

Commands:
  status                     Show current Prometheus scrape configuration and mode
  enable-mission [interval]  Set high-resolution scrape interval (default: 5s, timeout 4s)
  restore-default            Restore default production scrape interval (30s)

Options:
  --dry-run                  Preview YAML changes without applying to cluster

Examples:
  $0 status
  $0 enable-mission 5s
  $0 enable-mission 5s --dry-run
  $0 restore-default
EOF
}

case "${1:-status}" in
    status)
        cmd_status
        ;;
    enable-mission|high-res|set)
        interval="${2:-5s}"
        dry_run="false"
        if [[ "${interval}" == "--dry-run" ]] || [[ "${3:-}" == "--dry-run" ]]; then
            dry_run="true"
            interval="5s"
        fi
        cmd_set_mission "${interval}" "4s" "${dry_run}"
        ;;
    restore-default|restore|default)
        dry_run="false"
        if [[ "${2:-}" == "--dry-run" ]]; then
            dry_run="true"
        fi
        cmd_restore_default "${dry_run}"
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        echo "Unknown command: $1" >&2
        usage
        exit 1
        ;;
esac
