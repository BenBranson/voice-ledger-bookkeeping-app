# 10. Staging, Approval, Audit, and Recovery

`CLAUDE.md` rule 2: **detect → draft → review → push.** No code path writes to a
production QuickBooks file without an explicit human approval step. Staged
corrections live locally first.

This document specifies that path, and specifies what happens when a write times
out — the case that produces double-voided transactions in systems that get it
wrong.

---

## 10.1 The write lifecycle

```
  Finding
    │  you choose a ProposedAction
    ▼
  ┌──────────────┐
  │  DRAFTED     │  StagedCorrection created locally. Nothing sent.
  └──────┬───────┘
         │  you review the diff and consequences
    ┌────┴────┐
    ▼         ▼
 DISCARDED  ┌──────────────┐
            │  APPROVED    │  human approval recorded: who, when, what they saw
            └──────┬───────┘
                   ▼
            ┌──────────────┐
            │  PREFLIGHT   │  re-read entity · SyncToken · round-trip · period lock
            └──────┬───────┘
               ┌───┴────┐
               ▼        ▼
          CONFLICTED  ┌──────────────┐
                      │  SUBMITTED   │  ◀── journaled BEFORE the network call
                      └──────┬───────┘
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
        ┌──────────┐  ┌──────────┐  ┌──────────────┐
        │CONFIRMED │  │ FAILED   │  │  UNKNOWN     │ ← timeout / no response
        └──────────┘  └──────────┘  └──────┬───────┘
                                           │ resolution probe (§10.6)
                                    ┌──────┴──────┐
                                    ▼             ▼
                              CONFIRMED       FAILED
```

**`SUBMITTED` is persisted and flushed to disk before the request is sent.** If
the app crashes between send and response, restart finds a `SUBMITTED` record
with no terminal state, moves it to `UNKNOWN`, and resolves it. A journal written
after the call would lose the record of a write that may have landed — which is
the whole failure this design exists to prevent.

---

## 10.2 The staged correction

```swift
struct StagedCorrection: Identifiable, Codable, Sendable {
    let id: StagedCorrectionID
    let realmID: RealmID
    let intentID: IntentID              // stable across every retry. §10.5
    let findingID: FindingID
    let actionID: ProposedActionID

    let operation: CatalogOperationKind      // §3.4 — a named op, never a URL
    let parameters: StagedWriteParameters

    /// The entity exactly as read, verbatim. This is what we write from —
    /// never the normalized form (§4, M3).
    let baselineSnapshot: EntitySnapshot
    let baselineSyncToken: String
    let baselineReadAt: Date

    let diff: CorrectionDiff                 // what you review
    let consequences: [Consequence]
    let reversal: ReversalPlan

    var state: StagedCorrectionState
    var approval: ApprovalRecord?
    var attempts: [WriteAttempt]
}

struct ApprovalRecord: Codable, Sendable {
    let approvedBy: String
    let approvedAt: Date
    let diffDigest: Digest          // hash of exactly what was displayed
    let consequencesDigest: Digest
    let evidenceWatermark: EvidenceWatermark   // §6 — data state at approval time
}
```

**`diffDigest` makes approval specific rather than general.** You approved *that*
diff. If anything about the correction changes between approval and submission —
a re-read produced different data, a rule version bumped, materiality changed —
the digest no longer matches and the approval is void. You re-approve. An
approval that survives a change to what's being approved isn't an approval.

---

## 10.3 Preflight — five checks, all blocking

Runs immediately before the write, never earlier.

**1. Fresh re-read.** The entity is read from QBO again, right now. Per spec:
*the entity is freshly re-read immediately before writing.*

**2. SyncToken match.** The current token must equal `baselineSyncToken`. A
mismatch means the entity changed since you looked at it — possibly by you in
QBO on the other monitor. → `CONFLICTED`, never a forced write.

**3. Round-trip fidelity.** Decode the fresh read into our model, re-encode, and
compare against the raw response. A mismatch means we hold fields we don't
understand, and a full update would clear them (§2, row 7.1, constraint 2). →
block the write.

