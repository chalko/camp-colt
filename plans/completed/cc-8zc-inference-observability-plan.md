# Operational Plan: Sovereign Inference Observability & Grafana Dashboards

**Status:** Completed (Verified: 2026-09-24)
**Date:** 2026-09-23

---

## 1. Executive Summary & Operational Need

To fulfill the Command Directive requiring empirical verification across foundation model deployments, serving benchmarks, and autonomous agent runs, Camp Colt requires full end-to-end observability in Grafana for:

1. **Inference Gateway:** LiteLLM proxy routing, latency percentiles, error rates, and token throughput.
2. **Physical Accelerator (GX10 / colt-gpu-01):** DCGM telemetry covering Grace Blackwell GB10 VRAM footprint, power draw, temperature, and streaming multiprocessor (SM) utilization.
3. **Inference Backend (vLLM / NIM):** Time-to-First-Token (TTFT), inter-token latency, request queues, and Radix KV cache saturation.

This plan establishes the minimum viable metrics, PromQL expressions, and declarative GitOps specifications based on the proven London Fog pre-Colt Grafana dashboard reference (`configmap-dashboards.yaml`).

---

## 2. Minimum Viable Metrics Specification

### 2.1 LiteLLM Gateway Observability

Exposed by the LiteLLM proxy metrics endpoint (scraped by Prometheus):

| Telemetry Focus           | Metric Name                                   | Metric Type | PromQL Query                                                                                          | Purpose / Threshold              |
| :------------------------ | :-------------------------------------------- | :---------- | :---------------------------------------------------------------------------------------------------- | :------------------------------- |
| **Router Health**         | `up{job="litellm"}`                           | Gauge       | `up{job="litellm"}`                                                                                   | Binary service availability      |
| **In-Flight Requests**    | `litellm_in_flight_requests`                  | Gauge       | `sum(litellm_in_flight_requests)`                                                                     | Real-time queue concurrency      |
| **Total Requests**        | `litellm_requests_metric_total`               | Counter     | `sum(litellm_requests_metric_total)`                                                                  | Cumulative traffic volume        |
| **Request Rate by Model** | `litellm_requests_metric_total`               | Counter     | `sum(rate(litellm_requests_metric_total[1m])) by (model)`                                             | Throughput per model (req/s)     |
| **P95 Total Latency**     | `litellm_request_total_latency_metric_bucket` | Histogram   | `histogram_quantile(0.95, sum(rate(litellm_request_total_latency_metric_bucket[5m])) by (le)) * 1000` | SLA tracking (target $<1000$ ms) |
| **Input Token Rate**      | `litellm_input_tokens_metric_total`           | Counter     | `sum(rate(litellm_input_tokens_metric_total[1m]))`                                                    | Ingested prompt tok/s            |
| **Output Token Rate**     | `litellm_output_tokens_metric_total`          | Counter     | `sum(rate(litellm_output_tokens_metric_total[1m]))`                                                   | Generation tok/s                 |
| **Proxy Failure Count**   | `litellm_proxy_failed_requests_metric_total`  | Counter     | `sum(litellm_proxy_failed_requests_metric_total)`                                                     | Error tracking (5xx / 4xx)       |

### 2.2 Host & Hardware Accelerators (NVIDIA DCGM Exporter on `colt-gpu-01`)

Scraped from `nvidia-dcgm-exporter.monitoring.svc.cluster.local:9400`:

| Telemetry Focus       | Metric Name               | Metric Type | PromQL Query                                       | Alert / Operational SLA            |
| :-------------------- | :------------------------ | :---------- | :------------------------------------------------- | :--------------------------------- |
| **VRAM Footprint**    | `DCGM_FI_DEV_FB_USED`     | Gauge       | `sum(DCGM_FI_DEV_FB_USED{node="colt-gpu-01"})`     | Clamped $\le 0.75$ UMA (~96GB)     |
| **Power Draw**        | `DCGM_FI_DEV_POWER_USAGE` | Gauge       | `sum(DCGM_FI_DEV_POWER_USAGE{node="colt-gpu-01"})` | Thermal / PDU ceiling ($\le 220$W) |
| **GPU Core Thermals** | `DCGM_FI_DEV_GPU_TEMP`    | Gauge       | `max(DCGM_FI_DEV_GPU_TEMP{node="colt-gpu-01"})`    | Alert at $>75^\circ\text{C}$       |
| **SM Core Load**      | `DCGM_FI_DEV_GPU_UTIL`    | Gauge       | `avg(DCGM_FI_DEV_GPU_UTIL{node="colt-gpu-01"})`    | Processing saturation (%)          |

