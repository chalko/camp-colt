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

---

### Entry 003: Billet Division — Workspace Compiler & Toolchain Installation (Mayor vs. Platform SRE)

- **Date:** September 24, 2026
- **Originator:** Commander / Chief of Staff (`colt-cos`)
- **Context:** Installing and verifying developer toolchains (Go compiler, OpenCode binary) on `colt-hq`.
- **Observation:** When developer tooling or compilers are required inside the command post workspace (`colt-hq`), tasks have alternated between the Mayor (Headquarters Commandant) and Platform Chief (`colt-sysadmin`).
- **Analysis:**
  - Under MAGTF doctrine (MCTP 3-30A), the Headquarters Commandant manages camp domestic plumbing, bivouac layout, workspace hygiene, and garrison order.
  - The Platform SRE manages hypervisors, K8s metal, OS declarations, and core system daemons.
  - On a single-user virtual workstation (`colt-hq`), unprivileged user-space packages poured via Homebrew (UID 1000) sit on the borderline between municipal camp furnishings and platform software engineering.
- **AAR Action Item / Friday Agenda:**
  - Codify the definitive boundary: Does unprivileged CLI toolchain installation belong to the Mayor (as municipal camp equipment) or Platform SRE (as systems administration)? Table for Friday 1400 AAR discussion.

---

### Entry 004: YAGNI Governance — Delaying Formal SOPs until the Rule of Three

- **Date:** September 24, 2026
- **Originator:** Commander
- **Context:** Establishing model qualification pipelines, FRAGOs, and operational workflows.
- **Observation:** Tendency to draft formal, rigid Standard Operating Procedures (SOPs) prematurely after a single occurrence or during the initial learning curve, creating unnecessary administrative overhead.
- **Doctrinal Principle Adopted (Rule of Three / YAGNI for SOPs):**
  1. **Immediate Lessons Learned:** Always log observations, friction points, and technical discoveries immediately in the AAR log to preserve institutional memory.
  2. **Tactical Agility via FRAGOs:** Iterate and adapt workflows rapidly using lightweight taskers, FRAGOs, and direct command directives during early iterations.
  3. **The Rule of Three Gate:** Do NOT draft, formalize, or publish a binding SOP until the procedure has been executed successfully and consistently at least **three times**.

---

### Entry 005: External Credential Lifecycle & Token Expiration Governance (S-1 Personnel Billet)

- **Date:** September 24, 2026
- **Originator:** Commander
- **Context:** GitHub Fine-Grained Personal Access Token (PAT) provisioned for `chalko/colt-results` outbound mirror with a 90-day maximum lifetime.
- **Observation:** External service tokens and fine-grained PATs increasingly enforce mandatory maximum lifespans (e.g., GitHub 90-day cap). Without automated tracking, outbound mirroring, CI/CD pipelines, and external integrations fail silently upon token expiration.
- **Doctrinal Decision & Remedy:**
  - Assign external credential lifecycle monitoring, access policy audits, and renewal schedules to the **S-1 Personnel (Permissions, RBAC, access policies)** billet.
  - S-1 will maintain a ledger of external tokens, scopes, and expiration dates, issuing renewal notifications to Command 14 days before expiration.
  - Set an operational reminder bead (`+75d`) for Command to renew the `colt-results` GitHub mirror PAT prior to the 90-day cutoff.

---

### Entry 006: S-Staff Billet Disciplines & Completed Staff Work Standards (Operation cc-32m)