**Verified-necessary, not precautionary — do not remove this check.** This was
flagged as the check most likely to be dropped as over-engineering. It isn't:
the Wave 3 spike (2026-08-16) confirmed sparse updates silently drop data on
real QBO entities — a `Purchase` line memo was cleared, and a `Bill`'s second
line was truncated, by resending a sparse update that omitted them (see
`spike/fixtures/results-2026-08-16T20-45-42-102Z.json`, matrix rows 6.3/7.1,
7.2, `docs/phase-0/02_QBO_CAPABILITY_MATRIX.md`). This is not a hypothetical
QBO behavior this check guards against — it is an observed one. It is cheap,
it runs once per write, and it is the only defense against silently destroying
fields on entities whose sparse-update support turns out to be incomplete. It
also *discovers* those entities for us, which feeds §2's matrix.

**4. Period lock.** `TxnDate` vs. `BookCloseDate` and Voice Ledger's own stricter
lock. Per `CLAUDE.md` and spec, closed-period writes are blocked **client-side
before reaching QBO** (§2, row 2.3). The QBO error is a backstop for the race,
not the control.

**5. Semantic re-verification.** Re-run the originating rule against fresh data.
If the finding no longer reproduces — someone already fixed it — the correction
is `CONFLICTED` with `.findingNoLongerReproduces`. Writing a correction for a
problem that no longer exists is how you void the wrong transaction.

```swift
enum ConflictReason: Codable, Sendable {
    case syncTokenChanged(expected: String, found: String)
    case entityDeleted
    case roundTripMismatch(unknownFields: [String])
    case periodNowClosed(closeDate: AccountingDate)
    case findingNoLongerReproduces
    case approvalDigestMismatch
    case accessModeReadOnly            // §3.4 — also enforced server-side
}
```

A `CONFLICTED` correction is **never auto-resolved**. It returns to you with the
specific reason and a fresh diff.

---

## 10.4 Access mode gate

Per `CLAUDE.md` rule 4: every new client connection starts in Read-Only Mode;
writes are enabled per client, explicitly.

Enforced in **three** places, deliberately redundant:
1. `ClientScope.accessMode` — the UI won't offer approval.
2. Preflight check — the client won't submit.
3. **The backend refuses write-classed catalog operations for a realm in
   read-only mode** (§3.3 item 7). This is the authoritative one; the first two
   are convenience.

The authoritative flag lives in the backend, not in the local database. A local
flag is a flag a modified client could flip.

