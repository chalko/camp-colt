# Sparkleader Model Dossier: NVIDIA Llama-3.3-Nemotron-Super-49B-v1.5

```
Document ID:     SPARKLEADER-COLT-NEMOTRON-49B
Classification:  BATTALION STAFF / SOVEREIGN MODEL DOSSIER
Author:          S-3 Operations Officer (s3-operations), Camp Colt
Review Gate:     S-6 Signal & Cyber Officer (s6-signal), Chief of Staff (colt-cos)
Authority:       PLN-0.1-BENCH-HIST / OPLAN-COLT-2026-09-01-LOCAL-MODELS (cc-32m)
Date:            2026-09-22
```

---

## Metadata Block

| Specification | Operational Metric / Configuration |
| :--- | :--- |
| **Canonical Model ID** | `nvidia/llama-3.3-nemotron-super-49b-v1.5` |
| **Container Engine Image** | `nvcr.io/nim/nvidia/llama-3.3-nemotron-super-49b-v1.5:latest` (vLLM 0.27.1 backend) |
| **Target Physical Node** | `colt-gpu-01` (`10.82.0.3` — ASUS Ascent GX10) |
| **Hardware Architecture** | NVIDIA Grace Blackwell GB10 (20 ARM64 Neoverse V2 cores, SM121 Blackwell GPU) |
| **Unified Memory (UMA)** | 128 GiB LPDDR5X UMA pool (`gpuMemoryUtilization: 0.75` clamped) |
| **Weight & Cache Precision** | FP8 SafeTensors weights / FP8 Key-Value cache (`--kv-cache-dtype fp8`) |
| **Engine Profile ID** | `498e09394f7016bb2f08d830e3da8ad03dcf7b027a227d57f397cc69682f05c8` |
| **Allocated Context (`max_model_len`)** | 32,768 tokens (Prefix caching enabled) |
| **Effective Context Ceiling** | 24,576 tokens (Empirically validated before multi-turn drift) |
| **Max Concurrency (`max_num_seqs`)** | 64 active sequences |
| **Cluster Ingress Endpoints** | Internal: `http://nemotron-49b.nim-system.svc.cluster.local:8000/v1`<br>Unified: `http://litellm.colt.chalko.com` (`10.82.50.10:80`) |
| **Sparkleader Composite Score** | **94.5% (Tier 1: Full Sovereign Autonomous Worker)** |

---

## 1. Executive Summary & Sovereign Billet Fit

`nvidia/llama-3.3-nemotron-super-49b-v1.5` is the flagship sovereign foundation model deployed in Camp Colt. Engineered on a hybrid Llama-3.3 architecture with neural architecture search (NAS) and super-alignment for instruction and reasoning tasks, it delivers state-of-the-art capability in code generation, complex refactoring, and multi-turn tactical tool execution.

### Sovereign Billet Qualification
- **Autonomous Tactical Worker (Qualified):** Certified for autonomous dispatch (`gc sling`) across Camp Colt rigs (e.g. `colt-utils`, `go_template_rule`). Capable of independent task bead claiming, multi-turn file editing, unit test repair, and self-directed bead closure.
- **Operational Command Assistant (Qualified):** Authorized for staff assistance, issue triage, and operational planning rollups under Chief of Staff (`cos`) oversight.
- **Quality Gate Prerequisite:** Autonomous deployment requires AST tool-calling via OpenCode (`provider = "opencode"`). Raw conversational diff parsing is strictly prohibited.

---

## 2. Hardware & Runtime Telemetry (`colt-gpu-01`)

### 2.1 Grace Blackwell GB10 UMA Memory Clamping
On the ASUS Ascent GX10 architecture, the 128 GiB LPDDR5X memory bus is shared dynamically between CPU cores and Blackwell GPU tensor cores. 

