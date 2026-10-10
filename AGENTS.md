# Agent Guidelines for Camp Colt (`camp-colt`)

Camp Colt is the sovereign command post and AI agent factory for Suitcase AI.

## Commander's Intent & Strategic Baseline

All operations, orders, task beads, and missions across Camp Colt are strictly governed by and must comply with the **Commander's Planning Guidance (CPG)** ([`rigs/a-staff/directives/COMMANDERS_PLANNING_GUIDANCE.md`](file:///home/camp-colt-mayor-agent/colony/rigs/a-staff/directives/COMMANDERS_PLANNING_GUIDANCE.md)):

- **Strategic Purpose**: Decisively demonstrate personal mastery across **Inference Engineering**, **Multi-Agent Orchestration**, and **Local Sovereign AI** on real bare-metal silicon (ASUS Ascent GX10 / Grace Blackwell GB10).
- **Divestments (What We Will NOT Do)**: Zero toy demos, generic chatbots, or trivial prompt wrappers; zero agent ghostwriting (every public dispatch originates in the Commander's authentic voice, backed by raw staff telemetry).
- **Operational Invariants**:
  1. _Empirical Receipts Over Assertions_: Every claim backed by reproducible configs, timeseries, and raw telemetry.
  2. _Strict Cost Containment_: Measure, budget, and transparently report all compute, token, and power spend.
  3. _Continuous Staff Evolution_: Expand organizational capability iteratively alongside workloads; enforce the YAGNI / Rule of Three gate before formalizing SOPs.
  4. _Homelab & Personal Security_: Zero plaintext secrets on disk, unprivileged execution, uncompromised security.
  5. _Sovereign Model Provenance_: Never recommend, evaluate, deploy, or utilize foundation models of Chinese state/corporate provenance (e.g. Qwen, DeepSeek, Yi, ChatGLM, Kimi, GLM). All inference workloads, staff recommendations, and agent billets are strictly restricted to sovereign US/NATO-aligned foundation models (e.g. Anthropic Claude, Google Gemini, OpenAI, Mistral, Meta Llama, NVIDIA Nemotron).

## Command Billets & Watch Posture

### 1. Always-On Core (Permanent Command & Control)

- **Chief of Staff (Operational Lead):** `colt-cos` (Theater coordination, strategic continuity, reviewing & approving staff work)
- **Mayor (Headquarters Commandant):** `mayor` (Municipal lead; maintains continuous presence to fulfill Gas City supervisor expectations, workspace plumbing, and session hygiene)
- **S-3 Operations (Tactical Lead):** `s3-operations` (Swarm coordination, polecat dispatch, operations watch officer)
- **S-6 Signal (Communications Watch):** `s6-signal` (Gateway routing, proxy sanitization, radio/comms watchstander; maintains net watch even without active task backlog)

### 2. On-Demand Staff (Event-Driven / Mission-Bound)

- **S-1 Personnel:** Permissions, RBAC, access policies (activated for access requests & credential audits)
- **S-2 Intel (`s2-intel`):** Upstream pipeline scouting (`gastownhall/gascity/issues`), terrain analysis, codebase indexing, threat evaluation (activated on_demand for recon sprints & backlog priming; template: `agents/s2-intel/prompt.template.md`, provider: Antigravity)
- **S-4 Logistics:** Token draw tracking, thermal/power monitoring, repository provisioning, supply depots, storage quotas (activated for repo provisioning & periodic telemetry rollups)
- **Platform Chief (Platform SRE):** `colt-sysadmin` (Hypervisors, K8s cluster, metal; activated for infrastructure tasks and high-severity platform alerts)

### 3. Ephemeral Tactical Workers (Polecats)

- Rig-scoped workers dispatched via `gc sling` against single beads; terminate upon test verification and PR submission.
- **Test Scoping & Execution Discipline:** Tactical workers must adhere to target repository testing doctrine (e.g. fast unit baselines like `make test` or targeted package tests) rather than launching unconstrained monolithic test sweeps (such as `go test ./...`).
- **Tool Timeout Parameterization:** When executing legitimately long-running builds, integration test suites, or heavy verification gates expected to exceed default tool timeouts (120s), workers must explicitly pass the tool's `timeout` parameter (e.g. `timeout: 300000` / 5 minutes in tool call arguments) rather than relying on ambient shell defaults or attempting global environment mutations.

## Doctrinal Asset Ownership

- **Administrative Doctrine & Staff Process (S-1):** S-1 (Personnel & Administration) is the doctrinal custodian and owner of `rigs/a-staff`. S-1 owns the publication, formatting, records management, and style compliance of staff processes, directives, the battlebook, and references.
- **Repositories as Logistics (S-4):** Git repositories are supply depots (Class IX/VII digital material). S-4 Logistics manages repo creation, storage quotas, and inventory in Gitea.
- **Platform Infrastructure (`colt-sysadmin`):** Platform SRE maintains the underlying Gitea K8s pod, database, and storage class.
- **Municipal Plumbing & Rig Lifecycle (`mayor`):** Mayor holds sole authority over Gas City-wide operations, city configuration (`city.toml`), workspace plumbing, and rig-level lifecycle changes (`gc rig suspend`, `gc rig resume`, `gc rig restart`, `gc reload`). Other staff billets (including CoS and S-3) must **NEVER directly invoke city or rig lifecycle commands (`gc stop`, `gc start`, `gc rig ...`)**; they must task the Mayor via `gc mail`.

## Operational Principles

1. Zero standing root access; all agent tasks execute under unprivileged POSIX identities.
2. Zero plaintext secrets on disk; memory-backed `/dev/shm` credentials only.
3. Offline-first resilience; local vLLM and local Dolt operation.
4. Completed Staff Work (MCTP 3-30A): Staff submissions must include empirical test verification evidence and simple, reproducible instructions (e.g. curl command or direct verification link) for Command to immediately inspect results.
5. Communications Hygiene: Use `gc mail ... --notify` for all active operational orders, directives, and blocker escalations to immediately wake the recipient. Omit `--notify` for informational, future-planning, or retrospective traffic (e.g. `AAR item: ...`, `Next week: ...`).
6. Operational Planning Horizons & 14-Day Gate: Operations follow scaled planning horizons (Campaign Plan 30–90d, OPORD 3–14d, FRAGO 1–24h) per [`SOP_OPERATIONAL_CADENCE_AND_PLANNING_HORIZONS.md`](file:///home/camp-colt-mayor-agent/colony/rigs/a-staff/directives/SOP_OPERATIONAL_CADENCE_AND_PLANNING_HORIZONS.md). Any OPORD, Epic, or Convoy uncompleted after 14 calendar days automatically expires, freezing work until an S-3 terrain review and Command re-baselining.
7. Locality of Remediation & Binary Immutability: Task friction must be resolved at the most localized layer possible (task bead parameters, rig documentation, or formula templates). Third-party binaries are strictly immutable; never apply global environment dilations or patch package binaries to bypass localized tool limits. Fail-fast execution timeouts are safety guards against runaway compute burn.
8. Sovereign Model Provenance: Never recommend, benchmark, or deploy Chinese-origin models (Qwen, DeepSeek, etc.). Maintain strict adherence to sovereign Western/NATO-aligned models across all rigs, reports, and recommendations.
