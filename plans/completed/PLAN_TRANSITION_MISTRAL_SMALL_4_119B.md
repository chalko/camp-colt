# Operational Architecture Plan: Transition to Mistral-Small-4-119B on Grace Blackwell GB10

**Status:** Completed (Verified: 2026-10-10)
**Date:** 2026-10-08

---

## 1. Executive Summary & Commander's Intent

### 1.1 Operational Problem Statement

Tactical workers operating on `rigs/gascity` under S-6 oversight have experienced repeated friction, tool-calling parsing failures, and execution stalls under the incumbent model profile (`nvidia/llama-3.3-nemotron-super-49b-v1.5`).

Specific failure modes identified:

1. **Tool-Call JSON Parser Brittleness:** Complex multi-line Go code patches containing nested curly braces and escape sequences repeatedly broke standard streaming regex extractors, triggering execution timeouts.
2. **Context Compression & Latency Tradeoffs:** Balancing reasoning effort against context length and throughput constrained worker velocity on complex multi-file tasks.

### 1.2 Strategic Intent & Solution

Per Commander's guidance and the authoritative **Model Clearance Registry** ([`model_clearance_registry.md`](https://london.fog.chalko.com/Chalko/strategic-plans/src/branch/main/docs/model_clearance_registry.md) approved 2026-10-08 03:59 Z), Camp Colt will execute a disciplined, Kubernetes-native transition to **`mistralai/Mistral-Small-4-119B-2603`**.

- **Architecture:** Sparse Mixture-of-Experts (119B total / 6.5B active parameters per token, 128 experts / 4 active).
- **Quantization:** **NVFP4 (~66 GiB)** via Spark Arena recipe (`avarok/atlas-gb10` container), native to the GB10 Tensor Cores.
- **Native Tool Calling:** Tekken tokenizer with native function calling and JSON tool output via vLLM (`--tool-call-parser mistral --reasoning-parser mistral`).
- **Performance Horizon:** Community-verified on ASUS Ascent GX10 silicon at **27.8 tok/s solo (TTFT 115 ms)** and **131 tok/s aggregate @ 20 concurrent streams**.

---

## 2. Six-Phase Operational Transition Plan

```mermaid
sequenceDiagram
    autonumber
    participant CDR as Commander
    participant COS as Chief of Staff (colt-cos)
    participant S3 as S-3 Operations
    participant SRE as Platform SRE (colt-sysadmin)
    participant S6 as S-6 Signal
    participant MAYOR as Mayor

    Note over COS,S3: Phase 1: Tactical Hold & Convoy Pause (COMPLETE)
    COS->>S3: Hold dispatch on gascity bead gcs-y9q
    COS->>MAYOR: Hold convoy control-dispatchers during staging

    Note over COS,SRE: Phase 2: K8s Declarative Deployment (spark-to-k8s)
    COS->>SRE: Compile mistral-small-4-nvfp4 recipe via spark-to-k8s
    SRE->>S6: Iterate with S-6 on K8s manifest & apply to nim-system

    Note over COS,S6: Phase 3: Signal Verification & Regression Gate (APPROVED)
    COS->>S6: Validate Gateway & run Tekken regression
    S6->>S6: Execute Tekken stream regression & live tool parsing

    Note over S3,S6: Phase 4: Silicon Benchmark Battery
    S3->>S3: Run TTFT, solo TPS, and concurrency sweep

    Note over COS,MAYOR: Phase 5: Municipal Provider Cutover
    COS->>MAYOR: Update city.toml (local-mistral) & reload supervisor
    MAYOR->>MAYOR: Update city.toml -> gc reload

    Note over COS,S3: Phase 6: Operational Resumption (Commander Review Gate)
    COS->>S3: Dispatch tactical worker on gcs-y9q
    S3->>CDR: Present Completed Work; await Commander PR approval
```

---

### Phase 1: Tactical Hold & Convoy Pause (COMPLETE)

1. **Operational State Reconciliation (S-3):**
   - Tactical worker bead `gcs-6fu` was successfully completed and closed.
   - S-3 Operations enacted a temporary dispatch hold on next bead `gcs-y9q` (P1 · OPEN: _Prepare clean upstream contribution branch `upstream-fix/relocate-prompt-headers-suffix`_). Confirmed via `cc-wisp-ocje3`.
