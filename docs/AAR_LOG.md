# After Action Report (AAR) Log — Camp Colt

**Document ID:** `AAR-CAMP-COLT-LOG`  
**Authority:** Chief of Staff (`colt-cos`), Camp Colt  
**Purpose:** Formal repository for operational observations, friction points, doctrine evolution, and institutional lessons learned across Camp Colt campaigns.

---

## Log Entries

### Entry 001: Billet Boundary Friction — Gitea Repo Provisioning vs. City Rig Mounting
- **Date:** September 22, 2026
- **Originator:** Mayor (`mayor`) via memo `cc-wisp-rpwn`
- **Context:** Bead `cc-xvy` (Establishing `rigs/a-staff`)
- **Observation:** S-3 tasked Mayor to create `colt/a-staff.git` on Gitea as well as clone and mount it in `city.toml`. Mayor lacked Gitea administrative credentials and correctly noted that municipal platform operations do not hold infrastructure admin rights.
- **Analysis:** Unclear division of labor caused task ping-pong between Mayor, S-3, and Platform Chief (`colt-sysadmin`). Repositories were treated ambiguously as platform admin or municipal items.
- **Doctrinal Decision & Remedy:**
  - Repositories are designated as **S-4 Logistics supply depots** (Class IX/VII digital material).
  - S-4 will manage Gitea repository creation, quotas, and inventory issuance using scoped tokens.
  - Platform SRE (`colt-sysadmin`) maintains the underlying Gitea K8s container/DB facility only.
  - Mayor receives repository coordinates from S-4 and mounts them into town workspaces.
  - Documented in `AGENTS.md` and `docs/SOP_WATCH_POSTURE.md`.

---

### Entry 002: Repository Cleanliness & Sergeant Major (SgtMaj) Walking Patrols ("Police Call")
- **Date:** September 22, 2026
- **Originator:** Command / Chief of Staff (`colt-cos`)
- **Context:** Post-operational drift in working directories (untracked plan drafts, test output, scratch files left in repo trees).
- **Observation:** Despite procedural guidelines, tactical workers (polecats) and staff officers periodically conclude tasks leaving untracked files, scratch scripts, or dirty git states across `colony` and mounted rigs.
- **Analysis:** In conventional military units, officers issue orders, but the **Sergeant Major (SgtMaj)** walks the lines, conducts daily "police calls", inspects bivouac hygiene, and enforces standards. Relying solely on the Chief of Staff or Commander to notice litter in the repo is poor command economy and allows workspace discipline to erode.
- **Action Item / Recommendation:**
  1. **Institute the SgtMaj Billet / Walking Patrol (`colt-sgtmaj`):** Create an automated watchdog/patrol routine representing the Battalion Sergeant Major.
  2. **Patrol Scope ("Walking the Lines"):**
     - Periodic inspection of colony root and all registered rigs in `city.toml`.
     - Execute `git status --porcelain` check; flag any untracked or modified files left by idle/completed sessions.
     - Inspect `.gc/`, `scratch/`, and temporary directories for uncollected garbage.
     - Issue immediate corrective notifications ("squawk tickets" / mail) to the responsible agent or S-3.
  3. **Stop Condition Gate:** S-3 must enforce a zero-dirty-git exit gate (`git status --porcelain == 0`) on all tactical worker FRAGOs before merging PRs.
