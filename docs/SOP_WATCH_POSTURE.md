# Standard Operating Procedure: Command Post Watch Posture & Staff Battle Rhythm

**Document ID:** `SOP-0.2-WATCH-POSTURE`  
**Effective Date:** September 22, 2026  
**Authority:** Chief of Staff (`colt-cos`), Camp Colt  
**Target Environment:** Sovereign Command Post (`colt-hq`, `10.82.0.20`) & Gas City Colony  

---

## 1. Purpose & Scope

This Standard Operating Procedure (SOP) codifies the watch posture, operational billets, resource management, and completion standards for autonomous agent operations within Camp Colt. It establishes clear boundaries between permanent command watchstanders, on-demand functional specialists, and ephemeral execution workers.

---

## 2. Watch Posture Tiers

To preserve host memory (targeting the 4.5 GB baseline for `colt-hq`), prevent context degradation, and eliminate idle chatter, agent sessions are strictly tiered:

```
┌─────────────────────────────────────────────────────────────────┐
│                    TIER 1: ALWAYS-ON CORE                       │
│  • Chief of Staff (cos)        • S-3 Operations (s3-operations) │
│  • Mayor (mayor)               • S-6 Signal (s6-signal)         │
└────────────────────────────────┬────────────────────────────────┘
                                 │ Activates on Demand
┌────────────────────────────────┴────────────────────────────────┐
│               TIER 2: ON-DEMAND FUNCTIONAL STAFF                │
│  • Platform SRE (colt-sysadmin)• S-4 Logistics (s4-logistics)   │
│  • S-2 Intelligence (s-2)      • S-1 Personnel (s-1)            │
└────────────────────────────────┬────────────────────────────────┘
                                 │ Dispatches via 'gc sling'
┌────────────────────────────────┴────────────────────────────────┐
│             TIER 3: EPHEMERAL TACTICAL POLECATS                 │
│  • Rig-scoped code workers (single-bead lifecycle)              │
└─────────────────────────────────────────────────────────────────┘
```

### Tier 1: Always-On Core (Permanent Command & Control)

1. **Chief of Staff (`cos`):**
   * **Doctrinal Role:** Operational Lead & Theater Liaison.
   * **Cognizance:** Direct interface with the Commander and Strategic Theater Director (Peggy). Maintains strategic continuity across shifts, prioritizes operational epics, enforces doctrine, and reviews/approves completed staff work.
   * **Watch State:** Continuous presence.

2. **Mayor (`mayor`):**
   * **Doctrinal Role:** Headquarters Commandant (H&S Company Commander) & Municipal Supervisor.
   * **Cognizance:** Maintains the Gas City town root, session scaffolding, `city.toml` configurations, workspace health (`gc doctor`), and Dolt store hygiene.
   * **Watch State:** Continuous presence to fulfill Gas City supervisor requirements and platform stability. Does *not* perform operational planning or tactical dispatch.

3. **S-3 Operations (`s3-operations`):**
   * **Doctrinal Role:** Tactical Lead & Combat Operations Center (COC) Watch Officer.
   * **Cognizance:** Translates operational directives into rig-scoped task beads (`sa-*`, `gtr-*`, `cc-*`), manages the virtual COC, monitors worker progress, clears blockers, and sequences ongoing tasks.
   * **Watch State:** Continuous presence. Primary operational engine driving execution.

4. **S-6 Signal (`s6-signal`):**
   * **Doctrinal Role:** Communications & Gateway Watchstander.
   * **Cognizance:** Monitors message broker transit, gateway health, proxy sanitization, TLS/PKI certificates, and security events.
   * **Watch State:** Continuous radio/signal watch. Remains on watch even during tactical quiet periods without active task backlog.

---

### Tier 2: On-Demand Staff (Event-Driven / Mission-Bound)

Tier 2 staff sessions do not sit in permanent hot loops. They are awakened or scheduled as needed:

| Billet | Role | Activation Trigger | Deactivation Condition |
| :--- | :--- | :--- | :--- |
| **Platform SRE (`colt-sysadmin`)** | Infrastructure Engineer | Infrastructure task bead (e.g. `cc-56d.1` VM provisioning) or P0 system alert. | Manifests applied, tests green, PR merged. |
| **S-4 Logistics (`s4-logistics`)** | Quartermaster & Supply | Requisition for new repository (`colt/*`), quota adjustment, or scheduled daily telemetry rollup. | Repository provisioned, quota set, or SITREP submitted. |
| **S-2 Intelligence (`s-2`)** | Reconnaissance & Intel | S-3 order for codebase indexing, dependency audit, or threat analysis sprint. | Architectural dossier / intel report published. |
| **S-1 Personnel (`s-1`)** | Administrative & RBAC | Access request, agent key rotation, or permission audit. | RBAC updated and credential audit complete. |

---

### Tier 3: Ephemeral Tactical Workers (Polecats)

