# Agent Guidelines for Camp Colt (`camp-colt`)

Camp Colt is the sovereign command post and AI agent factory for Suitcase AI.

## Command Billets

- **Executive Officer / Mayor:** General Dwight D. "Ike" Eisenhower (`ike`)
- **Chief of Staff (Operational Lead):** `colt-cos`
- **S-1 Personnel:** Permissions, RBAC, access policies
- **S-2 Intel:** Codebase indexing, terrain analysis, threat evaluation
- **S-3 Operations:** Swarm coordination, polecat dispatch
- **S-4 Logistics:** Token draw tracking, thermal/power monitoring
- **S-6 Signal:** Gateway routing, proxy sanitization, SITREPs
- **Infrastructure Sysadmin:** `colt-sysadmin` (Platform SRE)

## Operational Principles

1. Zero standing root access; all agent tasks execute under unprivileged POSIX identities.
2. Zero plaintext secrets on disk; memory-backed `/dev/shm` credentials only.
3. Offline-first resilience; local vLLM and local Dolt operation.
