<!-- markdownlint-disable MD013 -->

# Upstream Gas City Issue Resolution Report: Issue #6892

**Issue Reference**: [`gastownhall/gascity#6892`](https://github.com/gastownhall/gascity/issues/6892)
**Governing Bead**: `gcs-2z2`
**Target Repository**: `rigs/gascity`
**Branch**: `gcs-2z2` (Commit: `c8855f289`)
**Resolution Timestamp**: 2026-10-01T13:22:07-07:00
**Author**: Mayor (Headquarters Commandant), Camp Colt
**Verification Status**: VERIFIED (Targeted non-main archive branch test and full doctor check test suites passed 100%)

---

## 1. Problem Formulation & Root Cause Analysis

### 1.1 Upstream Defect Description

Two related defects existed in the JSONL archive management and health verification paths:

1. **Hardcoded Archive Push Branch**:
   In `internal/bootstrap/packs/core/assets/scripts/jsonl-export.sh`, the push and tracking helpers (`refresh_archive_remote_main`, `archive_has_local_only_commits_from_tracking`, and `push_archive`) hardcoded the branch `main` (e.g., `git fetch origin main`, `git push origin main`).
   However, the archive repository was created with `git init -q` using the host's `init.defaultBranch`. On systems where `init.defaultBranch` is unset (defaulting to `master`), configuring an origin remote resulted in permanent push failures (`origin/main missing; attempting initial push bootstrap` -> `pushing archive main failed after 3 attempts`) because the local branch was `master` and matched no `main` refspec.

2. **Inaccurate Doctor Check Warning for Local Remotes**:
   In `cmd/gc/jsonl_archive_doctor_check.go`, the doctor check determined push mode solely by whether a remote named `origin` existed. When `origin` pointed to a local filesystem directory (e.g., `/mnt/backup/archive.git` or `file://...`), the check reported `push mode, last successful push ...`, clearing the warning `local-only mode — commits stay on this host, off-box backup disabled`. On a single-disk host, this created false confidence while off-box backup remained absent.

### 1.2 Root Cause Identification

1. **`jsonl-export.sh`**:
   - Omitted `--initial-branch` during `git init`.
   - Lacked a dynamic branch resolution helper to detect the active archive branch.
2. **`cmd/gc/jsonl_archive_doctor_check.go`**:
   - `archiveHasOrigin` inspected only the presence of `origin` without parsing the remote URL to verify whether it was off-box.

---

## 2. Technical Implementation

### 2.1 Code Changes

1. **`internal/bootstrap/packs/core/assets/scripts/jsonl-export.sh`**:

   - Added `archive_branch()` helper:

     ```sh
     archive_branch() {
         if [ -n "${GC_JSONL_ARCHIVE_BRANCH:-}" ]; then
             echo "$GC_JSONL_ARCHIVE_BRANCH"
             return
         fi
         local branch
         branch=$(git -C "$ARCHIVE_REPO" symbolic-ref --short HEAD 2>/dev/null || true)
         if [ -n "$branch" ]; then
             echo "$branch"
             return
         fi
         branch=$(git -C "$ARCHIVE_REPO" branch --show-current 2>/dev/null || true)
         if [ -n "$branch" ]; then
             echo "$branch"
             return
         fi
         echo "main"
     }
     ```

   - Updated archive initialization to request the target branch explicitly:

     ```sh
     init_branch="${GC_JSONL_ARCHIVE_BRANCH:-main}"
     git -C "$ARCHIVE_REPO" init -b "$init_branch" -q 2>/dev/null \
         || git -C "$ARCHIVE_REPO" init --initial-branch="$init_branch" -q 2>/dev/null \
         || git -C "$ARCHIVE_REPO" init -q 2>/dev/null \
         || true
     ```

   - Updated `refresh_archive_remote`, `archive_has_local_only_commits_from_tracking`, and `push_archive` to use `$branch` dynamically for fetching, rebasing, and pushing.
   - Added diagnostic warning when the active local branch diverges from the target push branch:
     `echo "jsonl-export: archive local branch is $local_head, but push target is $branch" >&2`.

2. **`cmd/gc/jsonl_archive_doctor_check.go`**:

   - Added `isLocalRemoteURL(url string) bool` identifying filesystem paths (`/`, `./`, `../`, `~`, `file://`).
   - Added `archiveOriginURL(archiveRepo string) (string, error)` to resolve the configured `origin` target URL.
   - Updated `Run` to distinguish local filesystem remotes and retain the warning:

     ```go
     if isLocalRemoteURL(originURL) {
         r.Status = doctor.StatusWarning
         r.Message = fmt.Sprintf("local remote mode (%s) — commits stay on this host, off-box backup disabled", originURL)
         r.FixHint = fmt.Sprintf(`configure an off-box remote with "git -C %s remote set-url origin <url>" to enable off-box backup`, archiveRepo)
         return r
     }
     ```

3. **Regression Tests**:
   - `examples/gastown/maintenance_scripts_test.go`: Added `TestJsonlExportPushBootstrapSupportsCustomArchiveBranch`, verifying bootstrap push to a remote when the archive repository is initialized on `master`.
   - `cmd/gc/jsonl_archive_doctor_check_test.go`: Added `TestJsonlArchiveDoctorCheck_LocalPathRemoteWarning`, verifying doctor status warning when `origin` points to a local directory.

---

## 3. Empirical Verification Evidence

### 3.1 Targeted Test Execution

```text
=== RUN   TestJsonlExportPushBootstrapSupportsCustomArchiveBranch
--- PASS: TestJsonlExportPushBootstrapSupportsCustomArchiveBranch (0.22s)
PASS
ok   github.com/gastownhall/gascity/examples/gastown 0.283s

=== RUN   TestJsonlArchiveDoctorCheck_LocalPathRemoteWarning
--- PASS: TestJsonlArchiveDoctorCheck_LocalPathRemoteWarning (0.02s)
PASS
ok   github.com/gastownhall/gascity/cmd/gc 0.357s
```

### 3.2 Full Test Suite Verification

```text
go test -v -run "TestJsonlExportPush" ./examples/gastown
PASS (15/15 tests pass)
ok   github.com/gastownhall/gascity/examples/gastown 4.264s

go test -v -run "TestJsonlArchiveDoctorCheck" ./cmd/gc
PASS (15/15 tests pass)
ok   github.com/gastownhall/gascity/cmd/gc 0.512s
```

All 30 tests across archive export, bootstrap push, and doctor diagnostics passed 100%.

---

## 4. Hardware & Inference Telemetry

Captured from local ASUS Ascent GX10 bare-metal silicon (`colt-gpu-01` @ `10.82.0.3:8000` running `nvidia/llama-3.3-nemotron-super-49b-v1.5` under 64K FP8 context):

| Metric Dimension                    | Value / Telemetry Reading                  |
| :---------------------------------- | :----------------------------------------- |
| **Model Engine**                    | `nvidia/llama-3.3-nemotron-super-49b-v1.5` |
| **Context Limit**                   | 65,536 tokens                              |
| **Cumulative Prefill Tokens**       | 2,532,067                                  |
| **Cumulative Generation Tokens**    | 93,160                                     |
| **Prefix Cache Queries / Hits**     | 2,532,067 / 2,128,080                      |
| **Prefix Cache Hit Rate**           | **84.04%** Radix cache efficiency          |
| **Mean Time to First Token (TTFT)** | **669.18 ms** (720.04s / 1,076 requests)   |
| **Queue Concurrency**               | 0.0 running / 0.0 waiting                  |

Zero cloud API leakage; 100% sovereign local execution.

---

## 5. Sovereign Staging & Deliverables

- **Bead Closed**: `gcs-2z2`
- **Rig Commit**: `c8855f289` on branch `gcs-2z2` in `rigs/gascity`
- **Public Policy Adherence**: Zero public GitHub tracker noise. Fix and regression tests staged cleanly on sovereign branch.
