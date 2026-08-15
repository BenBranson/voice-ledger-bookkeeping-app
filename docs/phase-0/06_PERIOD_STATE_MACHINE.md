# 6. Period Workflow State Machine

Page states, completion criteria, the dependency graph, and staleness
propagation rules.

The requirement this document exists to satisfy (spec, Page 12):

> Change an upstream transaction after a later page was completed, and everything
> downstream is automatically marked for revalidation rather than holding a false
> checkmark.

"Automatically" is the hard word. A design where some code path must remember to
call `markStale()` will eventually fail to. Decision **D3** replaces it with a
computed property: **a page is fresh iff the evidence watermark it was completed
against still equals the current watermark for its declared inputs.**

---

## 6.1 Page states

```swift
enum PageState: Hashable, Sendable {
    case blocked(by: [WorkflowPage])              // a prerequisite isn't complete
    case notStarted
    case dataIncomplete(DataGap)                  // "Coverage incomplete"
    case inProgress(openFindings: Int)
    case awaitingClient(findings: [FindingID])
    case readyToComplete                          // all criteria met, awaiting your confirmation
    case complete(CompletionAttestation)
    case stale(was: CompletionAttestation, cause: StalenessCause)
}

enum DataGap: Hashable, Sendable {
    case noSyncYet
    case syncPartial(reason: String)              // §2.6 pagination checksum failure
    case importRequired(what: String, whereInQBO: String)   // Type B
    case importStale(file: String, importedAt: Date, periodEnd: AccountingDate)
    case manualStepRequired(GuidedProcedure)      // Type C
    case connectionUnhealthy(RealmID)
    case featureNotEnabled(String)                // e.g. Class tracking off
    case capabilityUnverified(matrixRowID: String)  // CLAUDE.md #6
}
```

**`readyToComplete` and `complete` are distinct on purpose.** The app never
completes a page for you. It says "everything I can check has passed"; you
confirm. That confirmation is what `CompletionAttestation` records, and it is
what makes the Close Package a statement about *your* work rather than the app's.

**`stale` retains the prior attestation.** You need to see what was completed,
when, and what invalidated it. Discarding the attestation on staleness would lose
the audit trail precisely when it matters.

---

## 6.2 Completion criteria

```swift
struct CompletionCriteria: Sendable {
    let requiredDataSources: [RequiredDataSource]
    let requiredChecks: [RuleID]
    let requiredAttestations: [AttestationKind]     // Type C steps
    let openFindingPolicy: OpenFindingPolicy
}

enum OpenFindingPolicy: Sendable {
    case noOpenFindings
    case noOpenFindingsAboveSeverity(Severity)
    case allFindingsTriaged      // resolved, dismissed-with-reason, or awaitingClient
}
```

A page may enter `readyToComplete` only when **all** hold:

1. Every `requiredDataSource` is present, `Coverage.complete`, and not stale
   relative to `period.end`.
2. Every `requiredCheck` returned `.pass` or `.findings` — **never
   `.cannotEvaluate`** (§8). A check that could not run blocks completion.
3. Every `requiredAttestation` is recorded with actor and timestamp.
4. `openFindingPolicy` is satisfied.
5. The connection that fed the page is healthy. Per spec: *no workflow page may
   render green while the connection that fed it is red.*

Condition 2 is the one that does the work. It is the same guard as §5.7's green
derivation, applied at page scope, and it is why `.cannotEvaluate` had to be a
distinct outcome rather than an empty finding list.

---

## 6.3 The evidence watermark (D3)

```swift
/// A content-addressed description of exactly which data a conclusion rests on.
struct EvidenceWatermark: Hashable, Codable, Sendable {
    let realmID: RealmID
    let period: AccountingPeriod

    /// Highest CDC cursor incorporated, per entity kind.
    let entityCursors: [QBOEntityKind: CDCCursor]
    /// Content hash of the ledger slice each rule actually read.
    let ledgerSliceDigest: [QBOEntityKind: Digest]
    /// Imported documents in play: id → content hash.
    let importDigests: [ImportedDocumentID: Digest]
    /// Reports: kind+parameters → generation time and content hash.
    let reportDigests: [ReportSignature: (generatedAt: Date, digest: Digest)]

    let ruleVersions: [RuleID: RuleVersion]     // §8
    let qboMinorVersion: Int                    // §2.7
    let coverage: Coverage
}

struct CompletionAttestation: Hashable, Codable, Sendable {
    let page: WorkflowPage
    let completedBy: String
    let completedAt: Date
    let watermark: EvidenceWatermark
    let attestations: [RecordedAttestation]
    let findingsAtCompletion: [FindingID]
    let note: String?
}
```