2. **Convoy Dispatcher Hold (Mayor):**
   - Mayor suspended rigs `gascity` and `colt-utils` and quiesced active convoy control-dispatchers. Confirmed via `cc-wisp-et7r4`.

---

### Phase 2: Kubernetes Declarative Deployment via `spark-to-k8s` (Platform SRE / S-6 Lead)

_(Incorporating Commander Redline L89: Retain Kubernetes; compile declarative recipe via `spark-to-k8s`; iterate with S-6)_

1. **Recipe Authoring (`rigs/suitcase-ai`):**

   - Author declarative `SparkRecipe` at `rigs/suitcase-ai/provision/k8s/apps/inference/recipes/mistral-small-4-nvfp4.yaml`:

     ```yaml
     apiVersion: inference.colt.ai/v1alpha1
     kind: SparkRecipe
     metadata:
       name: mistral-small-4-nvfp4
       labels:
         tier: flagship-coder
         quant: nvfp4
     spec:
       model:
         id: "mistralai/Mistral-Small-4-119B-2603"
         directory: "models--mistralai--Mistral-Small-4-119B-2603-NVFP4"
         source: "huggingface"
       runtime:
         engine: "vllm"
         image: "avarok/atlas-gb10:latest"
         gpuMemoryUtilization: 0.75
         maxNumSeqs: 32
         maxModelLen: 65536
         passthroughArgs: "--served-model-name mistralai/Mistral-Small-4-119B-2603 --attention-backend triton --tool-call-parser mistral --reasoning-parser mistral --enable-auto-tool-choice"
       hardware:
         accelerator: "gb10"
         arch: "arm64"
         gpuCount: 1
       storage:
         depotSource: "/mnt/model-depot/huggingface/hub/models--mistralai--Mistral-Small-4-119B-2603-NVFP4"
         readyTarget: "/opt/nim/.cache/huggingface/hub/models--mistralai--Mistral-Small-4-119B-2603-NVFP4"
     ```

2. **Manifest Compilation via `spark-to-k8s`:**

   - Execute the compiler in `rigs/colt-utils/tools/spark-to-k8s`:

     ```bash
     spark-to-k8s -i rigs/suitcase-ai/provision/k8s/apps/inference/recipes/mistral-small-4-nvfp4.yaml \
                  -t rigs/suitcase-ai/provision/k8s/apps/inference/templates/model.yaml.tmpl \
                  -o rigs/suitcase-ai/provision/k8s/apps/inference/mistral-small-4-nvfp4.yaml \
                  -n nim-system
     ```

   - Injects mandatory environment `VLLM_MLA_DISABLE=1`, hardware tolerations, UMA memory safety limits, and initContainers.

3. **Deployment & Iteration with S-6:**
   - Platform SRE and S-6 apply the manifest to `nim-system` via `kubectl apply -f ...` or Flux GitOps reconcile.
   - Pod replaces `nemotron-49b-haze` gracefully using Kubernetes rolling update / `Recreate` deployment strategy.
   - Verify health probe on `http://10.82.0.3:8000/v1/models`.

---

### Phase 3: Signal Gateway & Parser Regression Gate (S-6 Lead — APPROVED)

_(Approved by Commander L120)_

1. **LiteLLM Route Mapping:**
   - Update LiteLLM proxy configuration on `10.82.50.10:80` to declare model identifier `mistralai/Mistral-Small-4-119B-2603` routing to backend `http://10.82.0.3:8000/v1`.
   - Enable direct stream passthrough so native Tekken function-call deltas are not double-escaped.
2. **Tekken Streaming Regression Test Suite:**
   - S-6 executes regression testing against live endpoint:
     - Verify native Tekken function-call deltas parse cleanly into standard OpenAI tool calls without custom regex extractors.
     - Verify multi-line string payloads, nested curly braces, and code diff escape sequences pass without syntax errors or empty captures.

---

### Phase 4: Silicon Benchmark Battery (S-3 / S-6 Lead)

Before routing active agent traffic, execute a standardized 3-tier benchmark:

