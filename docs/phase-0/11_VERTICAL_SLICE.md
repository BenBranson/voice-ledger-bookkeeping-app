# 11. The First Vertical Slice — Duplicate Posted-Expense Detection

Detection → evidence → explanation → proposed solutions → approval → sandbox
write → activity log entry.

Scope is defined precisely below, including what is **deliberately excluded**.
The value of a vertical slice comes from it being narrow and complete; a wide
slice that is 80% complete proves nothing.

---

## 11.1 The gate ⚠ — read this first

**The slice's write path depends on one unverified fact: whether QBO supports
`POST /v3/company/{realmId}/purchase?operation=void`.**

Confidence `DOC-MED`. I believe it does. `CLAUDE.md` rule 6 says believing is not
enough, so the slice is specified with both branches and the branch is chosen by
a sandbox test, not by me.

| Branch | Condition | Slice write path |
|---|---|---|
| **A** | Void works on `Purchase`, is reversible or at minimum non-destructive (record retained, amount zeroed) | `voidPurchase` — `resolution: stagedAPI`. **Preferred.** |
| **B** | Void unsupported, or destroys the record | **No API write.** `resolution: manualQBO`. The slice still ships end to end, ending at a guided-manual step and an attested activity log entry. |

**Branch B does not fall back to hard delete.** Delete is permanent and
irreversible (§2, `TXN` profile). Trading a permanent destructive operation for
slice completeness would be exactly the wrong call, and the `ReversalPlan` type
(§5.5) would have to say `.irreversible` — which is a signal, not a formality.

**Branch B is still a complete vertical slice.** It exercises detection,
evidence, explanation, proposed solutions, approval, guided execution, and the
activity log. It exercises everything except the QBO write itself — and Wave 3 of
the spike (§2.8) will have proven other write paths (account deactivate, sparse
reclassification) regardless, so the write machinery is not left untested.

**Spike test to run first, before any slice work:**
`Wave 3, test 1` — create a `Purchase` in sandbox, void it, and record: HTTP
status, response body, whether the record survives, whether `TotalAmt` becomes 0,
whether the `SyncToken` increments, whether it still appears in `TransactionList`,
whether it can be un-voided, and what a Balance Sheet shows before and after.

---

## 11.2 In scope

### Data
- **One** sandbox company, one `realmId`, `environment == .sandbox`.
- Entity: **`Purchase` only.** Not `Bill`, not `BillPayment`, not `JournalEntry`,
  not `Check` as a separate concern (a `Purchase` with `PaymentType == Check` is
  in scope; a `Bill`+`BillPayment` pair is not).
- One accounting period, bounded by `AccountingPeriod`.
- Source: **QBO API only.** No imports in this slice — §9's pipeline is built in
  parallel but does not feed this rule yet.

### Rule `VL-DUP-EXP-001`
Three match tiers, all deterministic, all in `/core`:

| Tier | Criteria | Confidence |
|---|---|---|
| **T1 — exact** | Same vendor · same `TxnDate` · same `TotalAmt` · same payment account | `.high` |
| **T2 — reference** | Same vendor · same `TotalAmt` · same non-empty `DocNumber` (any date) | `.high` |
| **T3 — near-date** | Same vendor · same `TotalAmt` · same payment account · `TxnDate` within ±3 days | `.medium` |

**Severity** is a function of `dollarExposure` against the client's
`MaterialityPolicy` (§8.6) — not of tier. Severity is *how damaging*, confidence
is *how sure*; keeping them independent is §5.3's requirement, and this is where
it's first exercised.

**Exclusions, applied after detection and recorded as suppressions** (§8.5 step 6
— suppressed, not vanished):
- Either transaction already `isVoided`
- A finding for the same pair already `resolved` or `dismissed`
- A client memory rule marks this vendor+amount as legitimately recurring
- Below `MaterialityPolicy.absoluteFloor`

**Explicitly not excluded, but flagged:** transactions in a closed period. They
are detected, and the finding carries
`ResolutionConstraint.closedPeriod(closeDate:)` so its actions render
unavailable with the reason (§5.2). Failing to detect a closed-period duplicate
would be a false green.