### The freshness rule, entire

```
page.isFresh  ⟺  currentWatermark(for: page.declaredInputs) == attestation.watermark
```

That is the whole mechanism. No `markStale()` call exists anywhere in the
codebase, so no code path can forget to make one. A page's state is *derived*
from a comparison, every time it is displayed.

### Why digests and not just timestamps

A timestamp says "something changed." A digest says "the data this page's
conclusion rests on changed." Timestamps produce false staleness — a change to an
unrelated vendor record would invalidate the balance-sheet page, training you to
ignore staleness warnings. That is a worse outcome than no staleness tracking at
all, because it degrades a signal you need.

`ledgerSliceDigest` is scoped to what the rule actually read. A page that reads
only `Purchase` and `Bill` for July is unaffected by an August `Invoice`.

---

## 6.4 Staleness causes

```swift
enum StalenessCause: Hashable, Codable, Sendable {
    case upstreamPageInvalidated(WorkflowPage, cause: Box<StalenessCause>)
    case ledgerChanged(entities: [QBOEntityKind], changedIDs: [String])
    case importReplaced(ImportedDocumentID)
    case importSuperseded(old: ImportedDocumentID, new: ImportedDocumentID)
    case reportRegenerated(ReportSignature)
    case ruleVersionBumped(RuleID, from: RuleVersion, to: RuleVersion)
    case qboMinorVersionChanged(from: Int, to: Int)
    case coverageDegraded(from: Coverage, to: Coverage)
    case periodLockChanged(newCloseDate: AccountingDate)
    case correctionApplied(IntentID)          // our own approved write
    case connectionReauthorized(RealmID)      // forces full resync (§2 C5)
}
```

The UI states the cause in plain language: *"Marked for revalidation — Expense
#1842 was modified in QuickBooks on Aug 14, after this page was completed on
Aug 12."* An unexplained staleness flag is one you learn to dismiss.

**`correctionApplied` is the self-echo case.** Our own approved write mutates the
ledger and therefore changes the watermark. This is *correct* — the page's
conclusion genuinely rests on different data now — but it must be distinguishable
from a third-party change, or every correction would look like someone editing
the books behind you. The `intentID` links it to the activity log entry, so the
UI can say "revalidation needed because you voided Expense #1851 from this page,"
which reads as a normal consequence rather than an alarm.

This is also why §2 row C4's spike must determine whether webhooks echo our own
writes: without `intentID` suppression, one correction would produce two
staleness events.

---

## 6.5 Dependency graph

Edges mean "a change to the source page's conclusions may invalidate the target."

```
                    ┌─────────────────────────┐
                    │ 1. Access & Evidence    │  (A+C)
                    └────────────┬────────────┘
                                 ▼
                    ┌─────────────────────────┐
                    │ 2. Scope & Period Lock  │  (A+C)
                    └────────────┬────────────┘
              ┌──────────────────┼───────────────────┬──────────────┐
              ▼                  ▼                   ▼              ▼
   ┌────────────────┐  ┌──────────────────┐  ┌──────────────┐  ┌─────────┐
   │ 3. File Health │  │ 4. Bank Feed     │  │ 6. COA       │  │ 9. Sales│
   │    Scan   (A)  │  │    Cleanup  (B)  │  │  Cleanup(A+C)│  │  Tax    │
   └───────┬────────┘  └────────┬─────────┘  └──────┬───────┘  └────┬────┘
           │                    ▼                   │               │
           │           ┌──────────────────┐         │               │
           │           │ 5. Reconciliation│         │               │
           │           │          (B+C)   │         │               │
           │           └────────┬─────────┘         │               │
           └────────────┬───────┴───────────────────┘               │
                        ▼                                           │
              ┌──────────────────┐                                  │
              │ 7. Batch Fixes(A)│                                  │
              └────────┬─────────┘                                  │
                       ▼                                            │
              ┌──────────────────────┐                              │
              │ 8. Balance Sheet     │                              │
              │    Integrity     (A) │                              │
              └────────┬─────────────┘                              │
                ┌──────┴───────┐                                    │
                ▼              ▼                                    │
        ┌──────────────┐  ┌──────────────────┐                      │
        │ 10. Taxes(A) │  │ 11. Month-End    │◀─────────────────────┘
        └──────┬───────┘  │     Close  (A+C) │
               └─────────▶└────────┬─────────┘
                                   ▼
                          ┌──────────────────┐
                          │ 12. Reporting (A)│
                          └──────────────────┘
```

### Edge justifications

