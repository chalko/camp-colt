<!-- markdownlint-disable MD013 -->

# Bug Fix Report: Upstream Gas City Issue #6866 (Pre-Push Pipefail SIGPIPE)

**Governing Bead**: `gcs-f8m`
**Target Rig**: `rigs/gascity`
**Branch**: `gcs-f8m` (Commit `94db4a48d`)
**Upstream Reference**: `https://github.com/gastownhall/gascity/issues/6866`
**Date**: 2026-09-30T05:58:00-07:00
**Status**: RESOLVED & VERIFIED

---

## 1. Issue Overview & Root Cause Analysis

### Upstream Symptom

In `.githooks/pre-push`, the script evaluates whether Go files have changed between the local and remote SHAs to conditionally trigger `make test-fast-parallel`:

```bash
set -euo pipefail
...
  if git diff --name-only "$remote_sha" "$local_sha" -- '*.go' 2>/dev/null | grep -q .; then
    go_changed=1
  fi
```

### Forensic Root Cause

1. `grep -q .` exits with status 0 immediately after reading the first matching character or line, closing the read end of the pipe.
2. In scenarios with large Go diffs (e.g. branch merges, refactors touching many files exceeding the standard 64KB pipe buffer), `git diff` attempts a subsequent write to the closed pipe.
3. The kernel raises `SIGPIPE` to the writing process, causing `git diff` to terminate with exit code `141` (`128 + 13`).
4. Because `set -o pipefail` is active, the entire pipeline adopts the failing exit code `141`.
5. The `if` condition evaluates to false, skipping `go_changed=1`. The pre-push hook exits 0, silently pushing untested code to the remote repository.

---

## 2. Engineering Solution

Rather than piping `git diff` output through an external filter, the hook was refactored to use Git's native `--quiet` inspection:

```bash
  # Check if any .go files changed without piping to grep -q, which triggers
  # SIGPIPE (exit code 141) under set -o pipefail on diffs with multiple matching lines (#6866).
  if ! git diff --quiet "$remote_sha" "$local_sha" -- '*.go' 2>/dev/null; then
    go_changed=1
  fi
```

### Advantages of the Native Inspection

- **Zero Pipe / Zero SIGPIPE**: Single-process execution eliminates inter-process pipe buffers and SIGPIPE termination.
- **Deterministic Semantics**: `git diff --quiet` returns 1 when differences exist and 0 when the trees are identical. Negating with `!` sets `go_changed=1` whenever Go changes exist.
- **Fail-Safe Fallback**: Any error in Git SHA resolution produces a non-zero exit code, safely running the test suite rather than silently bypassing it.

---

## 3. Verification Evidence & Test Automation

A dedicated regression test harness was added at `scripts/test-pre-push-sigpipe.sh`:

### Test Coverage

1. Validates that legacy `git diff | grep -q .` triggers pipe buffer termination.
2. Validates that `! git diff --quiet` reliably detects Go modifications under `set -euo pipefail`.
3. Validates that non-Go changes (e.g. documentation-only commits) cleanly evaluate to `go_changed=0`.

```text
=== Running pre-push large-diff regression test (#6866) ===
1. Verifying legacy 'git diff | grep -q' triggers SIGPIPE 141: CONFIRMED
2. Verifying 'git diff --quiet' detects large Go diff under pipefail: PASS (go_changed=1)
3. Verifying non-Go changes do NOT trigger go_changed: PASS (go_changed=0 for docs-only change)
==========================================
ALL PRE-PUSH REGRESSION TESTS PASSED (100%)
```

### Static Analysis

- `shellcheck rigs/gascity/.githooks/pre-push rigs/gascity/scripts/test-pre-push-sigpipe.sh` passed with **0 errors and 0 warnings**.

---

## 4. Hardware Telemetry & Silicon Measurements

- **Serving Node**: ASUS Ascent GX10 (`colt-gpu-01` @ `10.82.0.3:8000`)
- **Cumulative Prefill Tokens**: `2,379,401`
- **Cumulative Generation Tokens**: `62,974`
- **Radix KV Cache Queries**: `2,379,401`
- **Radix KV Cache Hits**: `1,995,952`
- **Cache Hit Rate**: **83.89%**
- **Host GPU Thermals**: 42.0°C / 66.8°C peak
- **Operational Discipline**: Zero public issue comments or PR submissions to upstream tracker; staged strictly on local sovereign branch `gcs-f8m`.
