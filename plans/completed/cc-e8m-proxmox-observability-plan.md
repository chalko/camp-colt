# Operational Plan: Proxmox VE Hypervisor Observability & Grafana Dashboard

**Status:** Completed (Verified: 2026-09-24)
**Date:** 2026-09-23

---

## 1. Executive Summary & Operational Context

Camp Colt's control plane, security infrastructure (Vault), and co-located legacy workloads run as virtualized guests (QEMU VMs and LXC containers) on the **Minisforum UM760 Slim** hypervisor (`colt-cp-01` @ `10.82.0.2`, Proxmox VE 9.2).

To ensure continuous health monitoring, avoid memory starvation on the 32GB DDR5 host, and maintain situational awareness of both **Active** and **Cold Standby** VM states, this plan defines the metric schema and declarative Grafana dashboard layout for Proxmox VE, adapting the proven London Fog reference (`proxmox-dashboard.json`).

---

## 2. Minimum Viable Metrics Specification (Proxmox VE)

Telemetry is gathered by `prometheus-pve-exporter` (already deployed in namespace `monitoring` via `deployment-proxmox-exporter.yaml` and scraped on port 9221):

### 2.1 Hypervisor Node Telemetry (`colt-cp-01` / `misty`)

| Telemetry Focus         | Metric Name              | Metric Type | PromQL Query                                                                       | Operational Threshold        |
| :---------------------- | :----------------------- | :---------- | :--------------------------------------------------------------------------------- | :--------------------------- |
| **Hypervisor CPU Load** | `pve_cpu_usage_ratio`    | Gauge       | `pve_cpu_usage_ratio{id=~"node/.*"} * 100`                                         | Alert if sustained $>80\%$   |
| **Total Node Memory**   | `pve_memory_size_bytes`  | Gauge       | `pve_memory_size_bytes{id=~"node/.*"} / 1024^3`                                    | 32 GB physical ceiling       |
| **Used Node Memory**    | `pve_memory_usage_bytes` | Gauge       | `pve_memory_usage_bytes{id=~"node/.*"} / 1024^3`                                   | Maintain $\ge 4$ GB headroom |
| **Root Storage Usage**  | `pve_disk_usage_bytes`   | Gauge       | `(pve_disk_usage_bytes{id=~"node/.*"} / pve_disk_size_bytes{id=~"node/.*"}) * 100` | Alert if $>85\%$             |
| **Disk IOPS / Rate**    | `pve_disk_write_bytes`   | Counter     | `sum(rate(pve_disk_write_bytes{id=~"node/.*"}[5m]))`                               | NVMe wear / load tracking    |

### 2.2 Virtual Guest Telemetry (QEMU VMs & LXCs)

| Telemetry Focus             | Metric Name                  | Metric Type | PromQL Query                                                          | Operational Purpose                |
| :-------------------------- | :--------------------------- | :---------- | :-------------------------------------------------------------------- | :--------------------------------- |
| **Active Guest Inventory**  | `pve_up`                     | Gauge       | `count(pve_up{id=~"(qemu\|lxc)/.*"} == 1)`                            | Active running VM/LXC count        |
| **Cold Standby Inventory**  | `pve_up`                     | Gauge       | `count(pve_up{id=~"(qemu\|lxc)/.*"} == 0)`                            | Powered-off cold standby tracking  |
| **Guest Memory Allocation** | `pve_memory_usage_bytes`     | Gauge       | `pve_memory_usage_bytes{id=~"(qemu\|lxc)/.*"} / 1024^3`               | Breakdown across Colt & Fog guests |
| **Guest CPU Utilization**   | `pve_cpu_usage_ratio`        | Gauge       | `pve_cpu_usage_ratio{id=~"(qemu\|lxc)/.*"} * 100`                     | Per-guest CPU load                 |
| **Guest Disk Throughput**   | `pve_disk_write_bytes`       | Counter     | `rate(pve_disk_write_bytes{id=~"(qemu\|lxc)/.*"}[5m]) / 1024^2`       | Storage I/O (MB/s)                 |
| **Guest Network I/O**       | `pve_network_transmit_bytes` | Counter     | `rate(pve_network_transmit_bytes{id=~"(qemu\|lxc)/.*"}[5m]) / 1024^2` | Network throughput (MB/s)          |

---

## 3. Dashboard Layout & Architecture

The dashboard is structured into three visual tiers:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ 1. Executive Status Header                                                  │
│  [ CPU Load (%) ]  [ Active Guests ]  [ Standby Guests ]  [ Storage (%) ]   │
├─────────────────────────────────────────────────────────────────────────────┤
│ 2. Hypervisor Resource Trends (colt-cp-01)                                  │
│  - Total vs Used Host Memory (GB) over time                                 │
│  - Host CPU load and system load average timeseries                         │
├─────────────────────────────────────────────────────────────────────────────┤
│ 3. Guest Deep-Dive (Colt VMs: 9110, 9111, 9120, 9121, 9190 + Fog: 9010-9090)│
│  - Per-Guest Memory Allocation (stacked timeseries)                         │
│  - Per-Guest CPU Utilization (%)                                            │
│  - Network I/O (Receive / Transmit rates)                                   │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 4. GitOps Delivery & Staff Delegation

1. **Manifest File:** `rigs/suitcase-ai/provision/k8s/apps/monitoring/configmap-proxmox-dashboard.yaml`
2. **Labeling for Discovery:** Label ConfigMap with `grafana_dashboard: "1"` in namespace `monitoring`.
3. **Execution Assignment:**
   - Platform Chief (`colt-sysadmin`) stages `configmap-proxmox-dashboard.yaml` in `provision/k8s/apps/monitoring/`.
   - Reconciles via Flux CD (`clusters/camp-colt`).
   - Verifies dashboard is visible under anonymous read-only access at `http://grafana.colt.chalko.com`.
