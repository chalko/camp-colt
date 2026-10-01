<!-- markdownlint-disable MD013 -->

# Upstream Gas City Issue Resolution Report: Issue #6873

**Issue Reference**: [`gastownhall/gascity#6873`](https://github.com/gastownhall/gascity/issues/6873)
**Governing Bead**: `gcs-eai`
**Target Repository**: `rigs/gascity`
**Branch**: `gcs-eai` (Commit: `c7a878784`)
**Resolution Timestamp**: 2026-10-01T10:20:48-07:00
**Author**: Mayor (Headquarters Commandant), Camp Colt
**Verification Status**: VERIFIED (Targeted unit tests and full mail provider test suites passed 100%)

---

## 1. Problem Formulation & Root Cause Analysis

### 1.1 Upstream Defect Description

Two related defects existed in the Gas City mail CLI and storage providers:

1. **CLI Multi-ID Inconsistency**:
   `gc mail mark-read` accepted arbitrary arguments, but internally only evaluated `args[0]`. If an operator or shell script passed multiple message IDs (or passed a quoted whitespace-delimited list `"$IDS"`), the command failed to mark subsequent IDs, or attempted to look up the entire space-separated string as a single non-existent message ID, returning `message not found`. In contrast, `gc mail archive` and `gc mail delete` supported multiple arguments and quoted lists via `splitMessageIDArgs`.

2. **Unread Mail Retention Leak**:
   When archiving an unread message via `gc mail archive` or provider methods (`Archive`, `ArchiveMany`, `ArchiveMatching`), the message bead was closed without first being marked as read. Consequently:
   - Historical listings and inquiries showed the message as unread.
   - The read-gated TTL cleanup sweeps (`SweepReadMessagesBefore` / `PurgeReadMessageWisps`) only sweep messages where `mail.read == "true"`. Unread archived messages were never reclaimed, causing dismissed mail to leak indefinitely into storage.

### 1.2 Root Cause Identification

1. **In `cmd/gc/cmd_mail.go`**:
   `doMailMarkReadJSON` lacked an invocation of `splitMessageIDArgs(args)` and only operated on `args[0]`.

2. **In `internal/mail/beadmail/beadmail.go`**:
   `Provider.Archive` and `Provider.ArchiveMatching` directly invoked `p.store.Close(id)` on open beads without checking or updating the read status (`mail.read` metadata and `read` label). Unlike `ArchiveInjectedAutoHandoffs` (which explicitly marks read before closing), normal archiving omitted the read transition.

---

## 2. Technical Implementation

### 2.1 Code Changes

1. **`internal/mail/beadmail/beadmail.go`**:

   - Added `isReadBead(b beads.Bead) bool` to inspect both `read` label and `mail.ReadMetadataKey` metadata.
   - Introduced `closeArchived(id string, read bool) error` helper:

     ```go
     func (p *Provider) closeArchived(id string, read bool) error {
         if !read {
             if err := p.store.Update(id, beads.UpdateOpts{
                 Labels:   []string{"read"},
                 Metadata: map[string]string{mail.ReadMetadataKey: "true"},
             }); err != nil && !errors.Is(err, beads.ErrNotFound) {
                 return fmt.Errorf("beadmail archive: %w", err)
             }
         }
         if err := p.store.Close(id); err != nil {
             if errors.Is(err, beads.ErrNotFound) {
                 return mail.ErrAlreadyArchived
             }
             return fmt.Errorf("beadmail archive: %w", err)
         }
         return nil
     }
     ```

   - Updated `Provider.Archive` and `Provider.ArchiveMatching` to use `closeArchived`.
   - Updated `beadToMessage` to use `isReadBead(b)`.

2. **`internal/mail/fake.go`**:

   - Updated `Fake.Archive` to set `msg.Read = true` upon archiving unread mail.

3. **`cmd/gc/cmd_mail.go`**:

   - Updated `newMailMarkReadCmd` usage to `mark-read <id>...` and revised help text.
   - Updated `doMailMarkReadJSON` to call `splitMessageIDArgs(args)`.
   - Added multi-ID loop preserving input order, emitting individual confirmation messages, reporting failures per ID while continuing to mark remaining IDs, and returning exit code 1 if any ID fails.
   - Preserved exact single-ID output behavior and schema compatibility.

4. **Regression Tests**:
   - Added `TestArchiveUnreadMarksReadFirst` in `internal/mail/beadmail/beadmail_test.go`.
   - Added `TestMailMarkReadList` in `cmd/gc/cmd_mail_test.go` covering separate arguments, quoted whitespace lists, and partial failure reporting.

---

## 3. Empirical Verification Evidence

### 3.1 Targeted Test Execution

```text
=== RUN   TestArchiveUnreadMarksReadFirst
--- PASS: TestArchiveUnreadMarksReadFirst (0.00s)
=== RUN   TestArchive
--- PASS: TestArchive (0.00s)
PASS
ok   github.com/gastownhall/gascity/internal/mail/beadmail 0.014s

=== RUN   TestMailMarkReadSuccess
--- PASS: TestMailMarkReadSuccess (0.00s)
=== RUN   TestMailMarkReadList
--- PASS: TestMailMarkReadList (0.00s)
PASS
ok   github.com/gastownhall/gascity/cmd/gc 0.368s
```

### 3.2 Full Mail Provider Suite Execution

```text
go test -v ./internal/mail/...
PASS
ok   github.com/gastownhall/gascity/internal/mail/exec 31.275s

go test -v ./cmd/gc -run "TestMail"
PASS
ok   github.com/gastownhall/gascity/cmd/gc 0.452s
```

All 60+ mail tests across CLI commands, MCP integration, and storage providers passed with zero regressions.

---

## 4. Hardware & Inference Telemetry

Captured from local ASUS Ascent GX10 bare-metal silicon (`colt-gpu-01` @ `10.82.0.3:8000` running `nvidia/llama-3.3-nemotron-super-49b-v1.5` under 64K FP8 context):

| Metric Dimension                    | Value / Telemetry Reading                  |
| :---------------------------------- | :----------------------------------------- |
| **Model Engine**                    | `nvidia/llama-3.3-nemotron-super-49b-v1.5` |
| **Context Limit**                   | 65,536 tokens                              |
| **Cumulative Prefill Tokens**       | 2,530,473                                  |
| **Cumulative Generation Tokens**    | 92,008                                     |
| **Prefix Cache Queries / Hits**     | 2,530,473 / 2,126,928                      |
| **Prefix Cache Hit Rate**           | **84.05%** Radix cache efficiency          |
| **Mean Time to First Token (TTFT)** | **700.12 ms** (702.92s / 1,004 requests)   |
| **Queue Concurrency**               | 0.0 running / 0.0 waiting                  |

---

## 5. Sovereign Staging & Deliverables

- **Bead Closed**: `gcs-eai`
- **Rig Commit**: `c7a878784` on branch `gcs-eai` in `rigs/gascity`
- **Public Policy Adherence**: Zero public GitHub tracker noise. Fix and regression tests staged cleanly on sovereign branch.
