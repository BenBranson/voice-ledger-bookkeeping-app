# 11. The First Vertical Slice — Duplicate Posted-Expense Detection

Detection → evidence → explanation → proposed solutions → approval → guided
QBO handoff → attested activity log entry.

Scope is defined precisely below, including what is **deliberately excluded**.
The value of a vertical slice comes from it being narrow and complete; a wide
slice that is 80% complete proves nothing.

---

## 11.1 The gate — resolved 2026-08-16

**The slice's write path depended on one fact: whether QBO supports
`POST /v3/company/{realmId}/purchase?operation=void`.**

It was tested against the live sandbox. **Answer: no.**

```json
{
  "Fault": {
    "Error": [{
      "Message": "Unsupported Operation",
      "Detail": "Operation void is not supported.",
      "code": "500",
      "element": "Operation"
    }],
    "type": "ValidationFault"
  }
}
```

Also tested per owner Decision 3 on `Bill`, `JournalEntry`, and
`BillPayment` — none support void either (see
`docs/phase-0/02_QBO_CAPABILITY_MATRIX.md` rows `11.x`, `11.x-bill`,
`11.x-je`, `11.x-bp`). **Branch B is confirmed, not conditional.**

| Branch | Status |
|---|---|
| ~~A~~ | **Eliminated.** Void is unsupported on every `TXN`-profile entity tested. |
| **B** | **Confirmed.** No API write. `resolution: manualQBO`. |

**Branch B does not fall back to hard delete.** Delete is permanent and
irreversible (§2, `TXN` profile). Trading a permanent destructive operation for
slice completeness would be exactly the wrong call, and the `ReversalPlan` type
(§5.5) would have to say `.irreversible` — which is a signal, not a formality.

**Branch B is not a degraded version of the slice — it's the correct shape of
this product, more than Branch A would have been.** Most of what this app does
sits on the other monitor from QBO. A first slice that ends in a guided handoff
and an attestation, rather than a silent API write, is the honest operating
model, not a consolation prize. It exercises detection, evidence, explanation,
proposed solutions, approval, guided execution, and the activity log — it
exercises everything except a QBO write, and Wave 3 of the spike already proved
the write machinery works against real writes elsewhere (account create/rename/
deactivate, batch, journal entries, transfers) — see §2.8's Wave 3 results.

**The resolution path is clean, not a workaround.** Once you void the duplicate
directly in QBO and Voice Ledger resyncs, the existing exclusion —
*"either transaction already `isVoided`"* (§11.2) — retires the finding
automatically. Branch B requires no special-cased resolution logic; it's the
same exclusion every other resolved-in-QBO finding already uses.

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

| Tier | Criteria | Confidence | Applicability |
|---|---|---|---|
| **T1 — exact** | Same vendor · same `TxnDate` · same `TotalAmt` · same payment account | `.high` | Always active |
| **T2 — reference** | Same vendor · same `TotalAmt` · same non-empty `DocNumber` (any date) | `.high` | **Conditional — see below** |
| **T3 — near-date** | Same vendor · same `TotalAmt` · same payment account · `TxnDate` within ±3 days | `.medium` | Always active |

**T2 is conditional on a company setting, verified 2026-08-16, not assumed.**
QBO enforces unique `DocNumber` per company **by default** — attempting to
create two `Purchase` records sharing a `DocNumber` fails outright (fault
`6140`, confirmed live). A same-`DocNumber` duplicate can only exist in a
client's real data if they have `VendorAndPurchasesPrefs.UseCustomTxnNumbers`
enabled. (Note this is the *vendor/purchases-side* setting, distinct from
`SalesFormsPrefs.CustomTxnNumbers` on the sales side — verified as two
separate preferences, not one generic toggle.)

**Design consequence — per-tier applicability, not a special case for this
rule.** Added to `Rule`'s interface (`docs/phase-0/08_RULE_ENGINE.md` §8.2):
any rule with multiple detection tiers can report which tiers are active for
the current client and why. `VL-DUP-EXP-001` reports T2 inactive when
`.customTxnNumbersForPurchases` (a new company feature flag, populated from
the Preferences field above and cached alongside other company facts) is off.
**This is informational, not a coverage gate** — T1 and T3 keep the rule fully
evaluable on their own, so an inactive T2 must never push the page to
`.cannotEvaluate`. Training Mode surfaces it: *"Tier 2 (matching invoice/
reference numbers) is inactive for this client because Custom Transaction
Numbers is off in their QBO vendor/purchases settings."*