| Metric                       | Target Baseline (Nemotron 49B)        | Expected Target (Mistral-Small-4)                       |
| :--------------------------- | :------------------------------------ | :------------------------------------------------------ |
| **Solo TTFT (Cold)**         | ~250 ms                               | $\le 150\text{ ms}$ (Expected: ~115 ms)                 |
| **Solo Throughput (TPS)**    | ~22.4 tok/s                           | $\ge 25.0\text{ tok/s}$ (Expected: ~27.8 tok/s)         |
| **Concurrency (20 streams)** | ~88 tok/s aggregate                   | $\ge 120\text{ tok/s}$ aggregate (Expected: ~131 tok/s) |
| **Tool Calling Accuracy**    | 91.2% (occasional JSON escape errors) | $\ge 99.0\%$ (Native Tekken parser)                     |
| **VRAM Footprint**           | ~52 GiB                               | ~66 GiB (fits comfortably in 128GB UMA)                 |

Results will be compiled by S-3 into a benchmark telemetry record in `rigs/colt-results/reports/`.

---

### Phase 5: Municipal Configuration & Supervisor Reload (Mayor Lead)

_(Incorporating Commander Redline L162: Renamed from local-nemotron to local-mistral)_

1. **Update `city.toml`:**
   Configure model identifiers across local providers:

   ```toml
   [providers.local-litellm.env]
   OPENAI_MODEL = "mistralai/Mistral-Small-4-119B-2603"

   [providers.local-mistral.env]
   OPENAI_MODEL = "mistralai/Mistral-Small-4-119B-2603"

   [providers.local-fast.env]
   OPENAI_MODEL = "mistralai/Mistral-Small-4-119B-2603"
   OPENCODE_REASONING_EFFORT = "none"

   [providers.local-general.env]
   OPENAI_MODEL = "mistralai/Mistral-Small-4-119B-2603"
   OPENCODE_REASONING_EFFORT = "medium"

   [providers.local-coder.env]
   OPENAI_MODEL = "mistralai/Mistral-Small-4-119B-2603"
   OPENCODE_REASONING_EFFORT = "high"
   ```

2. **Update Global OpenCode Config:**
   Align `~/.config/opencode/opencode.jsonc` default model identifier to `local-litellm/mistralai/Mistral-Small-4-119B-2603`.
3. **Supervisor Reload:**
   Mayor executes `gc reload` to refresh active provider configuration without restarting the city controller.

---

### Phase 6: Operational Resumption (S-3 Lead)

_(Incorporating Commander Redline L191: Mandatory Commander Approval Gate before PR submission)_

1. **Dispatch Tactical Worker to `gcs-y9q`:**
   - S-3 dispatches a fresh tactical worker on bead `gcs-y9q` (_Prepare clean upstream contribution branch upstream-fix/relocate-prompt-headers-suffix_).
   - Worker operates under `mistralai/Mistral-Small-4-119B-2603`.
2. **PR Verification & Commander Review Gate (L191 Mandate):**
   - Execute fast unit tests (`make test`).
   - Run quality gate checks (`make check`).
   - **HOLD: Tactical workers shall NOT submit the PR upstream without explicit review and approval by the Commander.**
   - S-3 and CoS compile empirical verification receipts into a completed staff work dispatch for Command sign-off.

---

## 3. Contingency & Fallback Gates

_(Addressing Commander Inquiry L202: Provenance of Fallback Criteria)_

**Origin of Thresholds:**

- **Baseline Telemetry:** Derived from historical Camp Colt receipts on `colt-gpu-01` (`docs/TELEMETRY_32K_BASELINE.md`: Nemotron 49B ran at 22.4 tok/s solo, 250 ms cold TTFT).
- **Clearance Registry Receipts:** Derived from community-validated ASUS Ascent GX10 runs (`model_clearance_registry.md` approved 2026-10-08 03:59 Z: 27.8 tok/s solo, 115 ms TTFT).
- **Fallback Trigger:** If live deployment achieves $<20\text{ tok/s}$ (-10% below the incumbent baseline) or TTFT exceeds $350\text{ ms}$ (+100 ms worse than incumbent), it signals an architectural misconfiguration (e.g. attention backend failure or thermal throttling) triggering immediate fallback.

**Immediate Fallback Protocol:**

1. Re-apply Nemotron manifest via Kubernetes:

   ```bash
   kubectl rollout undo deployment/mistral-small-4-nvfp4 -n nim-system
   ```

2. Mayor reloads `city.toml` restoring previous baseline.
3. Zero disruption to colony state.
