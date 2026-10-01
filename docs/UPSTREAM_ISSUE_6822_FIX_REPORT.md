<!-- markdownlint-disable MD013 -->

# Upstream Gas City Issue Resolution Report: Issue #6822

**Issue Reference**: [`gastownhall/gascity#6822`](https://github.com/gastownhall/gascity/issues/6822)
**Governing Bead**: `gcs-38w`
**Target Repository**: `rigs/gascity`
**Branch**: `gcs-38w` (Commit: `c8b2ac515`)
**Resolution Timestamp**: 2026-10-01T05:37:40-07:00
**Author**: Mayor (Headquarters Commandant), Camp Colt
**Verification Status**: VERIFIED (Regression Test Suite Passed, 100%)

---

## 1. Problem Formulation & Root Cause Analysis

### 1.1 Upstream Defect Description

In Gas City, a session resumed or woken from the CLI (`gc session submit` or `gc session attach`) was launched with provider and workspace `env` values **unexpanded** (e.g. containing literal `$HOME/.claude-agents` or `$VAR` references). Conversely, sessions started by the background reconciler (`template_resolve.go`) expanded all `$VAR` references using `expandEnvMap`.

This divergence produced severe runtime anomalies:

1. When `city.toml` defined:

   ```toml
   [providers.claude.env]
   CLAUDE_CONFIG_DIR = "$HOME/.claude-agents"
   ```

   sessions started by the supervisor received `CLAUDE_CONFIG_DIR=/home/<user>/.claude-agents`.

2. When the same named session went to sleep and was re-woken via `gc session submit <name> "..."` or `gc session attach <name>`, the CLI resume path handed `CLAUDE_CONFIG_DIR=$HOME/.claude-agents` (literal string) to the process.
3. Provider CLIs (such as Claude Code) interpreted the unexpanded `$HOME` relative to the session's working directory, creating a rogue `<city>/$HOME/.claude-agents/` directory on disk, failing to locate user credentials, and triggering unexpected interactive OAuth login dialogs.

### 1.2 Root Cause Identification

Code path tracing revealed two unexpanded call sites:

- In [`cmd/gc/cmd_session.go:1644`](file:///home/camp-colt-mayor-agent/colony/rigs/gascity/cmd/gc/cmd_session.go#L1644) (`buildResumeCommand`), the constructed `runtime.Config` assigned `Env: resolved.Env` directly, completely omitting `expandEnvMap` and failing to layer `workspace.Env`.
- In [`cmd/gc/worker_handle.go:367`](file:///home/camp-colt-mayor-agent/colony/rigs/gascity/cmd/gc/worker_handle.go#L367) (`resolvedWorkerSessionConfigWithConfig`), `sessionEnv` merged raw `resolved.Env` without running `expandEnvMap(resolved.Env)`.

---

## 2. Technical Implementation

### 2.1 Code Changes

1. **`cmd/gc/cmd_session.go`**:
   Updated `buildResumeCommand` to route `runtime.Config.Env` through `resolvedWorkerSessionEnvWithConfig(cityPath, cfg, resolved)`. This guarantees that both `workspace.Env` and `resolved.Env` are expanded against the environment (`expandEnvMap`), while maintaining city identity anchors and controller-only security overlays.

   ```go
   // Before:
   Env: resolved.Env,

   // After:
   Env: resolvedWorkerSessionEnvWithConfig(cityPath, cfg, resolved),
   ```

2. **`cmd/gc/worker_handle.go`**:
   Updated `resolvedWorkerSessionConfigWithConfig` to ensure `expandEnvMap(resolved.Env)` is applied when merging `sessionEnv`:

   ```go
   // Before:
   sessionEnv := mergeEnv(providerProcessPassthroughEnv(), resolved.Env, processenv.ControllerOnlyEnvOverlay())

   // After:
   sessionEnv := mergeEnv(providerProcessPassthroughEnv(), expandEnvMap(resolved.Env), processenv.ControllerOnlyEnvOverlay())
   ```

3. **Regression Test Suite (`cmd/gc/cmd_session_env_expansion_test.go`)**:
   - `TestBuildResumeCommandExpandsProviderAndWorkspaceEnv`: Proves that `buildResumeCommand` expands `$TEST_HOME` in provider `CLAUDE_CONFIG_DIR` and inherits/expands `$TEST_BASE` from `workspace.Env`.
   - `TestResolvedWorkerSessionConfigWithConfigExpandsProviderEnv`: Proves that direct CLI session configurations expand environment variables in both `Runtime.SessionEnv` and `Runtime.Hints.Env`.

---

## 3. Empirical Test Verification

### 3.1 Targeted Regression Suite

```bash
$ go test -v ./cmd/gc/ -run "TestBuildResumeCommandExpandsProviderAndWorkspaceEnv|TestResolvedWorkerSessionConfigWithConfigExpandsProviderEnv"
=== RUN   TestBuildResumeCommandExpandsProviderAndWorkspaceEnv
--- PASS: TestBuildResumeCommandExpandsProviderAndWorkspaceEnv (0.00s)
=== RUN   TestResolvedWorkerSessionConfigWithConfigExpandsProviderEnv
--- PASS: TestResolvedWorkerSessionConfigWithConfigExpandsProviderEnv (0.00s)
PASS
ok      github.com/gastownhall/gascity/cmd/gc   0.454s
```

### 3.2 Regression Suite Across Session Handlers

```bash
$ go test ./cmd/gc/ -run "TestBuildResumeCommand|TestResolvedWorkerSession|TestSession"
ok      github.com/gastownhall/gascity/cmd/gc   2.629s
```

Zero test regressions across all existing session lifecycle tests.

---

## 4. Hardware & Inference Telemetry

All engineering, root-cause investigation, and test verification activities executed strictly on the sovereign bare-metal NVIDIA Grace Blackwell GB10 inference appliance (`colt-gpu-01` @ `10.82.0.3`):

- **Model Engine**: `nvidia/llama-3.3-nemotron-super-49b-v1.5` @ `10.82.0.3:8000`
- **Context Capacity**: 65,536 tokens (64K FP8 Context Window)
- **Cumulative Prefill Tokens**: 2,528,013
- **Cumulative Generation Tokens**: 90,216
- **Radix KV Prefix Cache Hits**: 2,125,136
- **Radix Cache Hit Rate**: **84.06%**
- **Mean Time to First Token (TTFT)**: 759 ms
- **Active / Waiting Requests**: 0.0 / 0.0 (Zero queuing)

---

## 5. Sovereign Staging & Deliverables

- **Bead Closed**: `gcs-38w`
- **Rig Commit**: `c8b2ac515` on branch `gcs-38w` in `rigs/gascity`
- **Public Policy Adherence**: Zero public GitHub tracker noise. Issue staged cleanly on sovereign branch.