**Severity** is a function of `dollarExposure` against the client's
`MaterialityPolicy` (§8.6) — not of tier. Severity is *how damaging*, confidence
is *how sure*; keeping them independent is §5.3's requirement, and this is where
it's first exercised.

**Exclusions, applied after detection and recorded as suppressions** (§8.5 step 6
— suppressed, not vanished):
- **Either transaction already `isVoided`** — this is Branch B's resolution
  path (§11.1): void directly in QBO, resync, this exclusion retires the finding.
- A finding for the same pair already `resolved` or `dismissed`
- A client memory rule marks this vendor+amount as legitimately recurring
- Below `MaterialityPolicy.absoluteFloor`

**Explicitly not excluded, but flagged:** transactions in a closed period. They
are detected, and the finding carries
`ResolutionConstraint.closedPeriod(closeDate:)` so its actions render
unavailable with the reason (§5.2). Failing to detect a closed-period duplicate
would be a false green.

### Pipeline
1. OAuth to sandbox via the thin backend; scope created; read-only (Branch B
   never needs Write-Enabled mode — it makes no QBO write at all).
2. Sync `Purchase` for the period — paginated, with the §2.6 checksum. Failed
   checksum → `Coverage.partial` → `.cannotEvaluate` → gray page. **This path is
   tested, not just written** — §2.6's skip scenario was reproduced live
   (`docs/phase-0/02_QBO_CAPABILITY_MATRIX.md` §2.6), so this isn't a
   theoretical mitigation.
3. Normalize to `LedgerTransaction` + `Posting` (§4), provenance attached.
4. `RuleEngine.evaluate(page: .fileHealthScan, …)` with only this rule registered.
5. Findings persisted to the client store.
6. UI: findings list → finding detail with evidence.
7. Claude explanation (optional — must work with the kill switch on).
8. Proposed actions rendered with consequences and reversal plan, resolution
   `manual_qbo`.
