<!-- markdownlint-disable MD013 -->

# Upstream Gas City Issue Resolution Report: Issue #6906

**Issue Reference**: [`gastownhall/gascity#6906`](https://github.com/gastownhall/gascity/issues/6906)
**Governing Bead**: `gcs-79u`
**Target Repository**: `rigs/gascity`
**Branch**: `gcs-79u` (Commit: `1d14bcee0`)
**Resolution Timestamp**: 2026-10-01T12:24:02-07:00
**Author**: Mayor (Headquarters Commandant), Camp Colt
**Verification Status**: VERIFIED (Targeted Node.js harness test and full 70+ hook test suites passed 100%)

---

## 1. Problem Formulation & Root Cause Analysis

### 1.1 Upstream Defect Description

In Gas City's native Pi coding agent extension (`internal/bootstrap/packs/core/overlay/per-provider/pi/.pi/extensions/gc-hooks.js`):

1. The hook invoked `execFileSync("gc", args, ...)` with a hardcoded `"gc"` binary name, completely ignoring the `GC_BIN` environment variable supplied by Gas City to managed roles.
2. The hook prepended a hardcoded `PATH_PREFIX` (`/opt/homebrew/bin:/usr/local/bin:...`) in front of `process.env.PATH` when constructing the child execution environment:

   ```javascript
   PATH: PATH_PREFIX + (process.env.PATH || "");
   ```

3. Consequently, in isolated enclaves where the supervisor and role configure `GC_BIN` pointing to an isolated/pinned binary (e.g., `/opt/isolated/bin/gc`), and where `PATH` places the isolated runtime first:
   - `execFileSync` looked up `"gc"` on the prepended `PATH`, resolving `/usr/local/bin/gc` instead.
   - Any descendant processes (such as legacy nudge pollers or child scripts) inherited a `PATH` where `/usr/local/bin` shadowed the isolated runtime.

### 1.2 Root Cause Identification

1. Sibling providers (`opencode`, `mimocode`, `antigravity`, `cursor`, `copilot`, `codex`) had previously been upgraded to respect `GC_BIN` (e.g., commit `1afeae4186` for OpenCode). However, the native Pi hook was omitted during that migration and remained pinned to `GC_PI_HOOK_VERSION = 9` with bare `"gc"`.
2. Prepended `PATH_PREFIX` unconditionally shadowed whatever runtime directory was specified in `process.env.PATH`.

---

## 2. Technical Implementation

### 2.1 Code Changes

1. **`internal/bootstrap/packs/core/overlay/per-provider/pi/.pi/extensions/gc-hooks.js`**:

   - Bumped `GC_PI_HOOK_VERSION` from `9` to `10`.
   - Defined `const GC_BIN = process.env.GC_BIN || "gc";`.
   - Introduced `hookPath()`:

     ```javascript
     function hookPath() {
       const currentPath = process.env.PATH || "";
       if (process.env.GC_BIN) {
         const gcDir = path.dirname(process.env.GC_BIN);
         const prefix = gcDir && gcDir !== "." ? `${gcDir}:` : "";
         return `${prefix}${currentPath}${
           currentPath ? ":" : ""
         }${PATH_PREFIX}`;
       }
       return PATH_PREFIX + currentPath;
     }
     ```

     When `GC_BIN` is provided, its containing directory is placed first, the caller's runtime `PATH` is preserved, and fallback locations (`PATH_PREFIX`) are appended. When `GC_BIN` is absent, standard historical prefixing is preserved.

   - Updated `run` to invoke `execFileSync(GC_BIN, args, ...)` with `PATH: hookPath()`.
   - Updated `logRunFailure` to report `GC_BIN` rather than hardcoded `"gc"`.

2. **`internal/hooks/hooks.go`**:

   - Bumped `managedPiHookVersion` to `10`. This ensures existing on-disk managed Pi hooks (version 9) are recognized as needing upgrade and automatically replaced upon `gc hooks install` or container startup.

3. **`internal/hooks/hooks_test.go`**:
   - Updated version markers in `TestInstallPiHookUsesCurrentExtensionAPI` and `TestPiHookNeedsUpgradeComparesParsedVersion`.
   - Added `TestInstallPiHookSelectsGCBinAndPreservesPath`: embeds a Node.js test harness that intercepts `child_process.execFileSync` and verifies:
     - Case 1: When `GC_BIN` is set, `GC_BIN` is invoked and `PATH` places the directory containing `GC_BIN` ahead of `/usr/local/bin`.
     - Case 2: When `GC_BIN` is unset, `"gc"` is invoked and standard fallback prefixing applies.

---

## 3. Empirical Verification Evidence

### 3.1 Targeted Test Execution

```text
=== RUN   TestInstallPiHookSelectsGCBinAndPreservesPath
--- PASS: TestInstallPiHookSelectsGCBinAndPreservesPath (0.05s)
PASS
ok   github.com/gastownhall/gascity/internal/hooks 0.063s

=== RUN   TestBundledPiHookUsesCurrentExtensionAPI
--- PASS: TestBundledPiHookUsesCurrentExtensionAPI (0.00s)
PASS
ok   github.com/gastownhall/gascity/cmd/gc 0.344s
```

### 3.2 Full Hook Suite Execution

```text
go test -v ./internal/hooks
...
=== RUN   TestInstallPiHookUsesCurrentExtensionAPI
--- PASS: TestInstallPiHookUsesCurrentExtensionAPI (0.00s)
=== RUN   TestInstallPiHookUpgradesLegacyObjectExport
--- PASS: TestInstallPiHookUpgradesLegacyObjectExport (0.00s)
=== RUN   TestPiHookNeedsUpgradeComparesParsedVersion
--- PASS: TestPiHookNeedsUpgradeComparesParsedVersion (0.00s)
=== RUN   TestInstallPiHookPreservesUserAuthoredFile
--- PASS: TestInstallPiHookPreservesUserAuthoredFile (0.00s)
=== RUN   TestInstallPiHookSelectsGCBinAndPreservesPath
--- PASS: TestInstallPiHookSelectsGCBinAndPreservesPath (0.05s)
=== RUN   TestManagedOverlayHookPathsCoverEveryVersionedFile
--- PASS: TestManagedOverlayHookPathsCoverEveryVersionedFile (0.00s)
PASS
ok   github.com/gastownhall/gascity/internal/hooks 0.079s
```

All 70+ hook unit, migration, and preservation tests passed 100%.

---

## 4. Hardware & Inference Telemetry

Captured from local ASUS Ascent GX10 bare-metal silicon (`colt-gpu-01` @ `10.82.0.3:8000` running `nvidia/llama-3.3-nemotron-super-49b-v1.5` under 64K FP8 context):

| Metric Dimension                    | Value / Telemetry Reading                  |
| :---------------------------------- | :----------------------------------------- |
| **Model Engine**                    | `nvidia/llama-3.3-nemotron-super-49b-v1.5` |
| **Context Limit**                   | 65,536 tokens                              |
| **Cumulative Prefill Tokens**       | 2,531,539                                  |
| **Cumulative Generation Tokens**    | 92,776                                     |
| **Prefix Cache Queries / Hits**     | 2,531,539 / 2,127,696                      |
| **Prefix Cache Hit Rate**           | **84.05%** Radix cache efficiency          |
| **Mean Time to First Token (TTFT)** | **679.16 ms** (714.48s / 1,052 requests)   |
| **Queue Concurrency**               | 0.0 running / 0.0 waiting                  |

Zero cloud API leakage; 100% sovereign local execution.

---

## 5. Sovereign Staging & Deliverables

- **Bead Closed**: `gcs-79u`
- **Rig Commit**: `1d14bcee0` on branch `gcs-79u` in `rigs/gascity`
- **Public Policy Adherence**: Zero public GitHub tracker noise. Fix and regression tests staged cleanly on sovereign branch.