### Pipeline
1. OAuth to sandbox via the thin backend; scope created; read-only by default.
2. Sync `Purchase` for the period — paginated, with the §2.6 checksum. Failed
   checksum → `Coverage.partial` → `.cannotEvaluate` → gray page. **This path is
   tested, not just written.**
3. Normalize to `LedgerTransaction` + `Posting` (§4), provenance attached.
4. `RuleEngine.evaluate(page: .fileHealthScan, …)` with only this rule registered.
5. Findings persisted to the client store.
6. UI: findings list → finding detail with evidence.
7. Claude explanation (optional — must work with the kill switch on).
8. Proposed actions rendered with consequences and reversal plan.
9. Approve → `StagedCorrection` → preflight (all five checks) → submit.
10. Confirm → activity log entry with before/after snapshots.
11. Re-evaluate → finding `.resolved`; page watermark changes; §6 staleness fires.

### UI — minimum viable, and no more
- Connection page row for the sandbox company, with the **SANDBOX badge visually
  unmistakable** (`CLAUDE.md` rule 7). Built first, per Build Order §2.
- One workflow page (Page 3 shell) with the Type A badge, findings list, and the
  §6 page-state rendering including the gray states.
- Finding detail: evidence, explanation, proposed actions, approve/dismiss.
- Staging queue view with correction states, including `UNKNOWN`.
- Activity log view.
- Ask Claude panel — **deferred.** Build Order §7 places it after a page has real
  findings; it is not needed to prove the slice.

---

## 11.3 Out of scope — explicitly

Listing these because scope creep on the first slice is the standard failure.