**Item 3 — IMPLEMENTED 2026-08-17.** `connections.write_enabled` (SQLite,
`backend/src/db/sqlite.ts`; migration-safe `ALTER TABLE` for realms
connected before this column existed, verified against the real running
backend's DB, not just a fresh test one), `TokenStore.isWriteEnabled`/
`setWriteEnabled`, and `dispatcher.ts`'s `shouldBlockWrite` — checked
structurally inside `dispatch()` itself, not left to each route handler to
remember. `GET`/`PUT /realms/:realmId/write-access` (`routes/operations.ts`)
expose it; the desktop `ConnectionView` toggle calls these directly. Live-
verified end to end: GET returns `false` for a never-toggled realm, PUT
flips it, a second GET confirms the flip, flipped back to `false` before
moving on so the sandbox was left in its safe default state. **No write-
classified catalog operation exists yet** — `assertReadOnlyCatalog()` still
holds — so this gate currently blocks nothing in practice; it's built ahead
of the first write operation needing it, the same "prove the mechanism
before the thing that depends on it exists" approach used throughout this
project (e.g. §11.1's `isVoided` exclusion, proven before any write path
existed to trigger it). **Items 1 and 2 (`ClientScope.accessMode`, the
preflight check) are not built** — no `StagedCorrection`/approval UI exists
yet for them to gate.

---

## 10.5 Idempotency

Per spec: *every write carries an idempotency record; a timed-out POST is never
blindly retried.*

```swift
struct IntentID: Hashable, Codable, Sendable {
    let rawValue: UUID    // generated at DRAFT time, stable forever
}
```

`intentID` is generated when the correction is drafted — not per attempt. Every
attempt for that correction carries the same value. It appears in:
- the backend request (logged, §3.5)
- the local journal
- the activity log entry
- **QBO's request-idempotency parameter, if one exists** — ⚠ **ASSUMED,
  unverified.** §2's spike must determine whether QBO supports a caller-supplied
  idempotency key on the operations we use, and what its retention window is.

**The design does not depend on QBO supporting idempotency.** If it does, we use
it. If it does not, §10.6's resolution probe is the mechanism, and it works
either way. Building on an assumed idempotency guarantee would be exactly the
kind of unverified-capability dependency `CLAUDE.md` rule 6 prohibits.

---

## 10.5a Response validation — HTTP 200 is not success ⚠ correction, 2026-08-16

**This is a correctness bug fix, not a new feature.** Wave 3's void-on-other-
entities tests found two real anomalous-200 responses from QBO:
- `Bill` void → HTTP 200 with a `SystemFault` body (a leaked Java exception
  inside a 200 envelope)
- `JournalEntry` void → HTTP 200 with an empty `BatchItemResponse` (a silent
  no-op)

(`spike/fixtures/results-2026-08-16T20-45-42-102Z.json`, matrix rows
`11.x-bill`, `11.x-je`.) Either would be read as success by a status-code
check. **Status-code checking is therefore not a valid success test anywhere
in this design**, and every write path in this document that implicitly
assumed "2xx ⇒ success" is corrected by this section.

**1. A single chokepoint, not a per-operation check.** The backend's response
handling has exactly one place a QBO write response passes through before any
caller sees a result:

```swift
enum WriteResponseOutcome: Sendable {
    case success(entity: QBOEntitySnapshot)
    case rejected(fault: QBOFault)                 // clean, well-formed rejection
    case unknown(reason: MalformedResponseReason)   // §10.5a — routes to §10.6
}

enum MalformedResponseReason: Sendable {
    case faultInside2xx(QBOFault)          // Bill-void shape
    case emptyOrMissingExpectedEntity      // JournalEntry-void shape
    case unparseableBody
}

/// The ONLY function in the backend permitted to turn a raw HTTP response
/// into a result a caller acts on. No individual catalog operation parses
/// its own response — this exists specifically so no operation can forget
/// to check the body.
func classifyWriteResponse(_ raw: RawHTTPResponse) -> WriteResponseOutcome
```

No catalog operation (§3.4) is permitted to inspect `raw.status` and decide
success on its own. Every write op's implementation calls
`classifyWriteResponse` and only ever sees its result — `.success`,
`.rejected`, or `.unknown`. A fault element present anywhere in a 2xx body is
`.rejected`, never `.success`.

**2. An empty or structurally unexpected success body is `.unknown`, not
`.success`.** This is the JournalEntry-void case. "No fault present" is not
"it worked" — it's exactly the shape of response we have the least ability to
interpret, so it is treated with the same suspicion as a network timeout: it
routes into `UNKNOWN` (§10.6), not into `CONFIRMED`.

**3. This changes the resolution probe's step 1** (§10.6, revised below). The
probe used to start by re-reading the entity. It now starts by asking whether
the *original* response was well-formed at all, because an anomalous-200 write
is exactly the case where the original response tells us the least, and a
probe that skips straight to re-reading throws that signal away.

**4. Structural test requirement.** Add a backend test asserting **no code
path treats a 2xx status as success without passing through
`classifyWriteResponse`** — e.g., a lint-style test that greps/AST-scans every
catalog operation's response handling for a direct `status == 2xx` success
branch outside the chokepoint, or (preferred, once the catalog exists in code)
a compile-time guarantee that operations can only construct a
`WriteResponseOutcome` via the chokepoint function, never by hand. This is a
Phase 1 step-1.6 requirement, not deferred — the slice makes no QBO write
(§11.1), but the chokepoint and its test are prerequisites for step 1.6 per
the owner's instruction, because the *next* rule whose resolution is
`staged_api` depends on it existing.

---

## 10.6 The `UNKNOWN` state and the resolution probe

**The case this whole document is organized around.** We sent a write. We got no
response, or a timeout, or a network error after send. We do not know whether it
landed.

**Rules:**
1. `UNKNOWN` is a persisted, first-class state — not an exception.
2. **Never retry.** A retry may double-void, double-create, or double-post.
3. `UNKNOWN` **blocks all further writes to that entity** until resolved. Not just
   this correction — any correction touching the same entity.
4. It is surfaced prominently: the Connection Page, the staging queue, and the
   affected page all show an unresolved write. This is not a background condition.
5. Resolution is a **probe**, never an inference.

### The probe

**Revised 2026-08-16 (§10.5a) — step 1 is now about the original response,
not the entity.** An `UNKNOWN` can arise two ways: no response at all (network
timeout — the classic case this document was written for), or a response that
arrived but was malformed (§10.5a's anomalous-200 case). Those need different
first moves: the second case already has a real, if confusing, response worth
inspecting before spending a network round trip on a fresh read.

```
1. Was there an original response at all?
   ├─ No response received (true timeout/network error) → go to step 2
   └─ A response WAS received but was malformed (§10.5a:
      .faultInside2xx or .unparseableBody) → inspect it first:
        ├─ faultInside2xx names a real QBO fault  → treat as strong evidence
        │    of FAILED, but still corroborate via step 2 before finalizing —
        │    a leaked fault in a 200 is not yet proven equivalent to a clean
        │    rejection until we've seen it happen more than once (Bill-void
        │    is the only confirmed instance so far)
        └─ emptyOrMissingExpectedEntity (JournalEntry-void shape) → no signal
             either way, proceed to step 2 with no prior
2. Re-read the entity by Id.
   ├─ Not found + operation was a delete   → CONFIRMED
   ├─ Not found + operation was not delete → FAILED (or investigate)
   └─ Found → continue
3. Compare SyncToken to baselineSyncToken.
   ├─ Unchanged → the write did not land → FAILED (safe to re-stage)
   └─ Changed  → something wrote → continue
4. Compare entity state to the correction's expected post-state.
   ├─ Matches expected → CONFIRMED (our write landed)
   └─ Differs          → AMBIGUOUS
5. CDC sweep for the entity around the submission window.
   └─ Corroborates or contradicts step 4.
6. AMBIGUOUS after all of the above → escalate to you, with both snapshots
   side by side. Never guessed.
```

**Step 3 is the load-bearing one for the classic timeout case.** An unchanged
`SyncToken` is strong evidence the write did not land, because any successful
write increments it. **Step 1 is now the load-bearing one for the
anomalous-200 case** (§10.5a) — it's the only step that uses information the
original response actually gave us, before falling back to the same
re-read/SyncToken/CDC machinery used for a true timeout.

**Step 4's `AMBIGUOUS` case is real**: someone edited the entity in QBO during
the same window, so the token changed for a different reason. That is exactly
when a human must look, and exactly when an automated system that guesses causes
damage.

### Startup recovery
On launch, for every client scope: any correction in `SUBMITTED` or `UNKNOWN`
is resolved before that client's pages render. Pages that depend on the affected
entity show `dataIncomplete(.unresolvedWrite)` until it settles — never a state
computed from data we know might be wrong.

---

## 10.7 Batching

§2 row C6: batch max 30, not transactional, partial success is normal.

**We cap at 10, not 30.** Reasoning: a timed-out batch produces N `UNKNOWN`
records, each requiring its own probe and each blocking its entity. 30
simultaneous unknowns is a recovery problem; 10 is manageable. The throughput
difference is irrelevant at bookkeeping scale, and the cap is configurable if
sandbox testing shows batch reliability is high.

Per-item journaling, never per-batch: 10 items produce 10 journal rows with
independent states.

**Every item in a batch is a full-entity update with a complete `Line` array,
never a sparse update — correction, 2026-08-16.** §10.3 check 3 already made
this the rule for a single correction; Wave 3 confirmed it's not optional for
batch either, since the failure mode is the same shape either way: a partial
`Line` array is silently accepted by QBO and **truncates** the transaction
(the spike's Bill test dropped a second line by resending only the first).
Each of the 10 items in a batch runs its own §10.3 preflight — including round-
trip fidelity — before submission; a batch is 10 independently-preflighted
corrections submitted together, not one operation that gets preflighted once.

**Before any batch runs, the preview shows** (spec, Page 7): transactions
affected · total dollars · old and new category · tax-period consequences ·
before/after report impact · reversal plan. All computed deterministically. The
before/after report impact is a computed projection, clearly labeled as a
projection, not a re-fetched report.

---

## 10.8 The Activity & Correction Log

**Terminology, deliberately** (`CLAUDE.md`): *Voice Ledger Activity & Correction
Log*, not "Audit Log." QBO's real audit log has no API access at all.

```swift
struct ActivityLogEntry: Identifiable, Codable, Sendable {
    let id: ActivityLogEntryID
    let realmID: RealmID
    let recordedAt: Date
    let actor: Actor                       // .user(String) | .system | .scheduledSync
    let kind: ActivityKind
    let findingID: FindingID?
    let intentID: IntentID?
    let beforeSnapshot: EntitySnapshot?
    let afterSnapshot: EntitySnapshot?
    let qboResponse: SanitizedQBOResponse?
    let ruleID: RuleID?
    let ruleVersion: RuleVersion?
    let note: String?
}

enum ActivityKind: String, Codable, Sendable {
    case findingDetected, findingDismissed, findingSuperseded
    case correctionDrafted, correctionApproved, correctionSubmitted
    case correctionConfirmed, correctionFailed, correctionUnknown, correctionResolved
    case documentImported, documentVerified, documentRejected
    case pageCompleted, pageReopened, pageMarkedStale
    case accessModeChanged, connectionAuthorized, connectionRevoked
    case materialityChanged, memoryRuleCreated
    case periodClosed, periodReopened
    case askClaudeConversation
}
```

**Append-only.** No update, no delete. Corrections to the log are new entries
referencing prior ones.

### What it can and cannot prove — stated in the UI, not just in docs

**Can prove:** what Voice Ledger detected, proposed, and submitted; what you
approved; QBO's response; before/after entity snapshots; which user initiated it;
every file you imported and when.

**Cannot prove:** who changed something directly in QBO outside the app, or
history predating the connection.

The log's own header says this. An audit trail that overstates its coverage is
worse than one that doesn't exist, because it will be relied on. *(An imported
QBO Audit Log export — CSV or PDF — partially closes that gap, which is much of
why Universal Ingestion matters.)*

---

## 10.9 Recovery scenarios

| Scenario | Behavior |
|---|---|
| App crashes between journal write and send | `SUBMITTED` found at startup → probe → resolved |
| App crashes after send, before response | Same |
| Network drops mid-request | `UNKNOWN` → probe |
| QBO returns 500 | `FAILED` — a 500 after processing is possible, so probe anyway before allowing re-stage |
| QBO returns 429 | Not a failure. Backoff with jitter, retry the *same* `intentID`. Rate limiting is pre-processing. |
| SyncToken stale (5010) | `CONFLICTED` → fresh diff → re-approve |
| Closed period rejection | `CONFLICTED(.periodNowClosed)`. Also a bug signal — preflight check 4 should have caught it. Log as an engine defect. |
| Batch partial success | Per-item terminal states; successes stand |
| Refresh token expired mid-write | `UNKNOWN` (we can't know if it reached QBO) → re-auth → probe |
| Two corrections target the same entity | Second blocks until the first reaches a terminal state. Serialized per entity. |

---

## 10.10 What this design does not attempt

- **No automatic rollback.** A confirmed write is not silently undone. Reversal is
  a new, separately-approved correction using `ReversalPlan` (§5.5). Automatic
  rollback would be an unapproved write, violating `CLAUDE.md` rule 2.
- **No queued offline writes.** Writes require a live connection and a fresh
  preflight. An offline queue would submit corrections against data verified
  hours earlier.
- **No cross-entity transactions.** QBO has no multi-entity transaction, so we
  don't pretend to. A correction spanning entities is multiple corrections with
  visible independent states — because that is what it actually is.