### 2.3 Local Foundation Model Backend (vLLM / NIM Engine)

Scraped from `nemotron-49b.nim-system.svc.cluster.local:8000/metrics`:

| Telemetry Focus             | Metric Name                               | Metric Type | PromQL Query                                                                                      | Operational SLA              |
| :-------------------------- | :---------------------------------------- | :---------- | :------------------------------------------------------------------------------------------------ | :--------------------------- |
| **Running Requests**        | `vllm:num_requests_running`               | Gauge       | `vllm:num_requests_running`                                                                       | Active parallel inference    |
| **Waiting Requests**        | `vllm:num_requests_waiting`               | Gauge       | `vllm:num_requests_waiting`                                                                       | Backlog queue saturation     |
| **Radix KV Cache Usage**    | `vllm:kv_cache_usage_perc`                | Gauge       | `vllm:kv_cache_usage_perc * 100`                                                                  | Alert at $>85\%$ saturation  |
| **Generation Speed**        | `vllm:generation_tokens_total`            | Counter     | `sum(rate(vllm:generation_tokens_total[1m]))`                                                     | Target $>80$ tok/s unbatched |
| **P95 Time-to-First-Token** | `vllm:time_to_first_token_seconds_bucket` | Histogram   | `histogram_quantile(0.95, sum(rate(vllm:time_to_first_token_seconds_bucket[5m])) by (le)) * 1000` | Target warm TTFT $<500$ ms   |
| **P95 E2E Latency**         | `vllm:e2e_request_latency_seconds_bucket` | Histogram   | `histogram_quantile(0.95, sum(rate(vllm:e2e_request_latency_seconds_bucket[5m])) by (le)) * 1000` | End-to-end user request SLA  |

---

## 3. Declarative Dashboard Architecture & Implementation

### 3.1 Dashboard Layout

We package two standardized dashboards into `provision/k8s/apps/monitoring/`:

1. **`litellm-dashboard.json`**:
   - Header Row: Status (up/down), In-Flight Requests, Total Requests Served, Failed Requests.
   - Traffic Row: Request rate timeseries stacked by model name (`nemotron-super-49b`, `sparkleader-default`).
   - Latency & Tokens Row: P95 latency curve (ms) side-by-side with Input vs. Output token throughput.
2. **`gx10-inference-dashboard.json` (Haze / GX10 adapted from London Fog):**
   - Hardware Row: GPU Utilization gauge, VRAM Allocation timeseries (GB), Power Draw (W), Core Temp (°C).
   - Engine Row: Active Running vs Waiting requests, KV Cache Utilization gauge (%), Sustained Tokens/sec timeseries, P95 TTFT and E2E latency.

### 3.2 GitOps Manifest Wiring

Platform Chief (`colt-sysadmin`) will wire these dashboards into the existing Flux `kube-prometheus-stack` deployment:

1. **ConfigMap Provisioning:**
   - Create `provision/k8s/apps/monitoring/configmap-inference-dashboards.yaml` containing the two dashboard JSON definitions.
   - Add label `grafana_dashboard: "1"` so Grafana's dashboard sidecar automatically discovers and imports them.
2. **Scrape Configs in `release.yaml`:**
   - Add `additionalScrapeConfigs` under `prometheusSpec` for:
     - `job_name: 'litellm'` targeting `litellm.colt.chalko.com` or cluster service.
     - `job_name: 'nim-engine'` targeting `nemotron-49b.nim-system.svc.cluster.local:8000`.

---

## 4. Division of Staff Responsibilities

1. **S-3 Operations:**
   - Author operational plan and PromQL metrics specifications (Completed).
   - Dispatch task order to Platform Chief via `gc mail` (Bead `cc-8zc`).
   - Validate live metrics scraping during subsequent benchmark runs.
2. **Platform Chief (`colt-sysadmin`):**
   - Stage `configmap-inference-dashboards.yaml` and Prometheus scrape targets in `rigs/suitcase-ai/provision/k8s/apps/monitoring/`.
   - Reconcile via Flux CD (`flux reconcile kustomization monitoring`).
   - Validate dashboards render correctly under anonymous read-only access at `http://grafana.colt.chalko.com`.
   - Report completion back to S-3.