- Every other rule (§8.8's other 25)
- All other pages
- Imports of any kind (§9 is parallel work, not slice work)
- Voice
- Reports and the Close Package
- Webhooks — CDC polling only; webhooks are a latency optimization (§2 C4)
- Multi-client anything — the isolation *design* is implemented, but only one
  client is connected
- Firm Cockpit, Next Best Action, Training Mode, Client Question Builder
- Any production connection whatsoever
- Batch operations — single writes only. Batching is §10.7's concern, proven
  separately.
- Client memory rules — the *exclusion hook* exists; the learning UI does not

---

## 11.4 The worked example

The spec's sample finding, traced through every layer. This is the acceptance
scenario.

**Sandbox seed:**
```
Purchase #1842 · 2026-07-14 · Permian Supply · $486.20 · Checking · DocNo 4471
Purchase #1851 · 2026-07-14 · Permian Supply · $486.20 · Checking · DocNo 4471
```

**Detection.** T1 and T2 both match → `confidence: .high`.
`dollarExposure: $486.20` exceeds materiality → `severity: .high` → red.

**Finding renders:**
> **Possible duplicate expense — $486.20**
> Red · High confidence · Detection: automatic · Resolution: staged_api · Source: QBO API
>
> Two payments to Permian Supply share the same amount, date, payment account, and invoice number.
>
> **Evidence:** Expense #1842 — July 14 — $486.20 · Expense #1851 — July 14 — $486.20
>
> **Solutions:** 1. Void the second entry (recommended if only one bank withdrawal exists) 2. Keep both (if the statement confirms two withdrawals) 3. Ask the client
>
> *Before approving: view both transactions in QBO.*

Every element traced to its source:

| Element | Produced by |
|---|---|
| `$486.20` | Deterministic. `Money(minorUnits: 48620)` from the rule. |
| `Red` | `§5.7` derivation from severity `.high`. Not stored. |
| `High confidence` | Rule, T1+T2 match. Not an LLM judgment. |
| `Detection: automatic` | `Rule.identity` static classification |
| `Resolution: staged_api` | Branch A. **Branch B renders `manual_qbo`.** |
| `Source: QBO API` | `Provenance` (§4.5), carried from sync |
| The prose sentence | Claude, `GeneratedProse`, labeled guidance, `citedValues: [$486.20 ← VL-DUP-EXP-001]`. With the kill switch on, a deterministic template renders instead. |
| Evidence rows | `EvidenceItem.transaction` with `highlightedFields: [amount, date, paymentAccount, docNumber]` |
| Solution ordering | Deterministic. Solution 1 is first because T1+T2 matched. |
| Solution 1's parenthetical | Deterministic template — a genuine conditional, not narration |
| `Before approving` note | `preApprovalChecklist` (§5.1) |

**Approval → write (Branch A):**
```
StagedCorrection
  intentID:   <UUID, generated at draft>
  operation:  .voidPurchase
  parameters: purchaseId: 1851, syncToken: <from baseline>
  baseline:   verbatim Purchase #1851 as read
  diff:       "Void Purchase #1851 — $486.20 → $0.00, marked Voided"
  consequences: [.reconciliation("removes $486.20 from uncleared activity"),
                 .reporting("July expenses decrease by $486.20"),
                 .auditTrail("QBO retains the voided record")]
  reversal:   <determined by the spike — .reversible or .irreversible(warning:)>
```

Preflight → submit → confirm → activity log:
```
ActivityLogEntry
  kind: .correctionConfirmed
  actor: .user("Benjamin Branson")
  findingID / intentID linked
  beforeSnapshot: Purchase #1851 (TotalAmt 486.20, SyncToken 0)
  afterSnapshot:  Purchase #1851 (TotalAmt 0.00, Voided, SyncToken 1)
  ruleID: VL-DUP-EXP-001, ruleVersion: 1.0.0
```

Re-evaluation → finding `.resolved` · watermark changes · §6 staleness cascade
fires on downstream pages (none exist yet, so this is asserted in a test rather
than observed in the UI).

---

## 11.5 Acceptance criteria

The slice is done when **all** of these pass. Not a subset.

**Detection**
1. Seeded sandbox → sync → exactly the expected findings, no more, no fewer.
2. A near-miss (same amount, different vendor) produces **no** finding.
3. A T3 near-date pair produces `.medium` confidence, not `.high`.
4. Re-running the sync produces **identical finding IDs** — no duplicates.

**Honest coverage — the `CLAUDE.md` rule 5 tests**
5. Forcing a pagination checksum failure → `Coverage.partial` →
   `.cannotEvaluate` → **gray page, not green.**
6. With zero duplicates present **and** complete coverage → **green.**
7. With zero duplicates and no sync yet → **gray**, not green.
8. With the connection unhealthy → gray, regardless of findings.

**AI independence**
9. Full slice with the AI kill switch on: detection, severity, exposure,
   evidence, and proposed actions all identical, byte for byte. Only prose is
   absent.
10. A Claude explanation containing a currency figure not in `citedValues` is
    **discarded** and the finding renders without prose (§5.8).

**Write path (Branch A)**
11. Approve → void → confirm → activity log with before/after snapshots.
12. Preflight rejects on a stale `SyncToken` (mutate the entity in the sandbox UI
    between read and write) → `CONFLICTED`, no write sent.
13. Preflight rejects a closed-period write **client-side**, before any request.
14. **Injected timeout after send** → `UNKNOWN` → probe → correct terminal state.
    Run twice: once where the write actually landed, once where it didn't.
15. Kill the app between journal write and send → restart → recovery resolves it.
16. Read-only mode: approval unavailable in UI **and** the backend refuses the
    operation if invoked directly.

**Write path (Branch B)** — replaces 11–14
11b. Approve → guided manual procedure → your attestation → activity log entry
     recording the attestation, clearly marked as attested rather than verified.
12b. The finding's actions render `manual_qbo` with the constraint cited.

**Isolation**
17. A second sandbox company with deliberately identical data produces findings
    referencing only its own transactions (§7.8 test 1).

**Reproducibility**
18. Golden fixtures for `VL-DUP-EXP-001` pass with no network access.
19. The same duplicate data supplied as a CSV import produces the **same
    findings** modulo provenance (§4.1's contract). *Deferred to when §9 Tier 1
    lands, but the test is written now and skipped, not omitted.*

---

## 11.6 What this slice proves

Worth stating, because it's the justification for the sequencing:

- The backend catalog boundary works for both a read and a write (§3.4)
- The normalized model survives a real API round trip (§4)
- Three-outcome evaluation prevents a false green under real conditions (§8.1)
- Approval, preflight, and the `UNKNOWN` path work against a real API (§10)
- Client isolation holds with two live scopes (§7)
- The activity log's before/after snapshots are actually obtainable (§10.8)
- The kill switch is real (§3.6)

Everything after this slice is more rules, more pages, and more sources — each of
which reuses machinery this slice has proven, rather than inventing new
machinery. That is the point of doing it first.
