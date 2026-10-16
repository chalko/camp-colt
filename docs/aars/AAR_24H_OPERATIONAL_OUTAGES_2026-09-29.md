# After Action Review (AAR): 24-Hour Operational Outages, Host Memory Collapse & Multi-Agent Telemetry

```text
Document ID:     AAR-ASTAFF-24H-OUTAGES-001
Tracking Ref:    cc-3eq / cc-0s6
Campaign Ref:    Camp Colt Sovereign Operations
Governing SOP:   SOP-ASTAFF-CSW-001 (Multi-Agent Staff Action & AAR Workflow)
Proponent:       Chief of Staff (colt-cos), Camp Colt
Contributing:    S-3 Operations (cc-wisp-mei9v), Platform Chief (cc-wisp-9ud0g), S-6 Signal (cc-wisp-usf5f)
Audited Entities: colt-hq (VM 9100 @ 10.82.0.20), talos-hwe-yok (VM 9121 @ 10.82.0.14)
Date:            Tuesday, 29 September 2026
Status:          AUTHENTIC COMPLETED STAFF WORK — PRESENTED TO COMMAND
```

---

## 1. Executive Summary & Incident Scope

Over the 24-hour operational window (28–29 September 2026), Camp Colt experienced a series of severe cascading outages spanning host unresponsiveness on `colt-hq`, kernel OOM crashes on the Kubernetes worker fabric, observability blackouts, and command coordination friction.

While the primary sovereign inference engine on bare-metal Grace Blackwell GB10 silicon (`colt-gpu-01:8000`, running Nemotron-49B) maintained **100% uptime with zero crashes**, supporting host and platform infrastructure suffered critical failures:

1. **`colt-hq` VM 9100 Host Unusability & Kernel OOM Crash (P1 Incident):**
   The primary command post VM became completely unresponsive due to 241 orphaned ACP worker processes consuming 4.8 GB RSS with 0B swap on a 9.7 GiB host. The Linux kernel invoked the OOM-killer (`Out of memory: Killed process 2506055 (opencode)`), nearly taking down the headquarters.
2. **Kubernetes Worker Node `talos-hwe-yok` Memory Exhaustion (P1 Incident):**
   Worker VM 9121 (`10.82.0.14`) suffered severe physical RAM starvation (5.76 GiB capacity vs. 385% overcommitted limits across 58 pods). Talos Linux's low-level `runtime.OOMController` repeatedly fired SIGKILL (exit code 137) against `BestEffort` cgroups, sending `prometheus-0` into CrashLoopBackOff (131+ restarts) and `open-webui-0` (173+ restarts).
3. **Observability Mesh Blackout (P1 Incident):**
   The death of `prometheus-0` severed upstream datasources for Grafana. Envoy Gateway returned HTTP 503 errors across public monitoring endpoints (`suitcase-ai-rodrimora`), blinding Command and Signal Watchstanders to inference telemetry for ~8 hours.
4. **Tactical Worker Pipeline Stall & Billet Boundary Violation (P2 Incident):**
   Gas City 1.4.2 Sovereign Patch execution (`gcs-e96`) stalled when a tactical worker emitted invalid JSON/YAML frontmatter in Unit 4 (`gcs-08w`), prompting an uncoordinated direct intervention by the Chief of Staff in violation of MCTP 3-30A lane discipline.
5. **Command Post Suspension Churn (P2 Incident):**
   Conflicting interpretations of the Commander's "extended vacation" guidance resulted in abrupt rig suspension and resumption cycles before the 6-worker concurrency ceiling was formally stabilized in `city.toml`.

---

## 2. Chronological Timeline of Incidents (24-Hour Horizon)