- **Date:** September 26, 2026
- **Originator:** S-3 Operations (`s3-operations`) via bead `cc-3eq`
- **Context:** Operation `cc-32m` (First sovereign serving pilot and compiler tool migration on ASUS Ascent GX10 GB10)
- **Observations & Lessons:**
  1. **Strict Zero-`kubectl` Invariant:** Staff officers must never run `kubectl` or direct cluster mutations. Cluster infrastructure is strictly owned by Platform Chief (`colt-sysadmin`). Telemetry is queried via HTTP Grafana datasource proxy; visual charts are rendered via HTTP.
  2. **Never Conflate Serving Benchmarks with Agentic Evaluations:** Baseline hardware throughput, thermal stability, and UMA memory clamping (Tier 1) must be verified before launching autonomous agentic workouts (Tier 2).
  3. **Gateway Caching Bias:** Comparative proxy latency benchmarking requires randomized cold-cache UUID probe nonces, alternating query order, and trimmed mean sampling to prevent Radix prefix caching distortion.
  4. **Tone Hygiene & Visual Report Layout:** Eliminate pseudo-military boilerplate in technical reports. Visual timeseries charts must be rendered full-width (24-column) with local Pacific Time (`tz=America/Los_Angeles`) and embedded directly alongside the corresponding metric tables with a direct interactive Grafana dashboard link.
  5. **Zero-Dirty-Git Exit Gate:** Mandate `git status --porcelain == 0` and 100% clean pre-commit passing across all repositories before closing operational beads.
- **Reference:** [`rigs/a-staff/plans/AAR_FIRST_COMPLETED_STAFF_ACTION_CC32M.md`](file:///home/camp-colt-mayor-agent/colony/rigs/a-staff/plans/AAR_FIRST_COMPLETED_STAFF_ACTION_CC32M.md) (`AAR-ASTAFF-CC32M-001`).

---

### Entry 007: Git Worktree Cleanliness Doctrine & Municipal Audit Automation

- **Date:** September 26, 2026
- **Originator:** S-3 Operations (`s3-operations`) via bead `cc-nqpv`
- **Context:** Codification of Git Worktree Cleanliness doctrine and municipal audit automation across Camp Colt.
- **Observation:** As multi-agent swarms, ephemeral workers, and toolchain builds proliferate across mounted rigs, unmanaged working trees and abandoned git worktrees cause context pollution, merge conflicts, and supervisor thrashing.
- **Doctrinal Standard Adopted (`SOP-0.3-WORKTREE-CLEANLINESS`):**
  1. **Four-Tier Defense Architecture:**
     - **Tier 1 (Tactical Worker Clean-Exit Gate):** Mandate `git status --porcelain == 0` and worktree pruning before closing any task bead.
     - **Tier 2 (Scripted Lifecycle & Trap Discipline):** Automation scripts creating secondary worktrees must enforce deterministic POSIX EXIT/INT/TERM traps to remove worktree directories, prune worktrees, and delete temporary branches.
     - **Tier 3 (Turnkey Municipal Audit Tooling):** Deploy [`scripts/audit_git_cleanliness.sh`](file:///home/camp-colt-mayor-agent/colony/scripts/audit_git_cleanliness.sh) to audit the colony root and all mounted rigs (`a-staff`, `colt-results`, `colt-utils`, `go_template_rule`, `suitcase-ai`), returning exit 0 on clean state or exit 1 on uncommitted/orphaned files.
     - **Tier 4 (Watch Cadence & Shift Handoff Discipline):** Certify garrison git cleanliness in shift handoffs, 06:00 CUB documents, and weekly Friday retrospectives.
  2. **Hard Stop Condition:** No task bead may be transitioned to `CLOSED` (`status=closed`) if `git status --porcelain` returns any output.
- **References:** [`rigs/a-staff/battlebook/SOP_GIT_WORKTREE_CLEANLINESS.md`](file:///home/camp-colt-mayor-agent/colony/rigs/a-staff/battlebook/SOP_GIT_WORKTREE_CLEANLINESS.md), [`scripts/audit_git_cleanliness.sh`](file:///home/camp-colt-mayor-agent/colony/scripts/audit_git_cleanliness.sh), and [`rigs/a-staff/plans/AAR_FIRST_COMPLETED_STAFF_ACTION_CC32M.md`](file:///home/camp-colt-mayor-agent/colony/rigs/a-staff/plans/AAR_FIRST_COMPLETED_STAFF_ACTION_CC32M.md).
