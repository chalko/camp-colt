<!-- markdownlint-disable MD013 -->

# Upstream Gas City Issue Resolution Report: Issue #6866

**Issue Reference**: [`gastownhall/gascity#6866`](https://github.com/gastownhall/gascity/issues/6866)
**Governing Bead**: `gcs-mjt`
**Target Repository**: `rigs/gascity`
**Branch**: `gcs-mjt` (Commit: `8142ddc34`)
**Resolution Timestamp**: 2026-10-01T14:10:35-07:00
**Author**: Mayor (Headquarters Commandant), Camp Colt
**Verification Status**: VERIFIED (Targeted large Go diff regression test and full `scripts/...` test suites passed 100%)

---

## 1. Problem Formulation & Root Cause Analysis

### 1.1 Upstream Defect Description

In `.githooks/pre-push`, lines 47–49 previously determined whether any Go files changed between the pushed commits using a piped shell construct:

```bash
if git diff --name-only "$remote_sha" "$local_sha" -- '*.go' 2>/dev/null | grep -q .; then
  go_changed=1
fi
```

The script begins with `set -euo pipefail`. Under standard POSIX and Linux pipeline semantics, `grep -q .` terminates immediately upon matching the first line of input and closes its standard input file descriptor.

When a push contains a large number of modified Go files (or long file paths exceeding the kernel pipe buffer, typically 64 KiB), `git diff --name-only` attempts to write subsequent lines to the closed pipe. The kernel delivers `SIGPIPE` (signal 13 / exit code 141) to `git diff`.

Because `pipefail` is enabled, any non-zero exit code within the pipeline causes the entire pipeline to exit with that status (141). Consequently:

1. The `if` conditional evaluates to false (exit status 141 ≠ 0).
2. `go_changed=1` is never executed; `go_changed` remains 0.
3. The hook reaches line 66:

   ```bash
   if [ "$go_changed" -eq 0 ]; then
     exit 0
   fi
   ```

4. The hook exits 0 silently, completely bypassing `make test-fast-parallel` on large Go diffs where comprehensive test verification is most critical.

### 1.2 Root Cause Identification

The root cause was the combination of:

1. Piping `git diff --name-only` directly to `grep -q .` which closes stdin early.
2. `set -euo pipefail` promoting the downstream writer's `SIGPIPE` (141) into a failure status for the compound command.
3. Unnecessary data serialization across a pipe when Git provides a native, pipe-free difference check.

---

## 2. Technical Implementation

### 2.1 Code Changes

#### `.githooks/pre-push`

Replaced the piped diff and grep invocation with Git's built-in quiet exit-code check:

```diff
@@ -44,7 +44,7 @@ while read -r _local_ref local_sha _remote_ref remote_sha; do
     go_changed=1
     continue
   fi
-  if git diff --name-only "$remote_sha" "$local_sha" -- '*.go' 2>/dev/null | grep -q .; then
+  if ! git diff --quiet "$remote_sha" "$local_sha" -- '*.go' 2>/dev/null; then
     go_changed=1
   fi
 done < <(replay_refs)
```

**Key Advantages**:

- **Pipe-free**: Eliminates pipes completely; no subshell or inter-process communication buffer is used, eradicating `SIGPIPE` under `pipefail`.
- **O(1) Execution**: `git diff --quiet` stops scanning as soon as the first difference is encountered.
- **Fail-Closed Behavior**: If differences exist, `git diff --quiet` exits 1, making `! git diff --quiet ...` evaluate to true (0). If an error occurs (e.g., exit 128), it also evaluates to true, running the test suite safely rather than failing open.

### 2.2 Regression Test Suite

#### `scripts/githooks_pre_push_stdin_test.go`

Added a reproduction test `TestPrePushRunsSuiteOnLargeGoDiff`:

- Generates 2,000 modified Go files with lengthy filenames (>110 KiB of path data, easily exceeding the 64 KiB Linux pipe buffer).
- Simulates a push containing the large commit against an older base.
- Verifies that `pre-push` executes successfully and invokes `make test-fast-parallel`.
- Confirmed failure on the unpatched script: `githooks_pre_push_stdin_test.go:249: push-time suite not reached on large Go diff (make invocations = "")` with exit code 1.
- Confirmed clean pass on the patched script: `ok github.com/gastownhall/gascity/scripts 0.424s`.

---

## 3. Empirical Test Verification

### 3.1 Targeted Test Execution

```bash
go test -v ./scripts -run TestPrePush
```

Output:

```
=== RUN   TestPrePushReplaysRefListToBeadsAndSuiteScan
--- PASS: TestPrePushReplaysRefListToBeadsAndSuiteScan (0.08s)
=== RUN   TestPrePushSkipsSuiteForBranchDeletion
--- PASS: TestPrePushSkipsSuiteForBranchDeletion (0.10s)
=== RUN   TestPrePushHandlesEmptyRefList
--- PASS: TestPrePushHandlesEmptyRefList (0.09s)
=== RUN   TestPrePushPropagatesBeadsRejection
--- PASS: TestPrePushPropagatesBeadsRejection (0.09s)
=== RUN   TestPrePushRunsSuiteOnLargeGoDiff
--- PASS: TestPrePushRunsSuiteOnLargeGoDiff (0.26s)
=== RUN   TestPrePushUsesCanonicalMachineAwareConcurrency
--- PASS: TestPrePushUsesCanonicalMachineAwareConcurrency (0.00s)
PASS
ok   github.com/gastownhall/gascity/scripts 0.627s
```

### 3.2 Full Scripts & Push-Ownership-Guard Test Execution

1. `bash scripts/test-push-ownership-guard.sh`:

   ```
   pass=39 fail=0
   ```

2. `go test ./scripts/...`:

   ```
   ok   github.com/gastownhall/gascity/scripts 66.660s
   ok   github.com/gastownhall/gascity/scripts/cipolicy 0.247s
   ok   github.com/gastownhall/gascity/scripts/prwatchdog 0.005s
   ```

---

## 4. Hardware Telemetry & Resource Accounting

- **Silicon Substrate**: ASUS Ascent GX10 (NVIDIA Grace Blackwell GB10 @ `10.82.0.3:8000`)
- **Model Ingested**: `nvidia/llama-3.3-nemotron-super-49b-v1.5`
- **Total Prompt Tokens**: 2,532,469
- **Prompt Cache Hits**: 2,128,368 tokens (**84.04% Radix prefix cache hit rate**)
- **Local Compute Prefill**: 404,101 tokens
- **Total Generation Tokens**: 93,448 tokens
- **Requests Serviced**: 1,094 turns
- **Mean Time to First Token (TTFT)**: 662 ms
- **Cloud API Leakage**: 0 calls (100% sovereign bare-metal inference)

---

## 5. Artifact Audit & Commit Topology

- **Tracking Bead**: [`gcs-mjt`](file:///home/camp-colt-mayor-agent/colony/rigs/gascity) (Closed)
- **Patch Commit**: `8142ddc34` (`fix(hooks): avoid SIGPIPE under pipefail in pre-push on large diffs`)
- **Staging Branch**: `gcs-mjt`
- **Public Upstream Interaction**: Zero public comments or issues opened on GitHub (100% sovereign maintenance branch).
