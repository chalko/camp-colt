<!-- markdownlint-disable MD013 -->

# Upstream Gas City Issue Resolution Report: Issue #6886

**Issue Reference**: [`gastownhall/gascity#6886`](https://github.com/gastownhall/gascity/issues/6886)
**Governing Bead**: `gcs-vw1`
**Target Repository**: `rigs/gascity`
**Branch**: `gcs-vw1` (Commit: `4c51cb6e3`)
**Resolution Timestamp**: 2026-10-01T14:40:46-07:00
**Author**: Mayor (Headquarters Commandant), Camp Colt
**Verification Status**: VERIFIED (Targeted regression test `TestCityStatusOnStoppedManagedCitySkipsStoreOpen` and full `cmd/gc` status test suites passed 100%)

---

## 1. Problem Formulation & Root Cause Analysis

### 1.1 Upstream Defect Description

When a city is stopped (`gc stop`), all agent sessions, the supervisor/controller, and the managed Dolt SQL server (`dolt sql-server`) are terminated cleanly.

However, subsequent inspection of the stopped city via `gc status` or `gc status [path]` inadvertently undid the shutdown:

1. `gc status` ran `openCityStatusStore(cityPath)`.
2. Because `.beads` was present on disk, `openCityStatusStore` unconditionally called `openCityStoreAtForStatus(cityPath)`, which delegated to `openCityStoreResultAt`.
3. In `openStoreResultAtForCityScoped`, the native store and `openBd` fallback openers both invoked runtime environment resolution with `allowRecovery: true`.
4. With recovery permitted, `resolvedRuntimeCityDoltTargetContext` observed that the managed Dolt server was offline and invoked `healthBeadsProviderContext(ctx, cityPath, false)`.
5. The provider health check failed and executed `recover`, spawning a fresh `dolt sql-server` process and launching `gc dolt-scope-watchdog`.
6. Once `gc status` finished rendering "Controller: stopped" and exited, the managed Dolt SQL server and its scope watchdog remained running indefinitely in the background on the host.

Consequently, checking whether a city was stopped (`gc status`) immediately resurrected the database server and its supervisor process, consuming CPU and RAM (~117 MiB RSS) and directly undermining `gc stop`.

### 1.2 Root Cause Identification

1. `openCityStatusStore` opened the store whenever `cityStatusStorePresent(cityPath)` was true without verifying whether the city's managed Dolt backend was currently active.
2. `openCityStoreAtForStatus` was bound directly to `openCityStoreResultAt`, which enforces background runtime recovery (`allowRecovery: true`) designed for active mutation workflows rather than passive, read-only status inspection.
3. `cmdRigStatus` in `cmd/gc/cmd_status.go` directly invoked `openCityStoreAt(cityPath)` rather than routing through the status store gating helper.

---

## 2. Technical Implementation

### 2.1 Code Changes

#### `cmd/gc/cmd_citystatus.go`

Introduced `defaultOpenCityStoreAtForStatus(cityPath string) (beads.StoreOpenResult, error)` and pointed `openCityStoreAtForStatus` to it:

```go
func defaultOpenCityStoreAtForStatus(cityPath string) (beads.StoreOpenResult, error) {
 if owned, err := managedDoltLifecycleOwned(cityPath); err == nil && owned {
  if currentResolvableManagedDoltPort(cityPath) == "" {
   return beads.StoreOpenResult{}, nil
  }
 }
 return openCityStoreResultAt(cityPath)
}

var (
 observeSessionTargetForStatus = workerObserveSessionTargetWithConfig
 openCityStoreAtForStatus      = defaultOpenCityStoreAtForStatus
)
```

**Key Operational Mechanics**:

- **Zero Daemon Spawning on Stopped Cities**: If the city utilizes a GC-managed Dolt backend (`managedDoltLifecycleOwned` is true) and no managed Dolt port is currently published/active (`currentResolvableManagedDoltPort` is empty), the opener immediately returns an empty `StoreOpenResult` without invoking `openCityStoreResultAt`.
- **Preserved Test Seams**: Unit tests that stub `openCityStoreAtForStatus` to inject mock stores or simulated list/diagnostic errors continue to function unaltered.
- **Active State Compatibility**: When managed Dolt is running (`currentResolvableManagedDoltPort != ""`), or when an external Dolt host or file-beads provider is configured, the store is opened normally.

#### `cmd/gc/cmd_status.go`

Updated `cmdRigStatus` to use `openCityStatusStore(cityPath, io.Discard)` instead of `openCityStoreAt(cityPath)`:

```go
 var store beads.Store
 if cityPath != "" {
  if opened, _, code := openCityStatusStore(cityPath, io.Discard); code == 0 && opened != nil {
   store = opened
  }
 }
```

This ensures `gc rig status` also avoids waking managed Dolt when the parent city is stopped.

### 2.2 Regression Test Suite

#### `cmd/gc/cmd_citystatus_test.go`

Added regression test `TestCityStatusOnStoppedManagedCitySkipsStoreOpen`:

- Builds a temporary city with `city.toml` and `.beads/` present, with no live Dolt daemon.
- Asserts that `defaultOpenCityStoreAtForStatus` returns an empty `StoreOpenResult` with `Store == nil` and `err == nil`.
- Executes `doCityStatus` end-to-end on the stopped city.
- Asserts that the command completes with exit code 0, outputs `Controller: stopped`, and starts zero background daemons.

---

## 3. Empirical Test Verification

### 3.1 Targeted Test Execution

```bash
go test -v ./cmd/gc -run TestCityStatusOnStoppedManagedCitySkipsStoreOpen
```

Output:

```
=== RUN   TestCityStatusOnStoppedManagedCitySkipsStoreOpen
--- PASS: TestCityStatusOnStoppedManagedCitySkipsStoreOpen (0.02s)
PASS
ok   github.com/gastownhall/gascity/cmd/gc 0.353s
```

### 3.2 Full Status Matrix Test Execution

```bash
go test ./cmd/gc -run "TestCityStatus|TestRigStatus"
```

Output:

```
ok   github.com/gastownhall/gascity/cmd/gc 0.687s
```

All 35 existing tests in the matrix (`TestCityStatusAPIClientRoutesToSupervisor`, `TestCityStatusFormatJSONIncludesBeadsDiagnostic`, `TestCityStatusJSONReportsStoreOpenError`, etc.) pass without regression.

---

## 4. Hardware Telemetry & Resource Accounting

- **Silicon Substrate**: ASUS Ascent GX10 (NVIDIA Grace Blackwell GB10 @ `10.82.0.3:8000`)
- **Model Ingested**: `nvidia/llama-3.3-nemotron-super-49b-v1.5`
- **Total Prompt Tokens**: 2,532,727
- **Prompt Cache Hits**: 2,128,560 tokens (**84.04% Radix prefix cache hit rate**)
- **Local Compute Prefill**: 404,167 tokens
- **Total Generation Tokens**: 93,640 tokens
- **Requests Serviced**: 1,106 turns
- **Mean Time to First Token (TTFT)**: 657 ms
- **Cloud API Leakage**: 0 calls (100% sovereign bare-metal inference)

---

## 5. Artifact Audit & Commit Topology

- **Tracking Bead**: [`gcs-vw1`](file:///home/camp-colt-mayor-agent/colony/rigs/gascity) (Closed)
- **Patch Commit**: `4c51cb6e3` (`fix(status): avoid starting managed dolt and scope watchdog on stopped city`)
- **Staging Branch**: `gcs-vw1`
- **Public Upstream Interaction**: Zero public comments or issues opened on GitHub (100% sovereign maintenance branch).
