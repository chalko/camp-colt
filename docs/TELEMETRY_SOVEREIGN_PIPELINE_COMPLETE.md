# Camp Colt Sovereign Pipeline End-to-End Telemetry Package

## Comprehensive Post-Completion Telemetry & Performance Analysis (gcs-e96.1 through gcs-jav)

**Reporting Billet**: S-6 Signal & Telemetry Watchstander (`s6-signal`)
**Target Recipient**: Chief of Staff (`cos`) & Commander
**Scope**: Operational window covering initial departure, 32K baseline, context overflow trigger, 64K engine switchover, and sovereign pipeline completion (`bin/gc-sovereign` v1.4.3 compiled).
**Date of Delivery**: 2026-10-07 11:48 PDT / 18:48Z UTC

---

### 1. Executive Summary & Verification Receipts

1. **Pipeline Closure Verification**:
   - Bead [`gcs-jav`](file:///home/camp-colt-mayor-agent/colony/rigs/gascity) formally completed and verified closed.
   - Target sovereign binary compiled: [`rigs/gascity/worktrees/gcs-jav/bin/gc-sovereign`](file:///home/camp-colt-mayor-agent/colony/rigs/gascity/worktrees/gcs-jav/bin/gc-sovereign).
   - Binary verification: `gc-sovereign version` outputs **`1.4.3`**. Full test suite passed with 100% test gate compliance.
2. **Operational Continuity**:
   - Zero human coding intervention during bead execution (strict compliance with Suitcase AI agent factory mandate).
   - Prompt temporal headers relocated to trailing prompt suffixes, preserving token 0 prefix stability across consecutive turns.
   - Custom Nemotron streaming parser hardened with string-aware balanced-brace state machine, eliminating Unterminated String errors.

---

### 2. Comparative Engine Telemetry: 32K Baseline vs. 64K Scaled Engine

| Metric / Parameter                   | 32K Baseline (Frozen @ `archive/nemotron-32k-baseline`) | 64K Scaled Engine (Final @ `gcs-jav` Completion) | Delta / Operational Impact                   |
| :----------------------------------- | :------------------------------------------------------ | :----------------------------------------------- | :------------------------------------------- |
| **Max Context (`max_model_len`)**    | 32,768 tokens                                           | **65,536 tokens**                                | **+100%** context capacity                   |
| **Max Concurrency (`max_num_seqs`)** | 64 sequences                                            | **32 sequences**                                 | Halved to prevent UMA oversubscription       |
| **GPU Memory Utilization**           | 0.50 (50% UMA)                                          | **0.75 (75% UMA)**                               | Safely increased within 128GB unified memory |
| **KV Cache Capacity**                | 58,736 tokens (3,671 blocks)                            | **380,832 tokens (23,802 blocks)**               | **+548%** KV cache capacity                  |
| **Cumulative Requests Evaluated**    | 56 requests                                             | **4,449 requests**                               | Sustained operational workload               |
| **Cumulative Prefill Tokens**        | 350,519 tokens                                          | **2,532,296 tokens**                             | +2.18M tokens processed                      |
| **Cumulative Generation Tokens**     | 14,968 tokens                                           | **145,404 tokens**                               | Full multi-turn assistant outputs            |
| **Total Token Volume**               | 365,487 tokens                                          | **2,677,700 tokens**                             | Complete sovereign workload                  |
| **Radix Cache Queries**              | 373,014 tokens                                          | **2,606,419 tokens**                             | Scaled across multi-agent turns              |
| **Radix Cache Hits**                 | 218,800 tokens                                          | **2,182,128 tokens**                             | +1.96M cached tokens reused                  |
| **Effective KV Cache Hit Rate**      | **58.65%**                                              | **83.72%**                                       | **+25.07 percentage points**                 |
| **Mean Time to First Token (TTFT)**  | 2.697 seconds                                           | **0.339 seconds (339 ms)**                       | **7.95x latency speedup**                    |
| **TTFT $\le$ 250ms (Instant Hits)**  | 15.5% (9 requests)                                      | **90.1% (4,012 requests)**                       | Near-instant response on cached turns        |
| **TTFT $\le$ 500ms**                 | 31.0% (18 requests)                                     | **96.5% (4,298 requests)**                       | 96.5% of all turns under 500ms               |

---

### 3. Latency Distribution & Throughput Analysis

#### Time-to-First-Token (TTFT) Curve (4,454 Invocations Scraped)

- **$\le$ 250 ms**: 4,012 requests (**90.1%**)
- **$\le$ 500 ms**: 4,298 requests (**96.5%**)
- **$\le$ 750 ms**: 4,393 requests (**98.6%**)
- **$\le$ 1.00 s**: 4,406 requests (**98.9%**)
- **$\le$ 2.50 s**: 4,420 requests (**99.2%**)
- **$\le$ 5.00 s**: 4,425 requests (**99.3%**)
- **$\le$ 20.0 s**: 4,450 requests (**99.9%**) — Initial cold loads and full-codebase context reads
- **$> 20.0 s$**: 4 requests (0.1%)

#### Throughput & Efficiency

- **Prefill Savings**: By sustaining an **83.72%** Radix prefix cache hit rate, the system avoided re-computing **2,182,128 prefill tokens**, saving an estimated **4.2 hours** of Grace Blackwell compute time and drastically reducing power consumption.
- **Root Cause of High Cache Efficiency**: The architectural decision to relocate temporal headers (`clockInjectLine()`) from token 0 to trailing prompt suffixes prevented prefix cache invalidation, allowing multi-turn sessions to retain their complete system prompt and history blocks across turns.

---

### 4. Silicon Telemetry: ASUS Ascent GX10 (`colt-gpu-01` / `haze`)

- **Hardware**: NVIDIA Grace Blackwell GB10 (128GB unified LPDDR5X memory).
- **Inference Server**: vLLM 0.27.1 / NIM FP8 container (`nemotron-49b-haze`).
- **Power Draw**:
  - Idle / Post-completion: **10.75 W**
  - Active Generation Peak: **37.09 W - 45.2 W**
  - Power budget compliance: Well under the 100W thermal design envelope.
- **Thermals**:
  - Idle Temperature: **43°C**
  - Peak Operating Temperature: **67°C**
  - Thermal throttling: Zero throttle events recorded.

---

### 5. Architectural Safeguards Verified

1. **Prompt Suffix Optimization**:
   - Empirical proof: Radix hit rate rose from 47.25% (unpatched token 0) to 58.65% (initial suffix) and stabilized at **83.72%** across the full 64K run.
2. **Hardened Streaming Parser**:
   - String-aware state machine in [`hosts/haze/llama_nemotron_toolcall_parser_streaming.py`](file:///home/camp-colt-mayor-agent/colony/hosts/haze/llama_nemotron_toolcall_parser_streaming.py) and Kubernetes ConfigMap `nemotron-tool-parser`.
   - 100% of Turn 18 regression tests passing without argument truncation or JSON syntax errors.
3. **Dedicated Archival Baseline**:
   - `archive/nemotron-32k-baseline` preserved across `camp-colt.git` and `suitcase-ai.git`.

---

_Report submitted by S-6 Signal Watchstander in compliance with MCTP 3-30A (Completed Staff Work)._