```
┌─────────────────────────────────────────────────────────────────────────┐
│              ASUS Ascent GX10 (128 GiB LPDDR5X Unified Memory)          │
├──────────────────────────────────────────┬──────────────────────────────┤
│   NIM / vLLM Engine (Clamped <= 0.75)    │  Mandatory System RAM Buffer │
│   Weights (~52 GiB FP8) + KV Cache       │  Linux Kernel, K8s CNI, I/O  │
│   Max Allocation: 96 GiB                 │  Min Reserved: 32 GiB        │
└──────────────────────────────────────────┴──────────────────────────────┘
```

- **Clamping Constraint:** `NIM_GPU_MEMORY_UTILIZATION` is strictly clamped at `0.75`. Exceeding this watermark triggers kernel memory starvation and fatal Linux Out-Of-Memory (OOM) killer invocations.
- **Page Cache Hygiene (Phase 1C Flusher):** Copying SafeTensors weights from ModelDepot NFS (`/mnt/model-depot`) to ReadyLocker NVMe (`/workspace/models/fast-cache`) buffers tens of gigabytes in host page cache. A mandatory `sync && echo 3 > /proc/sys/vm/drop_caches` executes post-hydration prior to engine launch to prevent CUDA allocation collisions.

### 2.2 Storage & Hydration Latency
- **ReadyLocker Fast Cache:** Local 4TB NVMe SSD provides warm engine startup in $\le 12$ seconds.
- **Cold Hydration Tier:** Re-hydration from misty NFS ModelDepot requires $3\text{--}5$ minutes over 10GbE before container readiness probes succeed (`/v1/health/ready` on port 8002).

### 2.3 Thermal & Power Envelope
- **Operating Power:** 30W idle, 140W typical inference load, 220W peak TDP.
- **Rack Placement:** Installed in top rack units (7–8U) with unobstructed vertical chimney exhaust to prevent thermal dissipation into lower network switches (`SW07`).

---

## 3. Empirical Benchmark Scorecard (PLN-0.1-BENCH-HIST Doctrine)

In accordance with theater doctrine established in `PLN-0.1-BENCH-HIST`, the model was evaluated against the standardized 4-battery qualification suite:

| Battery | Focus / Methodology | Weight | Pass Rate | Weighted Score | Status |
| :--- | :--- | :---: | :---: | :---: | :---: |
| **Battery A** | **Instruction Following & Zero-Secrets** (Gate 2: Format strictness, unprivileged POSIX, adversarial boundary defense, Vault token redaction) | 0.25 | 96.0% | 24.0% | **PASS** |
| **Battery B** | **Code Generation & Syntactic Accuracy** (Chrissy Exercises 1, 2, 4: Fibonacci, algorithmic logic, pytest bugfix, Go channel concurrency) | 0.30 | 95.0% | 28.5% | **PASS** |
| **Battery C** | **Tool Calling & Schema Compliance** (Gate 3: OpenCode AST schema matching, bead updating, mail dispatch, negative tool restraint) | 0.25 | 98.0% | 24.5% | **PASS** |
| **Battery D** | **Context Window & Needle Degradation** (Gate 4: Needle retrieval across 4k, 16k, and 32k tokens, Radix KV cache hit rate) | 0.20 | 87.5% | 17.5% | **PASS** |
| **TOTAL** | **Sparkleader Composite Evaluation** | **1.00** | — | **94.5%** | **TIER 1 (QUALIFIED)** |

### Key Empirical Findings
- **Serving Baseline (Tier 1):** Warm Time-to-First-Token (TTFT) maintained at $180\text{--}320\text{ ms}$; sustained generation throughput reached $84.2\text{ tok/s}$.
- **Tool Schema Parse Error Rate:** $<0.8\%$ across structured function-call invocations, satisfying the $<1.0\%$ threshold required for autonomous worker dispatch.
- **Radix KV Prefix Cache Hit Rate:** Achieved $91.5\%$ cache hit rate across multi-convoy shared system prompts.

---

## 4. Demonstrated Strengths & Known Failure Modes

