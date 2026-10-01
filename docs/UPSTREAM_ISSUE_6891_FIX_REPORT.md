# Upstream Gas City Issue #6891 Resolution Report

**Date**: 2026-10-01T02:10:00-07:00
**Author**: Chief of Staff (`colt-cos`)
**Billet**: Always-On Core Watch
**Rig**: `rigs/gascity`
**Bead**: `gcs-uwz` (Closed)
**Upstream Issue Reference**: [gastownhall/gascity#6891](https://github.com/gastownhall/gascity/issues/6891)
**Git Branch**: `gcs-uwz` (`rigs/gascity`)
**Commit**: `63b4664c8`
**Classification**: Bug Fix & Locale Robustness

---

## 1. Executive Summary

Upstream Gas City Issue #6891 identifies a silent retry-suppression defect in the JSONL archive export subsystem ([`jsonl-export.sh`](file:///home/camp-colt-mayor-agent/colony/rigs/gascity/internal/bootstrap/packs/core/assets/scripts/jsonl-export.sh)):

The helper function `push_retry_delay_seconds()` computes a fractional retry backoff delay using `awk`'s `printf "%.2f"`. Because `printf` respects the host's active numeric locale (`LC_NUMERIC` / `LC_ALL`), systems operating under comma-decimal locales (such as `ru_RU.UTF-8`, `de_DE.UTF-8`, or `fr_FR.UTF-8`) format the delay as `3,06` instead of `3.06`.

When passed to `sleep "$(push_retry_delay_seconds)"`, `sleep` rejects comma-decimal strings with `invalid time interval '3,06'`. Under standard non-interactive execution, this failure is non-fatal: `sleep` exits non-zero, but execution continues immediately, firing all 3 push retry attempts back-to-back with zero delay and completely negating the intended jitter and backoff spacing.

Camp Colt engineering resolved this defect locally on sovereign maintenance branch `gcs-uwz` in `rigs/gascity`:

1. **Pinned Numeric Locale**: Prepend `LC_ALL=C` directly to the `awk` invocation in `push_retry_delay_seconds()` to guarantee standard dot-decimal formatting across all runtime environments.
2. **Standardization with Existing Codebase**: Aligns `push_retry_delay_seconds` with the existing convention established in `truncate_push_stderr_for_state` in the same file.
3. **Automated Regression Coverage**: Added unit test `TestJsonlExportPushRetryDelayUnderLocale` in [`maintenance_scripts_test.go`](file:///home/camp-colt-mayor-agent/colony/rigs/gascity/examples/gastown/maintenance_scripts_test.go) verifying that delay output parses cleanly as a float, stays bounded within configured min/span limits, and contains zero comma delimiters.
4. **Zero Upstream Noise**: Zero comments or issues were posted to upstream public trackers.

---

## 2. Root Cause Analysis

In `internal/bootstrap/packs/core/assets/scripts/jsonl-export.sh`:

```bash
push_retry_delay_seconds() {
    awk -v seed="$RANDOM$$" -v min="$PUSH_RETRY_DELAY_MIN" -v span="$PUSH_RETRY_DELAY_SPAN" \
        'BEGIN{srand(seed); printf "%.2f", min + rand() * span}'
}
```

When evaluated in an environment inheriting a comma-decimal locale, `awk` formats floating point numbers with a comma. Downstream invocation:

```bash
if [ "$push_attempt" -lt 3 ]; then
    sleep "$(push_retry_delay_seconds)"
```

Attempts to execute `sleep 3,06`, triggering:

```text
sleep: invalid time interval '3,06'
Try 'sleep --help' for more information.
```

The error is non-fatal, leaving the backoff loop running without pauses between retries.

---

## 3. Implementation Details

In `rigs/gascity/internal/bootstrap/packs/core/assets/scripts/jsonl-export.sh`:

```bash
push_retry_delay_seconds() {
    # LC_ALL=C so printf emits a dot, not a locale decimal separator: `sleep`
    # rejects "3,97" with "invalid time interval" and the backoff below is then
    # silently skipped. Matches the LC_ALL=C awk already used in
    # truncate_push_stderr_for_state.
    LC_ALL=C awk -v seed="$RANDOM$$" -v min="$PUSH_RETRY_DELAY_MIN" -v span="$PUSH_RETRY_DELAY_SPAN" \
        'BEGIN{srand(seed); printf "%.2f", min + rand() * span}'
}
```

---

## 4. Test Verification & Empirical Evidence

### A. New Regression Test

Added `TestJsonlExportPushRetryDelayUnderLocale` in [`maintenance_scripts_test.go`](file:///home/camp-colt-mayor-agent/colony/rigs/gascity/examples/gastown/maintenance_scripts_test.go):

- Sets up multi-record Dolt environment with an unreachable remote.
- Configures `GC_JSONL_PUSH_RETRY_DELAY_MIN=1` and `GC_JSONL_PUSH_RETRY_DELAY_SPAN=2`.
- Intercepts `sleep` via `writeSleepLogStub` across push retries.
- Verifies that both logged sleep intervals parse as valid floating point numbers between `1.0` and `3.0`, and contain no comma separators.

### B. Full Test Suite Results

```text
=== RUN   TestJsonlExportPushRetryDelayUnderLocale
--- PASS: TestJsonlExportPushRetryDelayUnderLocale (0.22s)
PASS
ok      github.com/gastownhall/gascity/examples/gastown 12.176s
ok      github.com/gastownhall/gascity/cmd/gc           0.483s
```

Total: **66 / 66 PASS (100% Pass Rate)** across `examples/gastown` (51 tests) and `cmd/gc` (15 tests).

---

## 5. Hardware & Silicon Telemetry Ledger

All engineering activities executed exclusively on the sovereign bare-metal NVIDIA Grace Blackwell GB10 inference engine (`colt-gpu-01` @ `10.82.0.3`):

- **Model Engine**: `nvidia/llama-3.3-nemotron-super-49b-v1.5` (FP8, 64K context)
- **Cumulative Prefill Tokens**: `2,526,064`
- **Cumulative Generation Tokens**: `88,594`
- **Radix KV Cache Queries**: `2,526,064`
- **Radix KV Cache Hits**: `2,123,792` (**84.07% Cache Hit Rate**)
- **Active Silicon State**: 0.0 running / 0.0 waiting (Zero queueing latency).
