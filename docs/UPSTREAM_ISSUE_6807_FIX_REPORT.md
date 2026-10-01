<!-- markdownlint-disable MD013 -->

# Upstream Gas City Issue Resolution Report: Issue #6807

**Issue Reference**: [`gastownhall/gascity#6807`](https://github.com/gastownhall/gascity/issues/6807)
**Governing Bead**: `gcs-mgo`
**Target Repository**: `rigs/gascity`
**Branch**: `gcs-mgo` (Commit: `0a630e35c`)
**Resolution Timestamp**: 2026-10-01T07:04:59-07:00
**Author**: Mayor (Headquarters Commandant), Camp Colt
**Verification Status**: VERIFIED (Unit & Regression Tests Passed, 100%)

---

## 1. Problem Formulation & Root Cause Analysis

### 1.1 Upstream Defect Description

In Gas City's control dispatch system, a retry or convergence control bead whose underlying attempt **passed** could fail during its final close operation if the Dolt database write encountered a concurrent serialization conflict:

```text
Error 1213 (40001): serialization failure: this transaction conflicts with a committed transaction from another client, try restarting transaction
```

When this occurred:

1. The store layer attempted three retries (`bdTransientWriteAttempts` / `nativeWriteAttempts`), but on busy multi-agent hubs (such as Camp Colt's sovereign Dolt instance under concurrent worker turns), intense contention could exhaust the initial burst.
2. The exhausted error was returned to `handleControlDispatchError` in `cmd/gc/cmd_convoy_dispatch.go`.
3. `handleControlDispatchError` classified the error via `ClassifyControllerError(err)`.
4. Because the classifier lacked needles for Dolt's serialization syntax, it returned `TierNone` instead of `TierAvailability`.
5. `TierNone` was treated as an unrecoverable hard error, routing straight to `quarantineControlFailureBead`, which closed the bead with:
   - `gc.outcome = fail`
   - `gc.failure_class = hard`
   - `gc.failure_reason = control_dispatch_error`
   - `gc.control_quarantined = true`
6. If the control bead carried `on_fail = abort_scope`, `terminalAbortScopeFailure` aborted the entire enclosing workflow scope, destroying valid, verified staff work simply because of a transient database commit conflict.

### 1.2 Root Cause Identification

Inspection of [`internal/dispatch/control.go:497-534`](file:///home/camp-colt-mayor-agent/colony/rigs/gascity/internal/dispatch/control.go#L497) revealed that `transientNeedles` contained MySQL error needles (`"lock wait timeout"`, `"deadlock found"`) and SQLite needles (`"database is locked"`, `"sqlite_busy"`), but completely omitted Dolt SQL Server's distinctive error phrasing:

- `"serialization failure"`
- `"conflicts with a committed transaction"`

Both [`internal/beads/native_dolt_store.go:2293`](file:///home/camp-colt-mayor-agent/colony/rigs/gascity/internal/beads/native_dolt_store.go#L2293) and [`internal/beads/bdstore.go:2508`](file:///home/camp-colt-mayor-agent/colony/rigs/gascity/internal/beads/bdstore.go#L2508) already recognized these needles as retryable transient conflicts, but the dispatch classifier had an architectural blind spot.

---

## 2. Technical Implementation

### 2.1 Code Changes

1. **`internal/dispatch/control.go`**:
   Added `"serialization failure"` and `"conflicts with a committed transaction"` to `transientNeedles` mapped to `TierAvailability`:

   ```go
   var transientNeedles = []transientNeedle{
    {needle: "too many connections", tier: TierAvailability},
    {needle: "lock wait timeout", tier: TierAvailability},
    {needle: "deadlock found", tier: TierAvailability},
    {needle: "serialization failure", tier: TierAvailability},
    {needle: "conflicts with a committed transaction", tier: TierAvailability},
    {needle: "database is locked", tier: TierAvailability},
    {needle: "database table is locked", tier: TierAvailability},
    {needle: "sqlite_busy", tier: TierAvailability},
   ```

2. **Unit Test Updates (`internal/dispatch/control_retry_test.go`)**:
   Added test cases to `TestClassifyControllerErrorTiers`:
   - `dolt serialization failure`: verifies full Dolt 1213 error string classifies as `TierAvailability` and `IsTransientControllerError = true`.
   - `dolt transaction conflict`: verifies transaction conflict fragment classifies as `TierAvailability`.

---

## 3. Empirical Test Verification

### 3.1 Targeted Test Execution

```bash
$ go test -v ./internal/dispatch/ -run "TestClassifyControllerError"
=== RUN   TestClassifyControllerErrorTiers
...
=== CONT  TestClassifyControllerErrorTiers/dolt_serialization_failure
=== CONT  TestClassifyControllerErrorTiers/dolt_transaction_conflict
--- PASS: TestClassifyControllerErrorTiers (0.00s)
    --- PASS: TestClassifyControllerErrorTiers/dolt_serialization_failure (0.00s)
    --- PASS: TestClassifyControllerErrorTiers/dolt_transaction_conflict (0.00s)
PASS
ok      github.com/gastownhall/gascity/internal/dispatch   0.015s
```

### 3.2 Full Package Regression Run

```bash
$ go test ./internal/dispatch/...
ok      github.com/gastownhall/gascity/internal/dispatch   1.377s
```

100% pass across all dispatch tests with zero regressions.

---

## 4. Hardware & Inference Telemetry

Captured live from the bare-metal Grace Blackwell GB10 inference appliance (`colt-gpu-01` @ `10.82.0.3:8000`):

| Telemetry Dimension                 | Reading / Metric                           |
| :---------------------------------- | :----------------------------------------- |
| **Model Engine**                    | `nvidia/llama-3.3-nemotron-super-49b-v1.5` |
| **Context Window**                  | 65,536 tokens (64K FP8)                    |
| **Cumulative Prefill Tokens**       | 2,528,761                                  |
| **Cumulative Generation Tokens**    | 90,760                                     |
| **Prefix Cache Queries / Hits**     | 2,528,761 / 2,125,680                      |
| **Prefix Cache Hit Rate**           | **84.06%**                                 |
| **Mean Time to First Token (TTFT)** | **740 ms** (685.11s / 926 turns)           |
| **Batch Concurrency**               | 0.0 running / 0.0 waiting                  |

---

## 5. Sovereign Staging & Deliverables

- **Bead Closed**: `gcs-mgo`
- **Rig Commit**: `0a630e35c` on branch `gcs-mgo` in `rigs/gascity`
- **Public Policy Adherence**: Zero public GitHub tracker noise. Issue staged cleanly on sovereign maintenance branch.
