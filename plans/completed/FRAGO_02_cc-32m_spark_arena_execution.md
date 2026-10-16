# Fragmentary Order (FRAGO) 02 to OPORD cc-32m: Spark Arena Benchmark Execution (llama-benchy)

**Status:** Completed
**Date:** 2026-09-24

---

## 1. Situation & Purpose

1. **Strategic Intent**: Execute standardized hardware inference benchmarking for the **Spark Arena Leaderboard** ([spark-arena.com](https://spark-arena.com/)) on our sovereign ASUS Ascent GX10 (NVIDIA Grace Blackwell GB10) accelerator (`colt-gpu-01`).
2. **Clarification of Intent**: Previous testing under FRAGO 01 addressed internal agent behavioral suites. This order refocuses operational execution specifically on the official community standard: **`llama-benchy`** raw inference metrics (TTFT, TPS, and concurrency latency) adhering to the Spark Arena recipe specification.
3. **Execution Vehicle**: The in-cluster Kubernetes benchmark job located at [`rigs/suitcase-ai/provision/k8s/apps/inference/benchmarks/llama-benchy-job.yaml`](../../suitcase-ai/provision/k8s/apps/inference/benchmarks/llama-benchy-job.yaml).

---

## 2. Mandatory Command Review & Publication Gate (STRICT HOLD)

> [!IMPORTANT] > **LOCAL REVIEW GATE ONLY — ZERO PREMATURE EXTERNAL EGRESS**
>
> 1. All benchmark receipts (`results.csv` and compiled `recipe.yaml`) MUST be harvested and compiled into a local review dossier.
> 2. The dossier must be submitted to the Commander via the Chief of Staff for **personal review and sign-off locally**.
> 3. **NO EXTERNAL PUBLICATION** to `spark-arena.com`, public registries, or external communications channels is authorized until the Commander personally approves the results post-review.

---

## 3. Tasks to Staff Sections

### A. S-3 Operations (`s3-operations`) — Tactical Lead

1. **Mandatory Preflight Gate**: Execute and assert that the `spark-to-k8s` recipe synchronization suite passes (`go test -v -run TestSync_Nemotron49bManifestVsRecipe ./...` in `rigs/suitcase-ai/tools/spark-to-k8s`). If declarative `recipe.yaml` and active Kubernetes manifests diverge, abort benchmark execution immediately.
2. Coordinate with Platform Chief to verify `colt-gpu-01` inference pod readiness (`nemotron-49b` in `nim-system`).
3. Deploy and monitor the in-cluster `llama-benchy` Job:

   ```bash
   kubectl apply -f rigs/suitcase-ai/provision/k8s/apps/inference/benchmarks/llama-benchy-job.yaml
   ```

4. Harvest and package all required benchmark outputs, treating `recipe.yaml` as the sole authoritative specification of record:
   - Extract `/tmp/results.csv`, `/tmp/submission_answers.json`, and `/tmp/submission_answers.md` from the benchmark pod.
   - Pair with authoritative declarative recipe ([`rigs/suitcase-ai/provision/k8s/apps/inference/recipes/nemotron-49b-fp8.yaml`](../../suitcase-ai/provision/k8s/apps/inference/recipes/nemotron-49b-fp8.yaml)).
   - Scrape bracketed Prometheus/DCGM timeseries for the run window into `telemetry.json` via Grafana Datasource Proxy (`/api/datasources/proxy/1`).
   - Compile the **Spark Arena Local Review Dossier** (`dossier.md` / `local_review_dossier.md`) incorporating telemetry tables and arena comparisons.
5. Submit Completed Staff Work directly to Command via `gc mail send cos`.

### B. Platform Chief (`colt-sysadmin`) — Platform SRE

1. Pre-flight hardware audit on `colt-gpu-01`:
   - Confirm GPU temperature $< 50^\circ\text{C}$ idle.
   - Confirm vLLM/NIM inference engine health on `:8002/v1/health/ready`.
   - Verify UMA memory clamping constraint ($\le 0.75$ / 96 GB max) to safeguard 32 GB system buffer.
2. Monitor host thermal, power, and memory behavior during benchmark execution.

### C. S-6 Signal (`s6-signal`) — Quality & Stan/Eval

1. Audit benchmark logs for latency jitter and anomalous connection drops.
2. Validate zero secret leakage in exported CSV, telemetry timeseries, and recipe metadata.

---

## 4. Mandatory Run Procedure & Standardized Output Manifest

Prior to any benchmark execution, the **spark-to-k8s Sync Preflight Gate** must verify that declarative `recipe.yaml` and running cluster infrastructure are in 100% agreement. Once verified, `recipe.yaml` is established as the sole authoritative specification of record across all downstream registries, dossiers, and submissions.

All current and future Spark Arena benchmark executions must automatically scrape, structure, and preserve the following six mandatory artifacts within the target benchmark directory (e.g. `rigs/colt-results/benchmarks/models/<vendor>/<model>/<config>/spark-arena/<run-id>/`):

1. **`results.csv`**: Official Spark Arena CSV output (`model`, `latency_sec`, `prompt_tokens`, `completion_tokens`, `tps`).
2. **`recipe.yaml`**: Sole authoritative declarative `SparkRecipe` manifest matching physical hardware, runtime flags, and memory clamping.
3. **`telemetry.json`**: Pure bracketed Prometheus/DCGM timeseries capture (GPU utilization, power usage watts, core temperature, KV cache factor) across the run window.
4. **`submission_answers.json`**: Machine-readable standardized submission form answers pre-populating all Spark Arena admin/portal fields.
5. **`submission_answers.md`**: Human-readable standardized form submission reference sheet.
6. **`dossier.md`** (or `local_review_dossier.md`): Executive staff evaluation and comparative analysis referencing the complete artifact package.

- **Reporting**: S-3 submits Completed Staff Work upon job completion.

Regards,
Chief of Staff, Camp Colt
