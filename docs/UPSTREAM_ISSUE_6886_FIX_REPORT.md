# Upstream Gas City Issue #6886 Resolution Report

**Date**: 2026-10-01T04:00:00-07:00
**Author**: Chief of Staff (`colt-cos`)
**Billet**: Always-On Core Watch
**Rig**: `rigs/gascity`
**Bead**: `gcs-b8o` (Closed)
**Upstream Issue Reference**: [gastownhall/gascity#6886](https://github.com/gastownhall/gascity/issues/6886)
**Git Branch**: `gcs-b8o` (`rigs/gascity`)
**Commit**: `b07252151`
**Classification**: Bug Fix & Daemon Lifecycle Containment

---

## 1. Executive Summary

Upstream Gas City Issue #6886 identifies a daemon lifecycle regression where executing `gc status` against a **stopped, unregistered** city unexpectedly spawns the city's managed `dolt sql-server` process and a background `__gc-managed-dolt-scope-watchdog` process, both of which outlive the CLI invocation:

```text
gc    ppid=1      __gc-managed-dolt-scope-watchdog <city>/.gc/runtime/packs/dolt/dolt-config.yaml ...
dolt  ppid=<wd>   dolt sql-server --config <city>/.gc/runtime/packs/dolt/dolt-config.yaml
```

Because `gc status` is the canonical diagnostic command an operator runs right after `gc stop` to verify teardown success, running `gc status` immediately undoes the stop by leaving a fresh Dolt server and watchdog active in the process table.

Camp Colt engineering resolved this defect locally on sovereign maintenance branch `gcs-b8o` in `rigs/gascity`:

1. **Root Cause Rectified**: Isolated the premature daemon launch to `openCityStoreAtForStatus` in [`cmd/gc/city_status_snapshot.go`](file:///home/camp-colt-mayor-agent/colony/rigs/gascity/cmd/gc/city_status_snapshot.go), which previously routed directly to `openCityStoreResultAt`. The standard store opener ran with `allowRecovery: true`, which caused preflight and one-shot store builders to mistake a stopped Dolt server for an unexpected outage and execute `health` / `recover`, launching `start-managed` and the watchdog.
2. **Dedicated Status Opener**: Introduced `openCityStoreResultAtForStatus(cityPath)` in [`cmd/gc/main.go`](file:///home/camp-colt-mayor-agent/colony/rigs/gascity/cmd/gc/main.go), which threads `allowRecovery: false` through store opening, preflight checking, and native open resolution.
3. **No-Recovery Runners & Stores**: Added `bdCommandRunnerForCityNoRecovery`, `bdCommandRunnerForRigNoRecovery`, `bdStoreForCityWithConfigNoRecovery`, and `bdStoreForRigWithConfigNoRecovery` in [`cmd/gc/bd_env.go`](file:///home/camp-colt-mayor-agent/colony/rigs/gascity/cmd/gc/bd_env.go).
4. **Rig Status Protection**: Updated `cmdRigStatus` in [`cmd/gc/cmd_status.go`](file:///home/camp-colt-mayor-agent/colony/rigs/gascity/cmd/gc/cmd_status.go) to use `openCityStatusStore` instead of `openCityStoreAt`.
5. **Empirical Regression Tests**: Created [`cmd_citystatus_stopped_city_test.go`](file:///home/camp-colt-mayor-agent/colony/rigs/gascity/cmd/gc/cmd_citystatus_stopped_city_test.go) with tests `TestCityStatusOnStoppedCityDoesNotStartManagedDolt` and `TestRigStatusOnStoppedCityDoesNotStartManagedDolt`, proving that status commands on a stopped city start zero daemons.
6. **Zero Upstream Noise**: Zero comments or issues were posted to upstream public trackers.

---

## 2. Root Cause Analysis

Tracing the execution path of `gc status <cityPath>` on a stopped city:

1. `cmdCityStatus` calls `openCityStatusStore(cityPath, stderr)` in `cmd/gc/city_status_snapshot.go`.
2. `openCityStatusStore` invokes `openCityStoreAtForStatus(cityPath)`. In previous builds, `openCityStoreAtForStatus` was an alias for `openCityStoreResultAt`.
3. `openCityStoreResultAt` invokes `openStoreResultAtForCityScoped`. This opener builds:
   - `openBd`: uses `bdCommandRunnerForCity(cityPath)` which invokes `bdRuntimeEnvWithError(cityPath)` (`allowRecovery: true`).
   - `PreflightChecker`: uses `preflightBDContextReader(cityPath)` which executes `bdCommandRunnerForCity` (`allowRecovery: true`).
   - `OpenNativeStore`: uses `nativeDoltOneShotOpenEnvForScope(cityPath)` (`allowRecovery: true`).
4. When `PreflightChecker` or `OpenNativeStore` evaluates the stopped city's endpoint, `resolvedRuntimeCityDoltTargetContext` observes that the Dolt port is unallocated. Because `allowRecovery` was set to `true`, it attempted recovery via `healthBeadsProviderContext(ctx, cityPath, false)`.
5. The `health` probe failed against the offline server, causing `healthBeadsProviderContext` to trigger `runProviderOpWithEnvContext(ctx, script, providerEnv, "recover")`.
6. The `gc-beads-bd.sh recover` op invoked `gc dolt-state start-managed`, which spawned `startManagedDoltSQLServerWithScopeWatchdog`.
7. `gc status` rendered "Controller: stopped" and exited, while the spawned Dolt server and watchdog remained orphaned in the process table.

---

## 3. Engineering Implementation

### A. Non-Recovering Status Store Opener (`cmd/gc/main.go`)

```go
func openCityStoreResultAtForStatus(cityPath string) (beads.StoreOpenResult, error) {
 return openStoreResultAtForCityScopedWithRecovery(cityPath, cityPath, nil, gate.ModeUnset, false, false, false, false, false)
}
```

Threaded `allowRecovery bool` through `openStoreResultAtForCityScopedWithRecovery`:

- When `allowRecovery == false`, `openBd` uses `openBdStoreAtScopedWithRecovery(..., false)`.
- `PreflightChecker` uses `newBeadsPreflightCheckerWithRecovery(runtimeCityPath, provider, false)`.
- `OpenNativeStore` uses `nativeDoltOneShotOpenEnvForScopeNoRecovery(runtimeCityPath, cfg, scopeRoot)`.

### B. Non-Recovering Command Runners & Builders (`cmd/gc/bd_env.go`)

- Added `bdCommandRunnerForCityNoRecovery(cityPath)` and `bdCommandRunnerForRigNoRecovery(cityPath, cfg, rigDir)`.
- Added `bdStoreForCityWithConfigNoRecovery` and `bdStoreForRigWithConfigNoRecovery`.
- Added `nativeDoltOneShotOpenEnvForScopeNoRecovery` and `nativeDoltOpenEnvForScopeWithRecoveryContext`.

### C. Status Command Wiring (`cmd/gc/cmd_citystatus.go` & `cmd/gc/cmd_status.go`)

- Wired `openCityStoreAtForStatus = openCityStoreResultAtForStatus` in `cmd/gc/cmd_citystatus.go`.
- Updated `cmdRigStatus` in `cmd/gc/cmd_status.go` to use `openCityStatusStore(cityPath, io.Discard)` instead of `openCityStoreAt(cityPath)`.

---

## 4. Test Verification Evidence

### A. Targeted Regression Test

Executed [`cmd/gc/cmd_citystatus_stopped_city_test.go`](file:///home/camp-colt-mayor-agent/colony/rigs/gascity/cmd/gc/cmd_citystatus_stopped_city_test.go):

```bash
go test -v ./cmd/gc -run "TestCityStatusOnStoppedCityDoesNotStartManagedDolt|TestRigStatusOnStoppedCityDoesNotStartManagedDolt"
```

Output:

```text
=== RUN   TestCityStatusOnStoppedCityDoesNotStartManagedDolt
--- PASS: TestCityStatusOnStoppedCityDoesNotStartManagedDolt (0.36s)
=== RUN   TestRigStatusOnStoppedCityDoesNotStartManagedDolt
--- PASS: TestRigStatusOnStoppedCityDoesNotStartManagedDolt (0.00s)
PASS
ok   github.com/gastownhall/gascity/cmd/gc 0.802s
```

### B. Status Suite Conformance

All 34 existing status test scenarios in `cmd/gc` passed with zero errors (`0.632s`).

---

## 5. Telemetry Audit Record

Captured at completion of implementation and verification:

- **Host Node**: ASUS Ascent GX10 / NVIDIA Grace Blackwell GB10 (`colt-gpu-01`)
- **Model Engine**: `nvidia/llama-3.3-nemotron-super-49b-v1.5` @ `10.82.0.3:8000`
- **Total Prefill Tokens**: 2,526,992
- **Total Generation Tokens**: 89,266
- **Prefix Cache Hits**: 2,124,464
- **Prefix Cache Hit Rate**: **84.07%**
- **Concurrency**: 0.0 running / 0.0 waiting