9. Approve → `GuidedProcedure` presented (no staging, no preflight, no write —
   there is nothing to preflight when there's no API call).
10. You complete the void in QBO directly, then attest completion in Voice
    Ledger → activity log entry recording the attestation.
11. Re-sync → the `isVoided` exclusion fires → finding `.resolved` · watermark
    changes · §6 staleness cascade fires on downstream pages (none exist yet,
    so this is asserted in a test rather than observed in the UI).

### UI — minimum viable, and no more
- **Not** the full Connection Pages (step 1.3, separately gated) — only what
  this slice needs: a minimal indicator carrying the **SANDBOX badge visually
  unmistakable** (`CLAUDE.md` rule 7), reusing `VLEnvironmentBadge`
  (`desktop/Sources/DesignSystem/VLEnvironment.swift`, already built and tested).
- One workflow page (Page 3 shell) with the Type A badge, findings list, and the
  §6 page-state rendering including the gray states.
- Finding detail: evidence, explanation, proposed actions, approve/dismiss.
- Guided-procedure view + attestation form (replaces the staging-queue view —
  there is no staging state to show in Branch B).
- Activity log view.
- Ask Claude panel — **deferred.** Build Order §7 places it after a page has real
  findings; it is not needed to prove the slice.

---

## 11.3 Out of scope — explicitly

Listing these because scope creep on the first slice is the standard failure.

- Every other rule (§8.8's backlog)
- All other pages
- Imports of any kind (§9 is parallel work, not slice work)
- Voice
- Reports and the Close Package
- Webhooks — CDC polling only; webhooks are a latency optimization (§2 C4)
- Multi-client anything — the isolation *design* is implemented, but only one
  client is connected
- Firm Cockpit, Next Best Action, Training Mode's full UI (the per-tier
  applicability *data* is produced per §11.2; a dedicated Training Mode screen
  is not), Client Question Builder
- Any production connection whatsoever
- Batch operations — not needed; Branch B has no batched write
- Client memory rules — the *exclusion hook* exists; the learning UI does not
- Relationship-class rules and many-to-one/one-to-many matching (§8.2, §9 —
  interface-level accommodations only, no rule content; see
  `docs/phase-0/08_RULE_ENGINE.md` §8.2a and `docs/phase-0/09_INGESTION_PIPELINE.md` §9.11)

---

## 11.4 The worked example

Traced through every layer, using the **real sandbox data** the spike created
(`docs/phase-0/SPIKE_QUEUE.md`'s duplicates seed) — not a hypothetical.

**Sandbox seed (real, realm `9341456442848752`):**
```
Purchase #145 · 2026-07-14 · Permian Supply · $486.20 · Checking · DocNo 4471
Purchase #151 · 2026-07-14 · Permian Supply · $486.20 · Checking · DocNo 4471-DUP
```

**Why the DocNumbers differ from the original hypothetical:** the original
worked example had both postings share `DocNo 4471`. Per §11.2's verified
finding, QBO's default company rejects that outright — two `Purchase` records
cannot share a `DocNumber` unless Custom Transaction Numbers is enabled. This
seed reflects what a default company can actually contain, which is exactly
the scenario T2's conditional-applicability design (§11.2) exists for.

**Detection.** T1 matches — same vendor, date, amount, account →
`confidence: .high`. T2 does **not** match — DocNumbers differ, correctly
inert given `UseCustomTxnNumbers: false` in this sandbox — and its inactivity
is surfaced (§11.2), not silent.
`dollarExposure: $486.20` exceeds materiality → `severity: .high` → red.

**Finding renders:**
> **Possible duplicate expense — $486.20**
> Red · High confidence · Detection: automatic · Resolution: manual_qbo · Source: QBO API
>
> Two payments to Permian Supply share the same amount, date, and payment account.
>
> **Evidence:** Expense #145 — July 14 — $486.20 (Doc# 4471) · Expense #151 — July 14 — $486.20 (Doc# 4471-DUP)
>
> **Solutions:** 1. Void the duplicate directly in QBO if only one bank withdrawal exists — Voice Ledger cannot void a Purchase via the API (confirmed 2026-08-16) 2. Keep both (if the statement confirms two withdrawals) 3. Ask the client
>
> *Voice Ledger cannot complete this write — it requires action in QBO directly. Before proceeding: view both transactions in QBO.*

Every element traced to its source:

| Element | Produced by |
|---|---|
| `$486.20` | Deterministic. `Money(minorUnits: 48620)` from the rule. |
| `Red` | `§5.7` derivation from severity `.high`. Not stored. |
| `High confidence` | Rule, T1 match alone. Not an LLM judgment. T2 inactive this session — see §11.2. |
| `Detection: automatic` | `Rule.identity` static classification |
| `Resolution: manual_qbo` | **Confirmed, not conditional** — §11.1. |
| `Source: QBO API` | `Provenance` (§4.5), carried from sync |
| The prose sentence | Claude, `GeneratedProse`, labeled guidance, `citedValues: [$486.20 ← VL-DUP-EXP-001]`. With the kill switch on, a deterministic template renders instead. |
| Evidence rows | `EvidenceItem.transaction` with `highlightedFields: [amount, date, paymentAccount]` — `docNumber` dropped from the highlight set since T2 didn't match this instance |
| Solution ordering | Deterministic. Solution 1 is first because T1 matched. |
| Solution 1's wording | Deterministic template — states the API limitation as fact, not narration |
| `Before proceeding` note | `preApprovalChecklist` (§5.1) |

**Approval → guided procedure (Branch B — the only path):**
```
GuidedProcedure
  intentID:   <UUID, generated at draft — still tracked, for the activity log>
  mechanism:  .guidedManual(procedure: GuidedProcedure(
                steps: [
                  "Open QuickBooks Online",
                  "Go to Expenses, find the vendor Permian Supply",
                  "Locate Purchase #151 (Doc# 4471-DUP, $486.20, July 14)",
                  "Confirm with the bank statement whether one or two withdrawals occurred",
                  "If one: void Purchase #151 in QBO"
                ],
                pitfalls: [
                  "Void, not delete — voiding preserves the audit trail; deleting does not (§2, TXN profile)",
                  "Voice Ledger cannot verify this happened until the next sync"
                ],
                doneCriteria: "Purchase #151 shows as Voided in QBO, TotalAmt $0.00"
              ))
  consequences: [.reconciliation("removes $486.20 from uncleared activity, once completed in QBO"),
                 .reporting("July expenses decrease by $486.20, once completed in QBO"),
                 .auditTrail("Voice Ledger records your attestation; QBO's own record of the void is authoritative")]
  reversal:   .reversibleManually(procedure: "Un-void in QBO if done in error")
```

You complete the void in QBO → attest in Voice Ledger → activity log:
```
ActivityLogEntry
  kind: .manualCompletionAttested
  actor: .user("Benjamin Branson")
  findingID / intentID linked
  procedure: <the GuidedProcedure above>
  attestedAt: <timestamp>
  note: <optional — e.g. "Confirmed with client, only one withdrawal occurred">
  ruleID: VL-DUP-EXP-001, ruleVersion: 1.0.0
```

**Re-evaluation is where Branch B closes the loop cleanly.** The next sync
reads Purchase #151 with `isVoided: true`. `VL-DUP-EXP-001`'s existing
exclusion — *"either transaction already `isVoided`"* — fires. The finding
resolves **without Voice Ledger ever calling a QBO write endpoint.** No
special-cased "Branch B resolution" logic was needed; this is the same
exclusion path every already-resolved-in-QBO finding uses. Watermark changes;
§6 staleness cascade fires on downstream pages (none exist yet, so this is
asserted in a test rather than observed in the UI).

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

**Write path — Branch B, the only path (was 11b/12b; now the active set,
renumbered)**
11. Approve → guided manual procedure presented → your attestation recorded →
    activity log entry with `kind: .manualCompletionAttested`, clearly marked
    as attested rather than verified.
12. The finding's actions render `manual_qbo` with no staged-write option
    ever offered — not "offered then rejected," genuinely absent from the UI,
    since offering a control for a capability confirmed not to exist would be
    its own kind of dishonesty.
13. After attestation, a resync where Purchase #151 shows `isVoided: true`
    resolves the finding **via the existing exclusion**, with **no** write
    call made by Voice Ledger. Assert no QBO write endpoint was invoked
    during this step — this is the test that proves §11.1's "clean, not
    degraded" claim.
14. A resync where the void did *not* actually happen in QBO (attested but
    not done) leaves the finding open — attestation is not treated as proof.

**Isolation**
15. A second sandbox company with deliberately identical data produces findings
    referencing only its own transactions (§7.8 test 1).

**Reproducibility**
16. Golden fixtures for `VL-DUP-EXP-001` pass with no network access,
    including a T2-inactive fixture case (Custom Transaction Numbers off)
    and a T2-active fixture case (on) — both tiers' applicability logic
    needs coverage, not just T1/T3's detection logic.
17. The same duplicate data supplied as a CSV import produces the **same
    findings** modulo provenance (§4.1's contract). *Deferred to when §9 Tier 1
    lands, but the test is written now and skipped, not omitted.*

---

## 11.6 What this slice proves

Worth stating, because it's the justification for the sequencing:

- The backend catalog boundary works for a read (§3.4) — Branch B needs no
  write catalog entry at all, which is itself informative: the catalog's
  read-only Phase 1 step 1.2 scope is sufficient for this slice.
- The normalized model survives a real API round trip (§4)
- Three-outcome evaluation prevents a false green under real conditions (§8.1)
- Per-tier rule applicability works end to end — a real rule with a
  conditionally-inactive tier, not a hypothetical (§11.2, §8.2a)
- The guided-manual → attestation → exclusion-driven resolution path works
  against a real API, with no write ever attempted (§10, revised for Branch B)
- Client isolation holds with two live scopes (§7)
- The activity log's attestation record is actually obtainable (§10.8)
- The kill switch is real (§3.6)

Everything after this slice is more rules, more pages, and more sources — each of
which reuses machinery this slice has proven, rather than inventing new
machinery. That is the point of doing it first.

**One thing this slice does NOT prove, flagged rather than implied:** the
staged-write path (`StagedCorrection`, preflight's five checks, the `UNKNOWN`
timeout state, the resolution probe) — because Branch B makes no QBO write.
That machinery is real and specified (§10) and Wave 3 of the spike exercised
parts of it directly against non-void writes (account create/rename/
deactivate, batch, journal entries), but it has no home in *this* slice. The
next rule whose resolution is `staged_api` — not `VL-DUP-EXP-001` — is what
proves that path end to end.
