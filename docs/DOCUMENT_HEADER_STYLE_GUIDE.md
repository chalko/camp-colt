# Camp Colt Document Header Style Guide

**Document ID**: `SOP-S1-DOC-STYLE-001`
**Document Type**: Administrative Governance & Style Standard
**Custodian**: S-1 Personnel & Administration (`s1-personnel`), Camp Colt
**Effective Date**: 2026-10-07
**Target Audience**: All Command Billets (`cos`, `mayor`, `s1-personnel`, `s2-intel`, `s3-operations`, `s4-logistics`, `s6-signal`, `colt-sysadmin`), Rig Workers, and Contributors
**Governing Directive**: Commander's Planning Guidance (CPG) & Chief of Staff Administrative Mandate

---

## 1. Doctrinal Purpose & Core Philosophy

> _"Agent Staff takes its inspiration and form from the USMC staff process, but we are not playing soldiers here."_
> — Commander's Planning Guidance & Command Policy

Camp Colt organizes autonomous agent workflows through the functional Marine Corps staff structure (CoS, S-1, S-2, S-3, S-4, S-6, Sysadmin, Mayor) to enforce rigorous Completed Staff Work, clear accountability, role specialization, and operational continuity.

However, staff processes must reflect **genuine engineering and systems reality**. Theatrical military roleplay ("LARPing"), faux classification stamps, imaginary war rooms, and pseudo-tactical jargon obscure empirical receipts, degrade clarity, and distract from sovereign inference engineering.

This style guide establishes mandatory standards for document headers, metadata blocks, and technical terminology across all Camp Colt repositories (`colony`, `colt-results`, `suitcase-ai`, `a-staff`, `colt-utils`, `gascity`).

---

## 2. Invariant Rules & Style Boundaries

### 2.1 Zero Faux Classification Stamps

- **Prohibited**: `Classification: Sovereign Operations`, `Classification: Sovereign Appliance Internal`, `Classification: BATTALION STAFF`, `Classification: UNCLASSIFIED / GARRISON SOP`, `SECURITY / CLASSIFICATION: ...`.
- **Rationale**: Camp Colt is a sovereign, open-architecture AI appliance and engineering research lab. Security posture is enforced through cryptographic authentication (OpenSSH CA, mTLS, Vault AppRole), network segmentation, and zero plaintext secrets on disk—never through cosmetic classification markings.
- **Requirement**: Use `Document Type:` to identify the engineering nature of the document (e.g., `Document Type: Technical Benchmark Report`, `Document Type: Architectural Specification`).

### 2.2 Modern Engineering Terminology Over Theatrical Jargon

- **Prohibited**:
  - `Combat Operations Center (COC)` / `Virtual COC`
  - `WAR ORDER` / `WAR ROOM`
  - `MAGTF Authority` / `Authority: MCTP 3-30A` (when used as a faux legal authority stamp)
  - `Sovereign Operations / Staff Engineering Report`
- **Required Replacements**:
  - Use `Operations Watch` or `Tactical Watch` instead of `Combat Operations Center`.
  - Use `Incident Triage` or `Swarm Coordination` instead of `War Room`.
  - Use `Directive`, `Operational Plan`, or `Implementation Plan` instead of `War Order`.
  - Use `Standard: Completed Staff Work` to reflect MCTP 3-30A's doctrine of verified, rigorous submissions without pretending to be a military command.
  - Use `System Telemetry`, `Verification Receipt`, `Benchmark Configuration`, `Target Hardware`, `Serving Engine`, `Model Profile`, and `Timestamp`.

### 2.3 Required Factual Metadata Blocks

Every technical report, benchmark dossier, architecture specification, and after-action review must open with clean, factual metadata that provides immediate technical provenance:

1. **Document ID / Reference**: Tracking identifier or file reference.
2. **Document Type**: Exact functional classification (Benchmark, Telemetry, Specification, Plan, AAR, SOP).
3. **Author / Billet**: The functional staff billet or role responsible (e.g. `S-3 Operations (s3-operations)`, `Mayor (mayor)`).
4. **Target Hardware**: The physical compute substrate (e.g. `ASUS Ascent GX10 (NVIDIA Grace Blackwell GB10 @ 10.82.0.3:8000)`).
5. **Serving Engine**: The inference serving software and runtime parameters (e.g. `vLLM (FP8 KV Cache, 64K Context Window)`).
6. **Model Profile**: The model identifier (e.g. `nvidia/llama-3.3-nemotron-super-49b-v1.5`).
7. **Date / Timestamp**: ISO 8601 or standard localized date/time of completion.
8. **Verification Status**: Direct confirmation of test verification (e.g. `VERIFIED (Targeted regression tests passed 100%)`).

---

## 3. Standard Header Templates

### 3.1 Benchmark & Hardware Telemetry Reports (`colt-results/reports/`)