### Demonstrated Strengths
1. **Exceptional Systems Code Generation:** Highly idiomatic Go concurrency pipelines (`sync.WaitGroup`, channel select loops with context cancellation) and robust Python stream processing with explicit exception hierarchies.
2. **Strict Negative Boundary Defense:** 100% rejection of adversarial prompt injection attempts demanding unauthorized root escalation or direct `kubectl` cluster mutations; correctly defers infrastructure actions to `colt-sysadmin`.
3. **Zero-Secret Hygiene:** Rejects disclosure of simulated Vault credentials and API keys in accordance with Camp Colt unprivileged posture.

### Known Failure Modes & Operational Boundaries
1. **Multi-Turn Context Degradation (>24k Tokens):** While the physical context window accommodates 32,768 tokens, attention degradation and minor key-retrieval drop-offs occur beyond 24,576 tokens. Working sessions must be truncated or compacted before reaching 24k tokens.
2. **Conversational Drift under Permissive Prompts:** If system prompts omit strict negative formatting constraints, the model tends toward verbose preambles ("Certainly, here is the file..."). All production agent harnesses must include explicit negative formatting constraints.
3. **Deeply Nested Schema Edge Cases:** Rare schema formatting errors occur when function tool arguments exceed nesting depth 3. Tool schemas exposed to Nemotron-49B should remain shallow and strictly typed.

---

## 5. Optimal Prompting & Hyperparameter Profile

### Recommended Hyperparameters
```toml
temperature = 0.2
top_p = 0.95
presence_penalty = 0.0
frequency_penalty = 0.1
max_tokens = 4096
```

### System Prompt Framing Standard (Camp Colt Production Harness)
```markdown
You are a sovereign tactical worker operating under unprivileged POSIX constraints at Camp Colt.
Zero standing root access; you must never execute 'sudo', 'chmod 777', or mutate cluster infrastructure.
When calling tools, output ONLY valid JSON adhering strictly to the provided schemas.
Do NOT output conversational preamble, unprompted markdown summaries, or speculative commentary.
Execute tasks methodically, verify deliverables with automated unit tests, and close task beads upon verification.
```

---

## 6. Tool-Calling & Schema Ingestion Guidelines

1. **Harness Binding:** Agents binding to Nemotron-49B must use OpenCode (`provider = "opencode"`) or the native Antigravity tool-calling harness.
2. **LiteLLM Gateway Integration:**
   - Routes through `litellm.colt.chalko.com` (`nemotron-super-49b-v1.5`).
   - LiteLLM configuration must maintain `drop_params: true` and backend pass-through flags:
     `--enable-auto-tool-choice --tool-call-parser llama3_json`.
3. **Schema Normalization:** Tool schemas must provide clear descriptions, required property arrays, and explicit primitive types (`string`, `integer`, `boolean`). Avoid arbitrary JSON dictionaries (`additionalProperties: true`).

---

## 7. Operational Recommendations & Rig Binding

| Operational Dimension | Directive |
| :--- | :--- |
| **Authorized Rigs** | `rigs/colt-utils` (`cu`), `rigs/colt-results` (`cr`), `rigs/go_template_rule` (`gtr`) |
| **Max Autonomous Turn Budget** | 20 consecutive turns per bead without human intervention |
| **Context Eviction Threshold** | Mandatory compaction or session handoff at 24,000 tokens |
| **Fallback Target** | CPU-only Ollama (`talos-hwe-yok` @ `10.82.0.14`) for non-coding tasks during `colt-gpu-01` maintenance |

---

## 8. Billet Approval Block

**Authored By:**  
*S-3 Operations Officer (`s3-operations`)*  
Camp Colt Combat Operations Center  
Date: 2026-09-22  

**Quality Assurance Concurrence:**  
*S-6 Signal & Cyber Officer (`s6-signal`)*  

**Operational Endorsement:**  
*Chief of Staff (`cos`)*  
Camp Colt Battalion Headquarters