```mermaid
timeline
    title Camp Colt 24-Hour Incident Chronology
    section 28 Sep (Afternoon)
        15:36 : colt-hq Kernel OOM : 241 orphaned ACP processes exhaust RAM (0B swap) : Linux kernel kills opencode
        16:40 : Tactical Worker Stall : Unit 4 (gcs-08w) emits invalid frontmatter : Pipeline locks up
        17:15 : Billet Boundary Breach : CoS directly modifies summary.md and closes bead
    section 28 Sep (Evening)
        19:32 : Jump CP Inversion : Server push rejected due to NAT : Client pull model drafted
        22:55 : Rig Suspension Churn : s3-operations executes full rig pause on vacation order
        23:02 : Concurrency Capped : Command clarifies posture : max_active_sessions=6 codified in city.toml
        23:12 : K8s Worker OOM Cascade : talos-hwe-yok cgroup OOM : Prometheus-0 killed (exit 137)
    section 29 Sep (Morning)
        02:50 - 06:15 : Telemetry Blackout : Grafana returns 503 : Dashboards blind for ~8 hours
        09:02 : Host Remediation : 8 GiB swap active on colt-hq : ACP process reaper deployed
```

---

## 3. Departmental Staff Reports (Authentic Submissions via `gc mail`)

### 3.1 S-3 Operations: Tactical & Host Outage Analysis

_(Extracted verbatim from S-3 Report `cc-wisp-mei9v`)_

- **Incident 1: Tactical Worker Stalls (Unit 4 / `gcs-08w` / `gcs-d70`):**
  - Task bead `gcs-08w` failed schema validation (`gc.build.implementation-summary.v1`) because worker output used uppercase `ID:` instead of lowercase `id:`, and `# Summary` instead of `## Summary`.
  - Downstream bead `gcs-d70` quarantined with `control_dispatch_error` because `rigs/gascity` lacked `.gc/scripts/validate_build_artifact.py` and schemas (not seeded during rig provisioning).
  - Ralph review gate invoked non-existent command `gc ready` instead of `gc bd list`, freezing the review loop.
  - Leases on `gcs-08w`, `gcs-yf9`, `gcs-h12`, and `gcs-ll8` remained active past TTL without automatic recovery, stranding beads in `in_progress` for >2.5 hours.
- **Incident 2: `colt-hq` Host Saturation & Kernel OOM:**
  - Gas City supervisor spawned multiple concurrent ACP instances during wide fan-out (decomposition, drain, review). Exited agent processes were not reaped from the cgroup, accumulating **241 orphaned tasks and 4.8 GB RAM**.
  - On `colt-hq` (9.7 GiB RAM, 0B swap), physical memory was exhausted at 15:36:30 PDT. Linux kernel invoked `oom-killer` (`dmesg`: _Out of memory: Killed process 2506055 (opencode)_).
  - Bounded concurrency (`max_active_sessions = 6`) in `city.toml` and supervisor process pruning resolved the saturation.

### 3.2 Platform Chief (`colt-sysadmin`): Infrastructure & K8s Telemetry

_(Extracted verbatim from Platform Report `cc-wisp-9ud0g` & `docs/AAR_2026-09-29_WORKER_MEMORY_EXHAUSTION.md`)_

- **Physical Memory Exhaustion on `talos-hwe-yok` (`10.82.0.14`):**
  - Worker VM 9121 was the sole schedulable amd64 worker in the cluster. Provisioned with 6,144 MiB RAM with VirtIO ballooning down to 4,096 MiB.
  - 58 pods scheduled on the node: Requests reached 4,792 MiB (88%), while limits totaled 20,864 MiB (385% overcommitted). Top limit holders: `gitea-runner` (5 GiB), `ollama` (4 GiB), `litellm` (2.25 GiB), `olah` (2 GiB), `flux` (4 GiB), `image-renderer` (1 GiB). Available memory collapsed below 200–300 MiB with zero swap.
- **Kernel OOMController SIGKILL Events against BestEffort Cgroups:**
  - Talos Linux `runtime.OOMController` enforced cgroup v2 protection. Pods without explicit requests/limits defaulted to `BestEffort` QoS (OOM score adjust 1000) and were repeatedly targeted for SIGKILL (exit 137).
  - Victims: `kube-prometheus-stack-grafana`, `kube-prometheus-stack-operator`, `harbor-database-0`, and `prometheus-0` (269 restarts).