```markdown
# <Descriptive Technical Title>

**Document ID**: `COLT-BENCH-<CATEGORY>-<NUMBER>`
**Document Type**: Technical Benchmark Report | System Telemetry Report
**Author / Billet**: <Lead Billet> (e.g., `S-3 Operations (s3-operations)`)
**Collaborators**: <Contributing Billets>
**Hardware Platform**: ASUS Ascent GX10 (NVIDIA Grace Blackwell GB10 @ `10.82.0.3:8000`)
**Serving Engine**: vLLM (FP8 KV Cache, 64K Context Window, Prefix Caching Enabled)
**Model Profile**: `nvidia/llama-3.3-nemotron-super-49b-v1.5`
**Verification Date**: YYYY-MM-DD
**Verification Status**: VERIFIED (<Brief empirical evidence summary>)

---
```

### 3.2 Architectural Specifications & Implementation Plans (`suitcase-ai/plans/`, `docs/`)

````markdown
# <Specification Title>

```text
Document ID:     ARCH-COLT-<PROJECT>-<NAME>
Document Type:   System Architecture & Design Specification
Author / Billet: <Author Billet>
Reviewing Gates: <Reviewing Billets>
Target Enclave:  Camp Colt Sovereign AI Enclave (10.82.0.0/16)
Date:            YYYY-MM-DD
Status:          DRAFT | APPROVED | ACTIVE | COMPLETED
```
````

---

````

Or in Markdown format:

```markdown
# <Specification Title>

**Document ID**: `PLAN-CC-<CATEGORY>-<YEAR>-<NUMBER>`
**Document Type**: Master Strategic Infrastructure Plan | Implementation Plan
**Author / Billet**: <Author Billet>
**Reviewing Billets**: <Reviewers>
**Target Environment**: Camp Colt Sovereign AI Enclave (`10.82.0.0/16`)
**Date**: YYYY-MM-DD
**Status**: APPROVED / ACTIVE

---
````

### 3.3 Commander's Update Briefs (CUBs) (`docs/CUB_*.md`)

```markdown
# Commander's Update Brief (CUB) — Camp Colt

**Briefing ID:** CUB-YYYY-MM-DD-HHMM
**Date / Timestamp:** <Day, DD Month YYYY, HHMM PDT>
**Facilitator:** Chief of Staff (`colt-cos`), Camp Colt
**Operational Context:** Staff Coordination & Operational Status Update
**Target Environment:** Sovereign Command Post (`colt-hq` @ `10.82.0.20`)

---
```

### 3.4 After-Action Reports (AARs) & Incident Root Cause Analyses

```markdown
# After Action Report (AAR): <Incident or Exercise Name>

**Document ID:** `AAR-YYYY-MM-DD-<NAME>`
**Report Type:** Infrastructure Incident Root Cause Analysis | Operational After-Action Review
**Incident Period:** <ISO Timestamp Range>
**Author / Billet:** <Investigating Billet>
**Recipient:** Chief of Staff (`cos`), Commander
**Status:** Resolved / Stabilized
**Target Hardware / Service:** <Affected Host, Node, or Pod>

---
```

### 3.5 Standard Operating Procedures (SOPs)

```markdown
# Standard Operating Procedure: <Operational Procedure Name>

**Document ID:** `SOP-<CATEGORY>-<NUMBER>`
**Document Type:** Standard Operating Procedure
**Effective Date:** YYYY-MM-DD
**Lead Billet:** <Responsible Billet>
**Reviewing Authority:** Chief of Staff (`colt-cos`), Camp Colt
**Standard:** Completed Staff Work
**Target Environment:** Sovereign Command Post (`colt-hq`) & Mounted Rigs

---
```

---

## 4. Terminology Quick-Reference Table

| Disallowed / Discouraged Jargon                | Standardized Engineering Terminology                  | Context                         |
| :--------------------------------------------- | :---------------------------------------------------- | :------------------------------ |
| `Classification: Sovereign Operations`         | `Document Type: System Telemetry Report`              | Telemetry & validation logs     |
| `Classification: Sovereign Appliance Internal` | `Document Type: Hardware Procurement Specification`   | Hardware BOMs & specs           |
| `Classification: BATTALION STAFF`              | `Document Type: Technical Architecture Specification` | System design documents         |
| `Classification: UNCLASSIFIED / GARRISON SOP`  | `Document Type: Standard Operating Procedure`         | Internal SOPs                   |
| `Virtual Combat Operations Center (COC)`       | `Operations Watch` or `Tactical Watch`                | Staff watchkeeping & monitoring |
| `Combat Operations Center Watch Officer`       | `Operations Watch Officer`                            | S-3 billet description          |
| `WAR ORDER` / `WAR ROOM`                       | `Operational Directive` / `Incident Triage`           | Command orders & outage triage  |
| `Authority: MCTP 3-30A` (as faux seal)         | `Standard: Completed Staff Work`                      | Staff deliverable standard      |
| `Silicon Substrate` / `Silicon Hardware`       | `Target Hardware` or `Hardware Platform`              | Compute metadata                |
| `Model Engine`                                 | `Model Profile` or `Model Engine`                     | Weights & quantization metadata |

---

## 5. Compliance & Enforcement

1. **New Documents**: All new technical reports, plans, specifications, and telemetry summaries must adhere strictly to these formats before merging.
2. **Audit Cadence**: S-1 Personnel will audit documentation during regular weekly administrative reviews to maintain style compliance.
3. **Completed Staff Work**: Reviewing billets (`colt-cos`, `mayor`) will return submissions containing theatrical military LARP headers for refactoring before approval.