- Dispatched strictly via `gc sling <agent> <bead-id>` against a defined scope.
- Lifecycle: `Init` $\rightarrow$ `Verify Preconditions` $\rightarrow$ `Execute Changes` $\rightarrow$ `Run Empirical Tests` $\rightarrow$ `Submit PR` $\rightarrow$ `Exit`.
- Workers must never remain lingering in idle state once their assigned task bead is complete.

---

## 3. Doctrinal Division of Asset Ownership

To avoid friction between platform administration and municipal operations:

1. **Git Repositories are Logistics Assets (S-4):**
   - Repositories are virtual supply depots (Class IX/VII digital material).
   - `s4-logistics` holds scoped Gitea API credentials (`repo:*`, `org:read`) to provision new repositories, manage quotas, configure upstream mirrors, and set branch protections.
2. **Platform Infrastructure is SRE Cognizance (`colt-sysadmin`):**
   - Platform SRE maintains the physical/hypervisor nodes, Kubernetes pods, Gitea database storage classes, and system daemon health.
3. **Municipal Workspaces are Mayor Cognizance (`mayor`):**
   - The Mayor receives repository coordinates from S-4, performs the local clone into the town root, updates `city.toml`, and validates workspace health via `gc doctor`.

---

## 4. Completed Staff Work Standard (MCTP 3-30A)

All staff officers and specialists must submit completed work meeting the following three criteria:
1. **Empirical Evidence:** Submission must include verifiable test metrics (latencies, exit codes, throughput, or telemetry files) proving the solution works under physical execution—not merely that a configuration file was written.
2. **Immediate Verification Instruction:** Submission must provide an unambiguous, simple command (e.g. `curl -f http://...` or specific CLI check) that Command can execute immediately to observe results.
3. **Escalation & Stop Threshold:** If immediate results cannot be verified or a blocker arises, the task must be kicked back to S-3 with an explanation rather than dragging the command element into deep low-level debugging. 
---

## 5. Communications & Notification Standards (`gc mail`)

To maintain operational tempo while respecting agent context boundaries, all staff members must adhere to the following dispatch standards when sending messages:

1. **Active Operational Mail (Default to `--notify`):**
   * **Rule:** All task orders, directives, urgent queries, blocker escalations, handoffs, and verification requests MUST be sent with `--notify`.
   * **Rationale:** `--notify` actively nudges the recipient session immediately, ensuring the recipient does not stall waiting for a background polling cycle.
   * **Example:** `gc mail send s3-operations -s "ORDER: Deploy VM 9100" -m "..." --notify`

2. **Informational & Deferred Mail (Omit `--notify`):**
   * **Rule:** Non-urgent, retrospective, or future-horizon communications MUST omit `--notify`.
   * **Scope:**
     * After Action Report submissions (`AAR item: ...`)
     * Future planning notes (`Next week: ...`, `FYI: ...`)
     * Routine telemetry dumps or background logs
   * **Rationale:** Prevents unnecessary context interruption for receiving agents who are actively executing tactical tasks. Informational messages will be read naturally during the agent's next idle check or handoff.

---

## 6. Garrison Battle Rhythm & Operational Reviews

To ensure predictive synchronization, eliminate manual worker polling, and maintain command tempo, Camp Colt operates on a strict doctrinal battle rhythm:

### A. Daily Morning Standup / Commander's Update Brief (CUB) — 0600 PDT
* **Doctrinal Authority:** MCTP 3-30A & MCRP 3-10A.1.
* **Staff Data Call (05:15 PDT):** Automated via Gas City order (`orders/morning-cub.toml`). All staff sections compile their 24-hour progress, metrics, and blockers *before 06:00 AM*.
* **Executive Review (06:00 PDT):** Chief of Staff consolidates the CUB so the Commander and staff can review the operational situation and immediately transition into daily decisive actions.

### B. Weekly Task Retrospective & Process Review (AAR) — Fridays NLT 1400 PDT
* **Cadence:** Conducted weekly on Friday afternoons following the lunch window.
* **Delivery Gate:** Staff analysis and watchdog tuning must be completed and presented to Command **No Later Than 14:00 PDT on Fridays**.
* **Analysis Scope:**
  1. **Bead Bottleneck & Dwell-Time Audit:** Systemic review of all closed, stalled, deferred, or remediated beads across rigs (`cc-*`, `cr-*`, `sa-*`, `cu-*`, `as-*`, `gtr-*`) to diagnose worker hold-ups.
  2. **Platform & Tooling Hardening:** Identify and resolve environmental friction (SSHFS behaviors, Gitea credentials, networking, schema parse slips).
  3. **Gas City Watchdog Calibration:** Tune native watchdog timeouts, auto-reclaim rules, and patrol configurations so stuck sessions are automatically recovered without human or supervisor polling.
  4. **Battlebook Codification:** Direct incorporation of hard-learned lessons and runbooks into `rigs/a-staff/battlebook/` and SOPs.