| Edge | Why |
|---|---|
| 1 → all | Company identity and baseline evidence precede everything. Wrong realm = every conclusion void. |
| 2 → all | The period boundary and lock define what "in scope" means for every rule. |
| 3 → 6, 7 | Health-scan findings are the input to COA cleanup and batch reclassification. |
| 4 → 5 | Bank-feed cleanup resolves duplicates and missing postings that reconciliation would otherwise chase. |
| 5 → 7 | Reconciliation exposes miscodings that batch fixes correct. |
| 5 → 8, 11 | Unreconciled accounts make balance-sheet integrity and close unreliable. |
| 6 → 7, 8 | Account structure changes shift where transactions land. |
| 7 → 8 | Reclassification directly moves balance-sheet and P&L amounts. |
| 8 → 10, 11, 12 | Balance-sheet integrity is the precondition for estimates, close, and reports. |
| 9 → 11 | Sales tax must be reviewed before close. Skippable per client — a skipped page satisfies the edge with a recorded skip attestation, not silently. |
| 10 → 11 | Tax estimate is informational; the edge is weak but the close checklist references it. |
| 11 → 12 | The close package reports the closed period. |

**Cycle check:** the graph is a DAG. Notably 4 → 5 but not 5 → 4: reconciliation
findings that require bank-feed action create a *finding* on Page 4, not an edge
back to it. Feedback loops between pages are represented as findings and
carry-forward items, never as graph edges, or the propagation would not
terminate.

---

## 6.6 Propagation algorithm

On any watermark-affecting event:

1. **Identify affected inputs.** From the event (a CDC batch, an import, a rule
   version bump, an approved write), determine which watermark components change.
2. **Recompute the current watermark** for each page whose declared inputs
   intersect the changed components.
3. **Compare against each page's attestation.** Inequality → transition
   `complete` → `stale(was:cause:)`.
4. **Cascade along the DAG.** Every page reachable from a newly-stale page
   becomes `stale(cause: .upstreamPageInvalidated(...))`, carrying the root cause
   so the UI can explain the whole chain.
5. **Never auto-recomplete.** A page that becomes stale and whose data reverts is
   *not* silently restored to complete. Re-completion requires you to look at it
   again. Auto-recompletion would mean a checkmark you never granted.

Step 5 is a deliberate asymmetry: staleness is automatic, completion is manual.
That asymmetry is the whole point.

---

## 6.7 Skipped and not-applicable pages

Page 9 is skippable per client. A skip is a **recorded decision**, not an absent
page:

```swift
enum PageApplicability: Hashable, Codable, Sendable {
    case applicable
    case skippedByPolicy(reason: String, decidedBy: String, at: Date)
    case notApplicable(reason: String)     // e.g. Class tracking not enabled
}
```

A skipped page satisfies its outgoing dependency edges but renders **gray with
"skipped," never green**, and the Close Package lists it as skipped with the
reason. `CLAUDE.md` rule 5 again: green means verified. Skipped is not verified.

---

## 6.8 Period lifecycle

```swift
enum PeriodState: Hashable, Sendable {
    case open
    case inProgress(pagesComplete: Int, pagesTotal: Int)
    case readyToClose                 // all applicable pages complete or skipped
    case closedInVoiceLedger(ClosePackageID)
    case closedInQBO(attestedAt: Date, closeDate: AccountingDate)
    case reopened(reason: String, by: String, at: Date)
}
```

**`closedInVoiceLedger` and `closedInQBO` are separate states** because they are
separate facts, and conflating them would be the exact kind of overclaim
`CLAUDE.md` and the spec's terminology rules exist to prevent. Voice Ledger's
close is our checklist; QBO's Books Close is an action you take in QBO (§2 row
11.2, no API). A period can be closed in Voice Ledger and open in QBO. The UI
must show both.

**Reopening always leaves a trace.** A reopened period retains its prior close
package; the new close package references it. "This period was closed on Aug 12,
reopened Aug 20 for a vendor correction, re-closed Aug 21" is exactly the kind of
history the Activity & Correction Log exists to hold.

---

## 6.9 What this design does not do

- **It does not track partial page progress inside a page.** A page is complete
  or it isn't. Sub-page progress lives in finding statuses.
- **It does not model concurrent editing by two operators.** Single-operator tool;
  revisit if that changes.
- **It does not detect changes made in QBO before the connection existed.**
  Nothing can — that is the Activity Log's stated limitation (spec), partially
  closed by importing QBO's own audit log export.
- **It does not prevent you from completing a page you shouldn't.** It prevents
  *green*, states the gap, and records what you attested to. The distinction
  between "the app blocks you" and "the app tells you the truth and records your
  decision" is the operating model of the whole product.