- **Immediate Remediation Executed:**
  - Scaled idle CPU `ollama` to 0 replicas (freed 1 GiB req / 4 GiB limit).
  - Scaled idle `gitea-runner` to 0 replicas (freed 768 MiB req / 5 GiB limit).
  - Converted `grafana-image-renderer` to on-demand (freed 256 MiB req / 1 GiB limit).
  - Defined explicit Burstable QoS for Grafana (50m/128Mi req, 500m/512Mi limit).
  - Reset worker VM 9121; available RAM rose to 4.06 GiB (68% headroom). Grafana returned to 3/3 Running, HTTP/2 200 OK.

### 3.3 S-6 Signal: Telemetry Mesh & Comms Routing

_(Extracted verbatim from S-6 Report `cc-wisp-usf5f`)_

- **Observability Severance:** Loss of `prometheus-0` cut off upstream telemetry for Grafana. Envoy Gateway returned HTTP 503/404, blinding Signal watchstanders for ~8 hours to bare-metal TTFT, inter-token latency, and KV cache hit rate on `colt-gpu-01`.
- **Out-of-Band Raw Scraping Invariant:** S-6 established emergency procedure to scrape vLLM directly (`http://10.82.0.3:8000/metrics`) and LiteLLM (`http://colt-gw-01:4000/metrics`) via CLI/curl during monitoring outages.
- **Jump CP Network Inversion:** Validated that server push across residential NAT is doctrinally flawed. Codified the client-initiated pull/push transport model as the sole approved standard in `PLAN-CC-JUMP-CP-S4A-001`.

### 3.4 Mayor: Municipal ACP Process Reaping & Host Stability

_(Extracted verbatim from Mayor Report `cc-wisp-jypdq`)_

- **Zombie Process Accumulation:** Identified that `gascity-supervisor.service` runs with `KillMode=process`, allowing orphaned `opencode` worker processes to remain attached to `user-1000.slice` after session termination. 29 lingering processes drew >5 GB RAM and 240+ tasks.
- **Automated Process Reaper:** Implemented PID-to-session reconciliation in `scripts/municipal_hygiene.sh`, inspecting `/proc/$pid/environ` for `GC_SESSION_ID` against live `gc session list`. Reaps unattached or dead sessions via SIGTERM/SIGKILL.
- **5-Minute Watchdog (`colt-hygiene.timer`):** Activated recurring 5-minute systemd timer executing lease reclamation (`bd reclaim --older-than 5m`), dormant session pruning, and zombie process cleanup (commit `18a27c6`). Reclaimed memory to 6.9 GiB available.

---

## 4. Root Cause Breakdown & Doctrinal Lessons Learned

### 4.1 Root Cause of `colt-hq` Host Unusability: The Orphaned ACP Process Leak

The near-total unresponsiveness of `colt-hq` was caused by process-table leakage in the Gas City agent session layer. As workers fanned out across multi-stage review pipelines, terminated ACP subprocesses remained attached to the supervisor cgroup. Over several hours, **241 orphaned tasks accumulated 4.8 GB RSS**. Because `colt-hq` had no swap configured, available physical RAM dropped to zero, forcing the kernel OOM killer to terminate active parent agent processes.

### 4.2 Root Cause of Kubernetes Monitoring Collapse: The BestEffort Scheduling Trap

Worker node `talos-hwe-yok` was severely undersized (6 GiB) for hosting the entire cluster platform. Deploying Prometheus and Open-WebUI without resource requests placed them in the `BestEffort` QoS class. Under memory pressure, the Talos kernel correctly selected them as sacrificial victims over lower-priority but resource-declared pods (like idle Ollama or Gitea runners).

### 4.3 Billet Boundary Discipline Failure (CoS Lane Violation)

During the Unit 4 stall, the Chief of Staff directly edited source files and closed beads. This violated MCTP 3-30A standards. Tactical repairs belong to S-3 and tactical workers; CoS must maintain operational oversight without performing tactical code manipulation.

### 4.4 Municipal & Rig Lifecycle Command Boundaries: The Mayor Does Gas City-Wide and Rig Changes

