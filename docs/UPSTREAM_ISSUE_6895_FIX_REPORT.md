<!-- markdownlint-disable MD013 -->

# Upstream Gas City Issue Resolution Report: Issue #6895

**Issue Reference**: [`gastownhall/gascity#6895`](https://github.com/gastownhall/gascity/issues/6895)
**Governing Bead**: `gcs-rky`
**Target Repository**: `rigs/gascity`
**Branch**: `gcs-rky` (Commit: `b8e4a2f0b`)
**Resolution Timestamp**: 2026-10-01T12:05:08-07:00
**Author**: Mayor (Headquarters Commandant), Camp Colt
**Verification Status**: VERIFIED (Targeted reproduction tests and full 50+ sync session bead test suites passed 100%)

---

## 1. Problem Formulation & Root Cause Analysis

### 1.1 Upstream Defect Description

In Gas City session reconciliation (`syncSessionBeads` and configured named session preserve logic):
When an agent template defines `max_active_sessions = 1` and also backs a configured named session, `poolRuntimeSessionName` deliberately steps the pool slot aside onto `<name>-pool` to avoid colliding with the named session name (`spec.SessionName`).

During runtime reconciliation, phantom-identity collapse stamps `configured_named_session=true` on the slot's bead. However, during the scan for reconfigured named sessions in `syncSessionBeads`:

```go
if strings.TrimSpace(b.Metadata["session_name"]) == spec.SessionName {
    continue
}
```

Because the singleton pool slot wears its own `<name>-pool` step-aside name, the string comparison evaluated to `false`. As a result:

- The reconciler concluded that the named session had drifted.
- It closed the bead with the reason `"session reconfigured: superseded by new agent config"`.
- If the session was running, it was terminated or continuously killed and recreated across reconciler ticks.
- Stopped sessions also had their beads prematurely killed.

### 1.2 Root Cause Identification

1. **In `cmd/gc/session_beads.go`**:
   `preserveConfiguredNamedSessionBead`, `preserveConfiguredNamedSessionBeadInfo`, and `syncSessionBeadsWithSnapshotAndRigStores` compared `b.Metadata["session_name"]` directly to `spec.SessionName` without accounting for the canonical step-aside name that `poolRuntimeSessionName` assigns to singleton pool identities backed by `max_active_sessions = 1`.

2. **Expected Invariant**:
   For any agent where `spec.Agent.UsesCanonicalSingletonPoolIdentity()` is true, the runtime session name satisfies the configured named session specification if it matches either:
   - `spec.SessionName` (canonical named session name), or
   - `poolRuntimeSessionName(cfg, spec.Identity, spec.Agent.QualifiedName(), false)` (`<name>-pool` step-aside name).

---

## 2. Technical Implementation

### 2.1 Code Changes

1. **`cmd/gc/session_beads.go`**:
   Introduced `namedSessionRuntimeNameSatisfiesSpec(cfg, sessionName, spec)`:

   ```go
   // namedSessionRuntimeNameSatisfiesSpec reports whether sessionName satisfies
   // spec's runtime session name. It accepts spec.SessionName, or for a singleton
   // pool agent that uses canonical singleton pool identity, the identity-derived
   // pool step-aside name (poolRuntimeSessionName) that avoids colliding with the
   // named session.
   func namedSessionRuntimeNameSatisfiesSpec(cfg *config.City, sessionName string, spec namedSessionSpec) bool {
       sessionName = strings.TrimSpace(sessionName)
       if sessionName == "" {
           return false
       }
       if sessionName == strings.TrimSpace(spec.SessionName) {
           return true
       }
       if spec.Agent != nil && spec.Agent.UsesCanonicalSingletonPoolIdentity() {
           stepAside := poolRuntimeSessionName(cfg, spec.Identity, spec.Agent.QualifiedName(), false)
           if sessionName == stepAside {
               return true
           }
       }
       return false
   }
   ```

2. **Updated Call Sites**:

   - `preserveConfiguredNamedSessionBead`: replaced direct string comparison with `namedSessionRuntimeNameSatisfiesSpec`.
   - `preserveConfiguredNamedSessionBeadInfo`: replaced direct string comparison with `namedSessionRuntimeNameSatisfiesSpec`.
   - `syncSessionBeadsWithSnapshotAndRigStores`: replaced direct string comparison with `namedSessionRuntimeNameSatisfiesSpec`.

3. **Regression Tests (`cmd/gc/session_beads_singleton_pool_test.go`)**:
   Added `TestSyncSessionBeadsKeepsCollapsedSingletonPoolSession` with two subtests:
   - `running_runtime`: Confirms that a running singleton pool session wearing `<name>-pool` is preserved and not closed as reconfigured.
   - `stopped_runtime`: Confirms that a stopped singleton pool session wearing `<name>-pool` is preserved and not closed as reconfigured.

---

## 3. Empirical Verification Evidence

### 3.1 Targeted Test Execution

```text
=== RUN   TestSyncSessionBeadsKeepsCollapsedSingletonPoolSession
=== RUN   TestSyncSessionBeadsKeepsCollapsedSingletonPoolSession/running_runtime
=== RUN   TestSyncSessionBeadsKeepsCollapsedSingletonPoolSession/stopped_runtime
--- PASS: TestSyncSessionBeadsKeepsCollapsedSingletonPoolSession (0.00s)
    --- PASS: TestSyncSessionBeadsKeepsCollapsedSingletonPoolSession/running_runtime (0.00s)
    --- PASS: TestSyncSessionBeadsKeepsCollapsedSingletonPoolSession/stopped_runtime (0.00s)
PASS
ok   github.com/gastownhall/gascity/cmd/gc 0.423s
```

### 3.2 Full Session Sync Suite Execution

Ran all 50+ `TestSyncSessionBeads*` tests:

```text
go test -v -count=1 -run "TestSyncSessionBeads" ./cmd/gc
...
--- PASS: TestSyncSessionBeads_RecreatesDriftedNamedSessionRuntimeName (0.00s)
--- PASS: TestSyncSessionBeads_DoesNotCompactLivePoolSlotIdentity (0.00s)
--- PASS: TestSyncSessionBeads_RewritesStalePoolSlotWhenConcreteIdentityAgrees (0.00s)
--- PASS: TestSyncSessionBeads_PoolSessionNameFailureLeavesReachableFailedCreate (0.00s)
--- PASS: TestSyncSessionBeads_ConfigDrift (0.00s)
--- PASS: TestSyncSessionBeads_OrphanDetection (0.00s)
--- PASS: TestSyncSessionBeads_ResumedAfterSuspension (0.00s)
PASS
ok   github.com/gastownhall/gascity/cmd/gc 0.579s
```

All session reconciliation tests passed with zero regressions. Genuine drifts continue to be detected and recreated as intended.

---

## 4. Hardware & Inference Telemetry

Captured from local ASUS Ascent GX10 bare-metal silicon (`colt-gpu-01` @ `10.82.0.3:8000` running `nvidia/llama-3.3-nemotron-super-49b-v1.5` under 64K FP8 context):

| Metric Dimension                    | Value / Telemetry Reading                  |
| :---------------------------------- | :----------------------------------------- |
| **Model Engine**                    | `nvidia/llama-3.3-nemotron-super-49b-v1.5` |
| **Context Limit**                   | 65,536 tokens                              |
| **Cumulative Prefill Tokens**       | 2,531,407                                  |
| **Cumulative Generation Tokens**    | 92,680                                     |
| **Prefix Cache Queries / Hits**     | 2,531,407 / 2,127,600                      |
| **Prefix Cache Hit Rate**           | **84.05%** Radix cache efficiency          |
| **Mean Time to First Token (TTFT)** | **681.78 ms** (713.14s / 1,046 requests)   |
| **Queue Concurrency**               | 0.0 running / 0.0 waiting                  |

Zero cloud API leakage; 100% sovereign local execution.

---

## 5. Sovereign Staging & Deliverables

- **Bead Closed**: `gcs-rky`
- **Rig Commit**: `b8e4a2f0b` on branch `gcs-rky` in `rigs/gascity`
- **Public Policy Adherence**: Zero public GitHub tracker noise. Fix and regression tests staged cleanly on sovereign branch.
