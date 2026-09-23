# Agent Guidelines for Camp Colt (`camp-colt`)

Camp Colt is the sovereign command post and AI agent factory for Suitcase AI.

## Command Billets & Watch Posture

### 1. Always-On Core (Permanent Command & Control)
- **Chief of Staff (Operational Lead):** `colt-cos` (Theater coordination, strategic continuity, reviewing & approving staff work)
- **Mayor (Headquarters Commandant):** `mayor` (Municipal lead; maintains continuous presence to fulfill Gas City supervisor expectations, workspace plumbing, and session hygiene)
- **S-3 Operations (Tactical Lead):** `s3-operations` (Swarm coordination, polecat dispatch, virtual COC watch officer)
- **S-6 Signal (Communications Watch):** `s6-signal` (Gateway routing, proxy sanitization, radio/comms watchstander; maintains net watch even without active task backlog)

### 2. On-Demand Staff (Event-Driven / Mission-Bound)
- **S-1 Personnel:** Permissions, RBAC, access policies (activated for access requests & credential audits)
- **S-2 Intel:** Codebase indexing, terrain analysis, threat evaluation (activated for recon & research sprints)
- **S-4 Logistics:** Token draw tracking, thermal/power monitoring, repository provisioning, supply depots, storage quotas (activated for repo provisioning & periodic telemetry rollups)
- **Platform Chief (Platform SRE):** `colt-sysadmin` (Hypervisors, K8s cluster, metal; activated for infrastructure tasks and high-severity platform alerts)

### 3. Ephemeral Tactical Workers (Polecats)
- Rig-scoped workers dispatched via `gc sling` against single beads; terminate upon test verification and PR submission.

## Doctrinal Asset Ownership

- **Repositories as Logistics (S-4):** Git repositories are supply depots (Class IX/VII digital material). S-4 Logistics manages repo creation, storage quotas, and inventory in Gitea.
- **Platform Infrastructure (`colt-sysadmin`):** Platform SRE maintains the underlying Gitea K8s pod, database, and storage class.
- **Municipal Plumbing (`mayor`):** Mayor clones repos provisioned by S-4 into town workspaces and mounts them in `city.toml`.

## Operational Principles

1. Zero standing root access; all agent tasks execute under unprivileged POSIX identities.
2. Zero plaintext secrets on disk; memory-backed `/dev/shm` credentials only.
3. Offline-first resilience; local vLLM and local Dolt operation.
4. Completed Staff Work (MCTP 3-30A): Staff submissions must include empirical test verification evidence and simple, reproducible instructions (e.g. curl command or direct verification link) for Command to immediately inspect results.
5. Communications Hygiene: Use `gc mail ... --notify` for all active operational orders, directives, and blocker escalations to immediately wake the recipient. Omit `--notify` for informational, future-planning, or retrospective traffic (e.g. `AAR item: ...`, `Next week: ...`).
