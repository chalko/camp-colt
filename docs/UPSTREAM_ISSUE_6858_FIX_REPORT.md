<!-- markdownlint-disable MD013 -->

# Upstream Gas City Issue Resolution Report: Issue #6858

**Issue Reference**: [`gastownhall/gascity#6858`](https://github.com/gastownhall/gascity/issues/6858)
**Governing Bead**: `gcs-utp`
**Target Repository**: `rigs/gascity`
**Branch**: `gcs-utp` (Commit: `2e795ffcf`)
**Resolution Timestamp**: 2026-10-01T08:57:37-07:00
**Author**: Mayor (Headquarters Commandant), Camp Colt
**Verification Status**: VERIFIED (Targeted unit tests and classifier equivalence test suites passed 100%)

---

## 1. Problem Formulation & Root Cause Analysis

### 1.1 Upstream Defect Description

In Gas City, creating an ad-hoc session via the HTTP API for an agent template configured with `max_active_sessions = 1` resulted in the session bead remaining stuck indefinitely in `state="start-pending"`. Furthermore, running `gc session pin` or `gc session wake` reported success but never started the worker runtime.

### 1.2 Root Cause Identification

1. **Session Origin Classification**:

   - In [`internal/api/session_create_agent.go`](file:///home/camp-colt-mayor-agent/colony/rigs/gascity/internal/api/session_create_agent.go#L24), API session creation persists metadata `session_origin="ephemeral"`.
   - In [`cmd/gc/session_origin.go:91-163`](file:///home/camp-colt-mayor-agent/colony/rigs/gascity/cmd/gc/session_origin.go#L91), both `isLegacyManualSessionBeadForAgent` and `isLegacyManualSessionInfoForAgent` guarded manual session recognition with:

     ```go
     if cfgAgent == nil || !cfgAgent.SupportsMultipleSessions() {
         return false
     }
     ```

   - For a singleton agent (`max_active_sessions = 1`), `cfgAgent.SupportsMultipleSessions()` evaluated to `false`.
   - Because of this guard, the API-created session bead was NOT recognized as a manual session (`manualSession == false`).

2. **Desired State Eviction**:

   - In `cmd/gc/build_desired_state.go`, because the session had origin `ephemeral` without pool markers, `isPendingPoolCreateInfo` evaluated to `true`, marking `controllerManagedPool = true`.
   - The filtering logic in `buildDesiredState` evaluated:

     ```go
     if controllerManagedPool && !manualSession && !isNamedSessionInfo(info) &&
         !sessionAlreadyDesired && !templateDesired && !poolPartialAlive {
         continue
     }
     ```

   - Because `manualSession == false`, the session was pruned from the desired state map.

3. **Reconciler Deadlock**:
   - In `cmd/gc/session_reconciler.go`, because the session was absent from `desiredState`, it entered the unmanaged session branch (`if !desired`).
   - Line 2267 matched `case pendingCreateSessionStillLeasedInfo(...) { continue }`.
   - The session was never appended to `wakeTargets`, preventing the process starter from ever launching the session runtime.
   - Calling `gc session pin` or `gc session wake` set bead flags, but reconciliation never scheduled the session into `wakeTargets` because it remained absent from `desiredState`.

---

## 2. Technical Implementation

### 2.1 Code Changes

1. **`cmd/gc/session_origin.go`**:
   Removed `|| !cfgAgent.SupportsMultipleSessions()` from both `isLegacyManualSessionBeadForAgent` and `isLegacyManualSessionInfoForAgent`.
   An ad-hoc, API-created session on a configured agent template carrying `session_origin="ephemeral"` without pool markers (`pool_managed`, `pool_slot`) and not marked `dependency_only` is recognized as a manual session regardless of whether the agent template is multi-session or singleton.

2. **Specification Update (`internal/session/REQUIREMENTS.md`)**:
   Updated requirement `SESSION-RECON-015` to explicitly document that controller reconciliation reclassifies ephemeral, pool-marker-free beads as manual across both multi-session and singleton templates, and linked issue `#6858` and new regression test `cmd/gc/api_created_singleton_test.go`.

3. **Regression Test (`cmd/gc/api_created_singleton_test.go`)**:
   Authored `TestBuildDesiredState_APICreatedSingletonAgentSessionBead`:
   - Configures a singleton agent (`min_active_sessions = 0`, `max_active_sessions = 1`).
   - Simulates an API-created session bead (`session_origin = "ephemeral"`, `state = "start-pending"`, `pending_create_claim = "true"`).
   - Verifies `buildDesiredState` retains the session in `desiredState` with `ManualSession: true`.

---

## 3. Empirical Verification Evidence

### 3.1 Targeted Test Execution

```text
=== RUN   TestBuildDesiredState_APICreatedSingletonAgentSessionBead
    api_created_singleton_test.go:54: OpenInfos count: 1, info: [...]
    api_created_singleton_test.go:59: Desired state keys: [s-re-wisp-bk2]
    api_created_singleton_test.go:65: tp: main.TemplateParams{... ManualSession:true ...}
--- PASS: TestBuildDesiredState_APICreatedSingletonAgentSessionBead (0.02s)
PASS
ok   github.com/gastownhall/gascity/cmd/gc 0.348s
```

### 3.2 Regression & Equivalence Testing

```text
=== RUN   TestBuildDesiredState_APICreatedAgentSessionBeadStaysDesired
=== RUN   TestBuildDesiredState_APICreatedAgentSessionBeadStaysDesired/multi_session_agent
=== RUN   TestBuildDesiredState_APICreatedAgentSessionBeadStaysDesired/multi_session_agent_with_always_named_session
--- PASS: TestBuildDesiredState_APICreatedAgentSessionBeadStaysDesired (0.05s)
=== RUN   TestSessionClassifierInfoEquivalence
--- PASS: TestSessionClassifierInfoEquivalence (0.00s across 200+ matrix cases)
PASS
ok   github.com/gastownhall/gascity/cmd/gc 0.588s
```

All session classifier equivalence pairs and desired state lifecycle tests passed cleanly with zero regressions.

---

## 4. Hardware & Inference Telemetry

Captured from local ASUS Ascent GX10 bare-metal silicon (`colt-gpu-01` @ `10.82.0.3:8000` running `nvidia/llama-3.3-nemotron-super-49b-v1.5` under 64K FP8 context):

| Metric Dimension                    | Value / Telemetry Reading                  |
| :---------------------------------- | :----------------------------------------- |
| **Model Engine**                    | `nvidia/llama-3.3-nemotron-super-49b-v1.5` |
| **Context Limit**                   | 65,536 tokens                              |
| **Cumulative Prefill Tokens**       | 2,529,729                                  |
| **Cumulative Generation Tokens**    | 91,464                                     |
| **Prefix Cache Queries / Hits**     | 2,529,729 / 2,126,384                      |
| **Prefix Cache Hit Rate**           | **84.06%**                                 |
| **Mean Time to First Token (TTFT)** | **716.85 ms** (695.35s / 970 turns)        |
| **Queue Concurrency**               | 0.0 running / 0.0 waiting                  |

---

## 5. Sovereign Staging & Deliverables

- **Bead Closed**: `gcs-utp`
- **Rig Commit**: `2e795ffcf` on branch `gcs-utp` in `rigs/gascity`
- **Public Policy Adherence**: Zero public GitHub tracker noise. Fix and regression test staged cleanly on sovereign branch.
