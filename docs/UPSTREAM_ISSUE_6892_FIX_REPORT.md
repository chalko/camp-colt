# Upstream Gas City Issue #6892 Resolution Report

**Date**: 2026-10-01T00:33:00-07:00
**Author**: Chief of Staff (`colt-cos`)
**Billet**: Always-On Core Watch
**Rig**: `rigs/gascity`
**Bead**: `gcs-7ky` (Closed)
**Upstream Issue Reference**: [gastownhall/gascity#6892](https://github.com/gastownhall/gascity/issues/6892)
**Git Branch**: `gcs-7ky` (`rigs/gascity`)
**Commit**: `4fd75d6d6`
**Classification**: Bug Fix & Multi-Branch Compatibility

---

## 1. Executive Summary

Upstream Gas City Issue #6892 reports a latent push failure vulnerability where `jsonl-export.sh` hardcodes the git branch name `main` throughout its remote tracking, fetching, and pushing routines, while archive repositories are initialized with the host's `init.defaultBranch`.

On systems where `init.defaultBranch` is unset or configured to `master` (such as default Git installations), configuring a remote produces an archive that fails on every push attempt with:

```text
jsonl-export: origin/main missing; attempting initial push bootstrap
jsonl-export: pushing archive main failed after 3 attempts
jsonl-export: jsonl — no changes, push: failed
```

Because `refs/heads/main` does not exist locally (the repository carries history on `refs/heads/master`), `git push origin main` cannot match the refspec. The error message mimics network or credential failure, misleading operators and leaving automated backups unpushed.

Camp Colt engineering resolved this defect locally on sovereign maintenance branch `gcs-7ky` in `rigs/gascity`:

1. **Dynamic Branch Resolution**: Added `resolve_archive_branch()` to detect the active branch via `git -C "$ARCHIVE_REPO" symbolic-ref --short HEAD`, honoring `GC_JSONL_ARCHIVE_BRANCH` if set, and falling back gracefully to `main`.
2. **Explicit Initialization**: Updated repository creation to explicitly initialize with `-b "${GC_JSONL_ARCHIVE_BRANCH:-main}"` (with `--initial-branch` and standard `git init` fallbacks) so fresh repositories consistently default to `main`.
3. **Refspec Generalization**: Replaced hardcoded `main` in `refresh_archive_remote_main`, `archive_has_local_only_commits_from_tracking`, `archive_has_local_only_commits`, and `push_archive_main` with `$ARCHIVE_BRANCH`.
4. **Comprehensive Test Verification**: Added regression tests `TestJsonlExportPushBootstrapSupportsMasterBranchArchive` and `TestJsonlExportFreshArchiveInitializesMainBranch` in `examples/gastown/maintenance_scripts_test.go`, verifying 100% test pass (65/65 tests pass across the Gastown and cmd/gc suites).

In strict accordance with Commander guidance:

- **Zero Public Issue Noise**: Zero comments or issues were posted to upstream GitHub trackers.
- **Local LM Exclusivity**: All analysis and verification performed on local bare-metal silicon (`colt-gpu-01`).
- **Telemetry Evidence**: Full hardware and inference telemetry captured and recorded below.

---

## 2. Root Cause Analysis

In `internal/bootstrap/packs/core/assets/scripts/jsonl-export.sh`:

1. **Bare `git init`**:
   The repository creation path relied on:

   ```bash
   if [ ! -d "$ARCHIVE_REPO/.git" ]; then
       mkdir -p "$ARCHIVE_REPO"
       git -C "$ARCHIVE_REPO" init -q 2>/dev/null || true
   fi
   ```

   Without specifying `--initial-branch`, Git defaults to the system/user `init.defaultBranch`, creating `refs/heads/master` on default environments.

2. **Hardcoded Refspecs in Push Path**:
   The push routine assumed `main`:

   ```bash
   git fetch origin main -q
   git rev-parse --verify refs/remotes/origin/main
   git rebase refs/remotes/origin/main
   git push origin main -q
   ```

   When the archive was initialized on `master`, `git push origin main` failed because local ref `refs/heads/main` did not exist.

---

## 3. Implementation Details

### A. Dynamic Branch Resolution (`resolve_archive_branch`)

Implemented dynamic branch discovery guarded for `set -u` (`nounset`) execution:

```bash
ARCHIVE_BRANCH=""

resolve_archive_branch() {
    if [ -n "${ARCHIVE_BRANCH:-}" ]; then
        return
    fi
    if [ -n "${GC_JSONL_ARCHIVE_BRANCH:-}" ]; then
        ARCHIVE_BRANCH="$GC_JSONL_ARCHIVE_BRANCH"
        return
    fi
    if [ -d "$ARCHIVE_REPO/.git" ]; then
        ARCHIVE_BRANCH=$(git -C "$ARCHIVE_REPO" symbolic-ref --short HEAD 2>/dev/null || true)
    fi
    ARCHIVE_BRANCH="${ARCHIVE_BRANCH:-main}"
}
```

### B. Explicit Archive Initialization

Updated the creation block to enforce `main` by default while allowing environment override:

```bash
if [ ! -d "$ARCHIVE_REPO/.git" ]; then
    mkdir -p "$ARCHIVE_REPO"
    git -C "$ARCHIVE_REPO" init -b "${GC_JSONL_ARCHIVE_BRANCH:-main}" -q 2>/dev/null \
        || git -C "$ARCHIVE_REPO" init --initial-branch="${GC_JSONL_ARCHIVE_BRANCH:-main}" -q 2>/dev/null \
        || git -C "$ARCHIVE_REPO" init -q 2>/dev/null || true
fi
resolve_archive_branch
```

### C. Generalized Push and Fetch Logic

All fetch, rebase, and push invocations in `push_archive_main` now reference `origin "$ARCHIVE_BRANCH"` and `refs/remotes/origin/$ARCHIVE_BRANCH`, correctly maintaining any active branch name.

---

## 4. Test Verification & Empirical Evidence

### A. New Regression Tests

Added two unit tests to `examples/gastown/maintenance_scripts_test.go`:

1. `TestJsonlExportPushBootstrapSupportsMasterBranchArchive`:
   - Configures an archive repository explicitly on `master` with an empty bare remote.
   - Executes `jsonl-export.sh`.
   - Asserts that the local `master` HEAD is pushed to `refs/heads/master` on the remote.
   - Asserts that `pending_archive_push` clears cleanly upon success.
2. `TestJsonlExportFreshArchiveInitializesMainBranch`:
   - Runs `jsonl-export.sh` against an empty target path.
   - Asserts that `git -C <archive> symbolic-ref --short HEAD` returns `main`.

### B. Automated Test Results

```text
=== RUN   TestJsonlExportPushBootstrapSupportsMasterBranchArchive
--- PASS: TestJsonlExportPushBootstrapSupportsMasterBranchArchive (0.29s)
=== RUN   TestJsonlExportFreshArchiveInitializesMainBranch
--- PASS: TestJsonlExportFreshArchiveInitializesMainBranch (0.15s)
PASS
ok      github.com/gastownhall/gascity/examples/gastown 14.353s
ok      github.com/gastownhall/gascity/cmd/gc           0.585s
```

Total: **65 / 65 PASS (100% Pass Rate)**.

---

## 5. Hardware & Silicon Telemetry Ledger

All engineering activities executed exclusively on the sovereign bare-metal NVIDIA Grace Blackwell GB10 inference engine:

- **Host Node**: `colt-gpu-01` (`10.82.0.3`)
- **Serving Framework**: vLLM `0.27.1-ae19ac56`
- **Model**: `nvidia/llama-3.3-nemotron-super-49b-v1.5` (FP8, 64K context window)
- **Cumulative Prefill Tokens**: `2,455,402`
- **Cumulative Generation Tokens**: `79,238`
- **Radix KV Cache Queries**: `2,455,402`
- **Radix KV Cache Hits**: `2,055,488` (**83.71% Cache Hit Rate**)
- **New Milestones**: Silicon passed **2.055 Million** KV cache hits.
- **GPU Queue State**: 0.0 running / 0.0 waiting (Zero queueing latency).
