# Camp Colt 32K Context Baseline Telemetry & Snapshot Report

**Billet**: S-6 Signal & Telemetry Watchstander
**Date**: 2026-09-30 04:03Z (2026-09-29 21:03 PDT)
**Trigger Reference**: `cc-wisp-6glza` / Standing Trigger `cc-wisp-u9bay`
**Dedicated Branch**: `archive/nemotron-32k-baseline`

---

## 1. Executive Summary & Trigger Event

At 20:56:25 PDT on 2026-09-29, opencode worker session `ses_f0f9bbc2dffe0B9qI5K49YZTkN` encountered a context overflow:

- **Input Tokens**: 30,209 tokens
- **Output Tokens Requested**: 2,560 tokens
- **Total Sequence Length**: 32,769 tokens (exceeding `max_model_len: 32768` by 1 token)
- **Error Emitted**: `AI_APICallError: maximum context length 32768 exceeded`

Pursuant to Commander's Planning Guidance and standing directive `cc-wisp-u9bay`, S-6 Signal has executed a full baseline snapshot and finalized all cumulative telemetry across the 32K operating window prior to the 64K switchover.

---

## 2. 32K Runtime Configuration Baseline

| Parameter                            | 32K Baseline Value                         | Notes / Invariants                                       |
| :----------------------------------- | :----------------------------------------- | :------------------------------------------------------- |
| **Model ID**                         | `nvidia/llama-3.3-nemotron-super-49b-v1.5` | Flagship FP8 quantized engine                            |
| **Context Window (`max_model_len`)** | `32,768` tokens                            | Maximum context allocated                                |
| **Hardware Appliance**               | ASUS Ascent GX10 (`colt-gpu-01` / `haze`)  | NVIDIA Grace Blackwell GB10 (128GB unified LPDDR5X)      |
| **GPU Memory Utilization**           | `0.50` (50% UMA)                           | Clamped to preserve host memory stability                |
| **KV Cache Data Type**               | `fp8`                                      | Radix attention cache                                    |
| **KV Cache Capacity**                | `58,736` tokens                            | 3,671 GPU blocks @ 16 tokens/block                       |
| **Prefix Caching**                   | Enabled (`--enable-prefix-caching`)        | Hash: SHA256 block-level matching                        |
| **Streaming Parser**                 | String-aware state machine                 | `hosts/haze/llama_nemotron_toolcall_parser_streaming.py` |

---

## 3. Cumulative Empirical Telemetry Receipts

Raw prometheus metrics scraped from `colt-gpu-01:8000/metrics` at snapshot freeze:

```prometheus
# KV Cache Capacity & Utilization
vllm:cache_config_info{block_size="16",cache_dtype="fp8",enable_prefix_caching="True",gpu_memory_utilization="0.5",kv_cache_size_tokens="58736",num_gpu_blocks="3671"} 1.0
vllm:kv_cache_usage_perc{model_name="nvidia/llama-3.3-nemotron-super-49b-v1.5"} 0.3008

# Radix Prefix Cache Performance
vllm:prefix_cache_queries_total{model_name="nvidia/llama-3.3-nemotron-super-49b-v1.5"} 373014.0
vllm:prefix_cache_hits_total{model_name="nvidia/llama-3.3-nemotron-super-49b-v1.5"} 218800.0
# Radix KV Cache Hit Rate: 58.65% (cumulative across diverse worker workloads)

# Token Volume
vllm:request_prompt_tokens_count{model_name="nvidia/llama-3.3-nemotron-super-49b-v1.5"} 56.0
vllm:request_prompt_tokens_sum{model_name="nvidia/llama-3.3-nemotron-super-49b-v1.5"} 350519.0
vllm:request_generation_tokens_count{model_name="nvidia/llama-3.3-nemotron-super-49b-v1.5"} 56.0
vllm:request_generation_tokens_sum{model_name="nvidia/llama-3.3-nemotron-super-49b-v1.5"} 14968.0

# Latency & Time To First Token (TTFT)
vllm:time_to_first_token_seconds_count{model_name="nvidia/llama-3.3-nemotron-super-49b-v1.5"} 58.0
vllm:time_to_first_token_seconds_sum{model_name="nvidia/llama-3.3-nemotron-super-49b-v1.5"} 156.4545
# Mean TTFT: 2.697 seconds (including reasoning/thinking prefill)
```

### TTFT Bucket Distribution (58 Total Invocations)

- **$\le$ 250ms**: 9 requests (15.5%) — Instant cached completions
- **$\le$ 500ms**: 18 requests (31.0%)
- **$\le$ 750ms**: 35 requests (60.3%)
- **$\le$ 1.00s**: 37 requests (63.8%)
- **$\le$ 2.50s**: 41 requests (70.7%)
- **$\le$ 5.00s**: 53 requests (91.4%)
- **$\le$ 20.0s**: 58 requests (100.0%) — Heavy 30k prefill turns

### Hardware Telemetry (`nvidia-smi`)

- **Power Draw**: 37.09 W
- **GPU Core Temperature**: 67°C
- **Thermals / Fans**: Nominal operating range

---

## 4. Snapshot Verification & Archival State

- **Branch Created**: `archive/nemotron-32k-baseline`
- **Repositories Frozen**:
  - `camp-colt.git`: Contains Gas City configuration, municipal policies, `hosts/haze/` parser and regression suite.
  - `suitcase-ai.git`: Contains K8s manifests for `nemotron-49b-haze`, ConfigMaps, and verification probes.
- **Remote Sync**: Pushed to sovereign Gitea remote on `10.82.0.10:30222`.

Platform Chief (`colt-sysadmin`) is cleared to deploy the 64K context manifest to `colt-gpu-01`.
