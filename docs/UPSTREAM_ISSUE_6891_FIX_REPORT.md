<!-- markdownlint-disable MD013 -->

# Upstream Gas City Issue Resolution Report: Issue #6891

**Issue Reference**: [`gastownhall/gascity#6891`](https://github.com/gastownhall/gascity/issues/6891)
**Governing Bead**: `gcs-m30`
**Target Repository**: `rigs/gascity`
**Branch**: `gcs-m30` (Commit: `7b3842355`)
**Resolution Timestamp**: 2026-10-01T13:10:11-07:00
**Author**: Mayor (Headquarters Commandant), Camp Colt
**Verification Status**: VERIFIED (Targeted locale tests and full 14 push maintenance test suites passed 100%)

---

## 1. Problem Formulation & Root Cause Analysis

### 1.1 Upstream Defect Description

In Gas City's Dolt-to-JSONL export maintenance script (`internal/bootstrap/packs/core/assets/scripts/jsonl-export.sh`):

1. The retry backoff delay helper `push_retry_delay_seconds()` computed its sleep interval using `awk`'s `printf "%.2f"`:

   ```sh
   push_retry_delay_seconds() {
       awk -v seed="$RANDOM$$" -v min="$PUSH_RETRY_DELAY_MIN" -v span="$PUSH_RETRY_DELAY_SPAN" \
           'BEGIN{srand(seed); printf "%.2f", min + rand() * span}'
   }
   ```

2. In shells or hosts configured with a comma-decimal locale (such as `ru_RU.UTF-8`, `de_DE.UTF-8`, or any locale with comma radix separator), `printf` honours `LC_NUMERIC` and emits intervals with a comma (e.g., `3,06`).
3. When passed to `sleep "$(push_retry_delay_seconds)"`, `sleep` rejects comma-decimal intervals (`sleep: invalid time interval '3,06'`).
4. Because `sleep` failure was non-fatal in the loop, the push retries fired back-to-back with zero delay, silently disabling push retry backoff entirely.

### 1.2 Root Cause Identification

1. `push_retry_delay_seconds` invoked bare `awk` without pinning numeric locale conventions.
2. In contrast, the stderr truncation routine in the same script at line 239 explicitly pinned the locale (`printf '%s' "$raw" | LC_ALL=C awk ...`).
3. Schedulers operating under `LC_ALL=C.UTF-8` did not trigger the bug, leaving it latent until run under interactive shells or environments inheriting regional system locales.

---

## 2. Technical Implementation

### 2.1 Code Changes

1. **`internal/bootstrap/packs/core/assets/scripts/jsonl-export.sh`**:
   Prepended `LC_ALL=C` to the `awk` invocation in `push_retry_delay_seconds`:

   ```sh
   push_retry_delay_seconds() {
       LC_ALL=C awk -v seed="$RANDOM$$" -v min="$PUSH_RETRY_DELAY_MIN" -v span="$PUSH_RETRY_DELAY_SPAN" \
           'BEGIN{srand(seed); printf "%.2f", min + rand() * span}'
   }
   ```

   This guarantees POSIX dot-decimal formatting for generated floating-point numbers across all host and shell environments.

2. **`examples/gastown/maintenance_scripts_test.go`**:
   Added `TestJsonlExportPushRetriesUnderCommaDecimalLocale`:
   - Configures the test environment with `LC_ALL=ru_RU.UTF-8` and `LC_NUMERIC=ru_RU.UTF-8`.
   - Simulates a transient git push failure followed by retry success.
   - Inspects the intercepted `sleep.log` output and verifies that the recorded delay interval is dot-decimal (`0.00`) and accepted by `sleep`.

---

## 3. Empirical Verification Evidence

### 3.1 Targeted Test Execution

```text
=== RUN   TestJsonlExportPushRetriesUnderCommaDecimalLocale
--- PASS: TestJsonlExportPushRetriesUnderCommaDecimalLocale (0.32s)
PASS
ok   github.com/gastownhall/gascity/examples/gastown 0.396s
```

### 3.2 Full Maintenance Script Push Suite Execution

```text
go test -v -run "TestJsonlExportPush" ./examples/gastown
=== RUN   TestJsonlExportPushBootstrapCreatesRemoteMainWhenMissing
--- PASS: TestJsonlExportPushBootstrapCreatesRemoteMainWhenMissing (0.23s)
=== RUN   TestJsonlExportPushFailureRecoversFromMalformedState
--- PASS: TestJsonlExportPushFailureRecoversFromMalformedState (0.21s)
=== RUN   TestJsonlExportPushFailureRecoversFromWrongShapeState
--- PASS: TestJsonlExportPushFailureRecoversFromWrongShapeState (0.21s)
=== RUN   TestJsonlExportPushSuccessWritesLastPushAt
--- PASS: TestJsonlExportPushSuccessWritesLastPushAt (0.24s)
=== RUN   TestJsonlExportPushFailureWritesLastPushStderr
--- PASS: TestJsonlExportPushFailureWritesLastPushStderr (0.22s)
=== RUN   TestJsonlExportPushRetriesAndRecordsSuccessAfterTransientFailure
--- PASS: TestJsonlExportPushRetriesAndRecordsSuccessAfterTransientFailure (0.27s)
=== RUN   TestJsonlExportPushRetriesUnderCommaDecimalLocale
--- PASS: TestJsonlExportPushRetriesUnderCommaDecimalLocale (0.24s)
=== RUN   TestJsonlExportPushRetryRebasesAfterRemoteAdvanceRace
--- PASS: TestJsonlExportPushRetryRebasesAfterRemoteAdvanceRace (0.36s)
=== RUN   TestJsonlExportPushRetriesThreeTimesBeforeRecordingFailure
--- PASS: TestJsonlExportPushRetriesThreeTimesBeforeRecordingFailure (0.34s)
=== RUN   TestJsonlExportPushSuccessAfterFailureClearsLastPushStderr
--- PASS: TestJsonlExportPushSuccessAfterFailureClearsLastPushStderr (0.26s)
=== RUN   TestJsonlExportPushModeAttemptsPushWhenOriginConfigured
--- PASS: TestJsonlExportPushModeAttemptsPushWhenOriginConfigured (0.25s)
=== RUN   TestJsonlExportPushModeMemoizesOriginForRun
--- PASS: TestJsonlExportPushModeMemoizesOriginForRun (0.24s)
=== RUN   TestJsonlExportPushFailureEscalationBodyIncludesStderrAndRemediation
--- PASS: TestJsonlExportPushFailureEscalationBodyIncludesStderrAndRemediation (0.24s)
=== RUN   TestJsonlExportPushFailureEscalatesOncePerUnresolvedFailure
--- PASS: TestJsonlExportPushFailureEscalatesOncePerUnresolvedFailure (0.55s)
PASS
ok   github.com/gastownhall/gascity/examples/gastown 3.932s
```

All 14 push recovery, state transition, and retry tests passed 100%.

---

## 4. Hardware & Inference Telemetry

Captured from local ASUS Ascent GX10 bare-metal silicon (`colt-gpu-01` @ `10.82.0.3:8000` running `nvidia/llama-3.3-nemotron-super-49b-v1.5` under 64K FP8 context):

| Metric Dimension                    | Value / Telemetry Reading                  |
| :---------------------------------- | :----------------------------------------- |
| **Model Engine**                    | `nvidia/llama-3.3-nemotron-super-49b-v1.5` |
| **Context Limit**                   | 65,536 tokens                              |
| **Cumulative Prefill Tokens**       | 2,531,937                                  |
| **Cumulative Generation Tokens**    | 93,064                                     |
| **Prefix Cache Queries / Hits**     | 2,531,937 / 2,127,984                      |
| **Prefix Cache Hit Rate**           | **84.05%** Radix cache efficiency          |
| **Mean Time to First Token (TTFT)** | **671.68 ms** (718.70s / 1,070 requests)   |
| **Queue Concurrency**               | 0.0 running / 0.0 waiting                  |

Zero cloud API leakage; 100% sovereign local execution.

---

## 5. Sovereign Staging & Deliverables

- **Bead Closed**: `gcs-m30`
- **Rig Commit**: `7b3842355` on branch `gcs-m30` in `rigs/gascity`
- **Public Policy Adherence**: Zero public GitHub tracker noise. Fix and regression tests staged cleanly on sovereign branch.