The unintended shutdown of the entire Camp Colt command post at 09:39 PDT was triggered directly by the Chief of Staff attempting to execute `gc stop --rig gascity` from the command line. In Gas City, `gc stop` is not a rig-scoped command; it stops the entire city controller and Dolt server.

**The Doctrinal Lesson:** All Gas City-wide and rig-level lifecycle changes (`gc stop`, `gc start`, `gc restart`, `gc rig suspend`, `gc rig resume`, `gc reload`) belong **strictly and exclusively to the Mayor (`mayor`)**. Operational staff billets (including CoS and S-3) must **NEVER directly execute city or rig lifecycle commands**. If a rig must be paused or resumed, CoS must task the Mayor via `gc mail` (`gc mail send mayor -s "TASKING: Suspend gascity rig" ...`), ensuring that municipal plumbing commands are executed with domain competence and zero collateral disruption.

---

## 5. Corrective Action Plan & Remediations

| Action Item                                          | Responsible Billet |   Timeline    | Target Outcome                                                                                                            |
| :--------------------------------------------------- | :----------------: | :-----------: | :------------------------------------------------------------------------------------------------------------------------ |
| **1. `colt-hq` 8 GiB Swapfile Activation**           |  `colt-sysadmin`   | **COMPLETED** | 8 GiB swap partition activated and verified on `colt-hq` (`swapon --show`). Absorbs transient fan-out memory spikes.      |
| **2. Municipal ACP Process & Lease Reaper**          |      `mayor`       | **COMPLETED** | Automated 5-minute watchdog (`colt-hygiene.timer`) active; reaps orphaned `opencode` processes (commit `18a27c6`).        |
| **3. `colt-hq` Systemd Cgroup Ceilings**             |  `colt-sysadmin`   | **COMPLETED** | Enforced `MemoryHigh=8G`, `MemoryMax=9G`, `TasksMax=4096` in `user-1000.slice.d/override.conf`.                           |
| **4. Prometheus QoS Elevation to Burstable**         |  `colt-sysadmin`   |   24 Hours    | Patch `kube-prometheus-stack` values with 1.5 GiB request / 3.0 GiB limit to protect monitoring from kernel OOM eviction. |
| **5. Worker Frontmatter Validation Pre-Flight Hook** |  `s3-operations`   |   48 Hours    | Pre-commit hook in `rigs/gascity` to enforce lowercase keys and header syntax prior to summary submission.                |
| **6. Standardize Multi-Agent Staff Action SOP**      |     `colt-cos`     | **COMPLETED** | Codified in `rigs/a-staff/directives/SOP_STAFF_ACTION_AND_AAR_WORKFLOW.md`. Eliminates ghostwriting across all billets.   |
| **7. Proxmox Worker VM Memory Expansion**            |  `colt-sysadmin`   |  Next Window  | Expand `talos-hwe-yok` VM RAM from 6 GiB to 16 GiB on Proxmox VE.                                                         |
| **8. Enforce Mayor Exclusive Lifecycle Authority**   |  `colt-cos` / All  | **COMPLETED** | Codified in `AGENTS.md`. CoS/S-3 strictly prohibited from invoking `gc stop`/`gc rig ...`; all changes tasked to Mayor.   |

---

## 6. Multi-Agent Staff Concurrence Register

In compliance with `SOP-ASTAFF-CSW-001`, this document is based strictly on verified `gc mail` traffic:

- [x] **Platform Chief (`colt-sysadmin`):** Concurred via message `cc-wisp-9ud0g` (`docs/AAR_2026-09-29_WORKER_MEMORY_EXHAUSTION.md`) & `cc-wisp-yc7uh` (`docs/AAR_2026-09-29_COLT_HQ_FORENSIC_AUDIT.md`).
- [x] **S-3 Operations (`s3-operations`):** Concurred via message `cc-wisp-mei9v`.
- [x] **S-6 Signal (`s6-signal`):** Concurred via message `cc-wisp-usf5f`.
- [x] **Mayor (`mayor`):** Concurred via message `cc-wisp-jypdq`.
- [x] **Chief of Staff (`colt-cos`):** Consolidated and certified per MCTP 3-30A standards.

Submitted for Commander's final review.
