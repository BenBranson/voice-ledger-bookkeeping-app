# Spike Queue — Ordered, Runnable

The capability spike (§2.8, §12.5) as an execution list rather than a plan.
Each item is a single `@CapabilityTest`, runnable independently, that emits one
matrix row's verdict and one fixture. Run them in this order — later items
assume earlier ones passed.

**Mechanics recap (§12.5):** a row becomes `VERIFIED` only when its test passes
against a live sandbox; the matrix is regenerated from test results, never
hand-edited. `VERIFIED` expires after 90 days.

**Revision (owner review, 2026-08):** three changes from the original draft —
the seeding harness is now a queue item instead of an implicit assumption, a
missing idempotency test was added, and Wave 3 (writes) now runs before Wave 2
(negatives). Rationale for the reorder: a wrong negative costs a manual step
that was going to be manual anyway; a wrong write assumption costs damaged
client books. The higher-consequence unknowns settle first.

**New wave order:** Wave 0 (seeding + prerequisites) → the gate test →
idempotency test → Wave 1 (reads) → **Wave 3 (writes)** → **Wave 2
(negatives)** → Wave 4 (awkward ones).

---

## ✅ Run 2026-08-16 — Wave 0, the gate, and Wave 1 complete

Approved and run against the connected sandbox (realm `9341456442848752`).
11/11 tests produced a definitive result — 10 `VERIFIED` (3 partial-coverage,
noted below), 1 `DISPROVEN`. Full detail in `docs/phase-0/02_QBO_CAPABILITY_MATRIX.md`
(regenerated) and `docs/phase-0/VERIFICATION_LEDGER.json` (the mechanical
source of every status change). Fixtures:
`backend/spike/fixtures/results-2026-08-16T17-34-45-969Z.json` (final clean
run) plus two earlier runs in the same directory that surfaced and fixed
real bugs before this one.

**The headline result: item 1 (`testPurchaseVoid`) came back DISPROVEN.**
QBO: `"Message": "Unsupported Operation", "Detail": "Operation void is not
supported."` — unambiguous, not a malformed-request issue. Per §11.1's
pre-written branch logic this selects **Branch B**. Not acted on beyond
recording the fact in the matrix — see the owner's "report before acting"
instruction.

**Four real findings surfaced fixing the run itself**, all now documented
in the matrix's `TXN` profile section (§2.1): `Purchase` requires
`PaymentType` on create (undocumented); `DocNumber` must be unique per
company by default (affects `VL-DUP-EXP-001`'s T2 tier); `DocNumber` has a
21-char max; `PrivateNote` is not a queryable field (a bug in this repo's
own `seed.ts`, now fixed with incremental manifest saves + a `DocNumber`-
based lookup).

**One test needed a same-session correction, recorded rather than hidden:**
the first pagination-integrity run assumed QBO's default order was
Id-ascending; it's actually descending, which meant the intended "delete an
earlier record" scenario accidentally deleted what would be fetched *last*,
producing an invalid "no skip" result. Fixed by adding an explicit
`ORDER BY Id` (confirmed supported) to the real page queries; the corrected
run reproduces the skip cleanly. Both versions are in the fixtures
directory for the record.

---

## ✅ Run 2026-08-16 (same day) — Wave 3 + Decision 3's void tests complete

Approved via `SPIKE_RUN_REVIEW.md` Decision 3, run immediately after Wave 1.
13/13 tests produced a definitive result — 11 `VERIFIED` (2 partial-coverage),
2 `DISPROVEN`. Matrix regenerated again. Fixture:
`backend/spike/fixtures/results-2026-08-16T20-45-42-102Z.json` (an earlier
same-session attempt crashed on two response-shape assumptions and is not
kept — its bugs are fully explained in the test files' own revision
comments instead of preserved as a redundant large fixture).

**The two DISPROVEN results are the most consequential findings of the
entire spike so far.** Both concern sparse updates — the mechanism §7's
entire batch-fix design rests on:

- **Purchase (item 16):** an entity-level sparse update left `DocNumber`
  and `PrivateNote` untouched, but the same update — resending the `Line`
  array to change `AccountRef` — **silently cleared the line's memo**,
  a field never mentioned in the request.
- **Bill (item 17):** sending only 1 of 2 lines **silently dropped the
  second line** — no error, HTTP 200, a $20 line item gone.

Neither is "sparse update requires the full array or rejects the
request" (safe). Both are "a partial update is *accepted* and *silently
loses data*" (dangerous). `docs/phase-0/02_QBO_CAPABILITY_MATRIX.md`'s
§10 preflight round-trip check — decode, encode, byte-compare against a
fresh read — is the only thing in the current design that would have
caught either before it was written. This moves that check from
precautionary to load-bearing.

**Decision 3's three additional void tests (Bill, JournalEntry,
BillPayment) all came back DISPROVEN, but not uniformly** — this is the
other major finding:

| Entity | Response | Danger |
|---|---|---|
| `Purchase` | Clean HTTP 400, "Unsupported Operation" | None — an honest answer |
| `BillPayment` | Clean HTTP 400, identical to Purchase | None |
| `Bill` | **HTTP 200** with a `Fault`/`SystemFault` body (a leaked Java `UnsupportedOperationException`) | Status-code-only success checking would wrongly record this as a successful void |
| `JournalEntry` | **HTTP 200** with an empty body — no `Fault`, no entity object | No error signal at all; only a resolution-probe re-read revealed the entity was untouched |

**Consequence:** "check `response.status === 200`" is not a sufficient
success test against this API, at least for void, and nothing tested this
session rules out the same pattern on other write operations not yet
tried. Branch B is confirmed as the correct path for all four entities
tested — the response-shape inconsistency is arguably the bigger finding.

**Two more required-field discoveries, same pattern as Wave 1's
`PaymentType` finding:** `Bill` requires `VendorRef` on every write,
sparse or not (fault 2020) — the same shape as `Purchase` requiring
`PaymentType`. Both now in §2.1's `TXN` profile notes.

**Account deactivation with a non-zero balance (item 15) succeeded without
error** — no adjusting `JournalEntry`, and QBO renames the account
(appending `" (deleted)"`) as an undocumented side effect. The account's
own `CurrentBalance` reports `0` afterward, but the original transactions
that posted to it are untouched — this was verified directly (not
inferred from "no error") and is flagged as needing a real accounting
read (Trial Balance) before Page 6's deactivate path can be called safe
for non-zero-balance accounts. See the matrix's 6.3/6.4 card for the full
account.

---

## Wave 0 — prerequisites

Nothing below runs without this. Not capability tests themselves — this is
what makes the capability tests possible and reproducible.

| # | Item | Detail |
|---|---|---|
| **0** | **Build the seeding harness** | The `Seeds/` structure from §12.6: `baseline.json` (COA, vendors, opening balances), `duplicates.json` (exact / near / legitimate-recurring cases), `reconciliation.json` (matched, unmatched, partially cleared), `closed-period.json` (transactions before/after a close date), `edge-cases.json` (zero amounts, very large, multi-line, linked transactions). **Idempotent, versioned, with hard teardown between suites.** Built first, deliberately — a manually-seeded sandbox drifts and becomes unreproducible (§12.6), and ad-hoc seeding built mid-wave is how that happens. Item 6, item 33, and item 43 below cannot run without specific seed fixtures this harness provides. |
| — | Intuit developer account + sandbox company | Owner-created — not something this queue can automate. developer.intuit.com, free. |
| — | OAuth round trip against the sandbox app | Exercises the backend's `auth/oauth.ts` exchange and refresh |
| — | Environment badge visually proven distinct | Sandbox vs. production — `CLAUDE.md` rule 7, checked before any other UI work |

---

## The gate — run immediately after Wave 0, before anything else

Everything downstream of the vertical slice branches on this one test
(§11.1).

| # | Test | Matrix row | Asserts | Result (2026-08-16) |
|---|---|---|---|---|
| **1** | `testPurchaseVoid` | 11.x (slice gate) | Create a `Purchase` in sandbox, void it via `?operation=void`. Record: HTTP status, response body, whether the record survives, whether `TotalAmt` becomes 0, whether `SyncToken` increments, whether it still appears in `TransactionList`, whether it can be un-voided, Balance Sheet before/after. **Output determines Branch A vs. Branch B for the entire vertical slice (§11.1).** | ❌ **DISPROVEN** — HTTP 400 "Operation void is not supported." → **Branch B** |
| **2** | `testIdempotencyKeySupport` | §10.5 | Determine whether QBO accepts a caller-supplied idempotency key on the write operations in our catalog. If so: record the header/parameter name, the retention window, and behavior on a repeated key (returns the original result vs. errors vs. silently duplicates). If not: record as a negative, with what was searched. **This sits underneath the entire `UNKNOWN`-state recovery design** (§10.6) — the resolution probe works either way, but the answer determines whether the probe is the primary mechanism or a fallback behind QBO's own idempotency guarantee. | ✅ **VERIFIED** — `requestid` param works; repeated request returned the same entity, no duplicate created (tested on Purchase create only) |

Do not proceed to slice-adjacent design work until item 1 returns. **It has
— see Result column. Branch B is selected; what to build is the owner's
decision, not yet made.**

---

## Wave 1 — read surface (unblocks read-only sync)

Exit condition: a full read-only sync of a seeded sandbox, reproducible and
checksum-clean.

| # | Test | Matrix row | Asserts | Result (2026-08-16) |
|---|---|---|---|---|
| 3 | `testCompanyInfoHealthCheck` | C1 | Live, timestamped, non-cached. Latency distribution. Whether it counts against CorePlus metering. Exact error shape on a revoked token. | ✅ VERIFIED — 3 live reads OK, latencies 268-332ms; error shape captured (malformed-token proxy, not a genuinely revoked one) |
| 4 | `testPreferencesRead` | C3 | `Preferences` read succeeds; shape of `AccountingInfoPrefs`, tax-mode fields, `BookCloseDate` presence. | ✅ VERIFIED — read OK; `BookCloseDate` absent (no close date set yet, expected); AST tax mode confirmed on |
| 5 | `testAccountsRead` | 1.2 | Full COA read; classification/type/subtype fidelity against §4.6's enum. | ✅ VERIFIED — 92 accounts, all `AccountType` values map cleanly to our enum |
| 6 | `testPurchasesRead` | 3.1 (subset) | Read `Purchase` for a bounded window; field completeness against §4.7's `LedgerTransaction`. Needs `baseline.json` seeded. | ✅ VERIFIED (Purchase only, of the ×8 TXN profile) — 15 read, no missing fields, no `cleared` field found (confirms §4.7's `.unknown` default) |
| 7 | `testPaginationOffsetIntegrity` | §2.6 | Seed >2 pages of `Purchase` (needs the seeding harness); mutate the set mid-sweep (insert/delete); assert whether rows are skipped or duplicated. **This is the correctness bug, not a formality — run it, don't skip it.** | ✅ VERIFIED — **the bug reproduces.** A never-deleted record was silently skipped after deleting an earlier one mid-sweep. See §2.6 in the matrix. |
| 8 | `testPaginationChecksum` | §2.6 | `COUNT` query vs. rows collected; confirm mismatch is detectable and drives `Coverage.partial`. | ✅ VERIFIED — `COUNT` supported, matched full sweep exactly (50=50) |
| 9 | `testCDCSince` | C5 | Supported entity list (observed, not documented); lookback boundary at 29/30/31 days; tombstone shape; behavior past the window (error vs. silent truncation — assume the dangerous one until disproven). | ⚠️ VERIFIED-PARTIAL — endpoint reachable, correct shape, near-term only. 30-day boundary/tombstone/overflow behavior still ASSUMED (needs real elapsed time) |
| 10 | `testRateLimitThreshold` | §2.5 | Drive to 429; record threshold, `Retry-After` behavior, which endpoints are metered. | ⚠️ Inconclusive by design — no 429 in 40 requests; deliberately didn't push a sandbox further to find the ceiling |
| 11 | `testBaselineReports` | 1.3, 8.1–8.3, 12.1–12.4 | BS, P&L, TB, GL, Transaction List — read succeeds; column binding by `ColTitle`/`ColType` (§4.9), never index. | ✅ VERIFIED — all 5 reports read OK with complete `ColTitle`/`ColType` on every column (CashFlow, Aged* reports not in this test — still ASSUMED) |

---

## Wave 3 — the writes (moved ahead of the negatives; owner decision 2026-08)

Exit condition: write machinery proven, including the `UNKNOWN`/timeout
recovery path. Items 1–2 already ran above.

⚠ **Failure injection NOT performed this run.** The original plan called
for every write test to run twice — once normally, once with an injected
timeout after send, per §12.7. That did not happen: all 13 tests below ran
only in the normal path. The `UNKNOWN`-state / resolution-probe machinery
(§10.6) remains unexercised against a real timeout. Flagging this
explicitly rather than letting the table below imply more coverage than
actually happened.

| # | Test | Matrix row | Notes | Result (2026-08-16) |
|---|---|---|---|---|
| 12 | `testAccountCreate` | 6.2 | | ✅ VERIFIED — created cleanly |
| 13 | `testAccountEditNameOnly` | 6.3 | | ✅ VERIFIED — renamed cleanly, `AccountType` survived. Type mutability post-posting still untested. |
| 14 | `testAccountDeactivateZeroBalance` | 6.4 | | ✅ VERIFIED — clean, no error |
| 15 | `testAccountDeactivateNonZeroBalance` | 6.4 | ⚠ material — QBO's UI creates an adjusting entry on deactivate-with-balance; confirm whether the API does the same, refuses, or strands it. Needs `edge-cases.json`. Do not build the deactivate path until this returns. | ⚠ VERIFIED-PARTIAL — succeeds without error; no adjusting JE found; account renamed `" (deleted)"` (new finding); original transactions untouched; `CurrentBalance` reports 0 but a real Trial Balance read wasn't done. **Not yet safe to call this path verified-safe.** |
| 16 | `testPurchaseSparseUpdateAccountRef` | 7.1 | Also assert unrelated fields (`PrivateNote`, `DocNumber`, `Memo`) survive — the constraint that matters (§2 row 7.1). **Gates the entire batch-fix machinery.** | ❌ **DISPROVEN** — `DocNumber`/`PrivateNote` survived, but the line's `Description` (memo) was silently cleared. Sparse ≠ sparse at the line level. |
| 17 | `testBillSparseUpdateLine` | 7.2 | Specifically test whether a line-level change requires resending the full `Line` array (§2 row 7.1, constraint 2). | ❌ **DISPROVEN** — sending 1 of 2 lines silently dropped line 2. Not rejected — accepted and truncated. |
| 18 | `testBatchPartialFailure` | C6 | 10-item batch, deliberately include one invalid item; confirm per-item fault isolation. | ✅ VERIFIED — 9 succeeded, 1 faulted, cleanly isolated |
| 19 | `testAttachableUpload` | C7 | | ⚠ VERIFIED-PARTIAL — metadata + entity linkage works (needs a `Note` field); binary upload endpoint not tested |
| 20 | `testJournalEntryCreate` | 8.4 | | ✅ VERIFIED |
| 21 | `testTransferCreate` | 8.6 | | ✅ VERIFIED |
| 21a | `testBillVoid` *(added, Decision 3)* | 11.x-bill | Does void work on `Bill`? | ❌ DISPROVEN, anomalously — HTTP 200 with a `SystemFault` body |
| 21b | `testJournalEntryVoid` *(added, Decision 3)* | 11.x-je | Does void work on `JournalEntry`? | ❌ DISPROVEN, ambiguously — HTTP 200, empty body, no signal at all |
| 21c | `testBillPaymentVoid` *(added, Decision 3)* | 11.x-bp | Does void work on `BillPayment`? | ❌ DISPROVEN, cleanly — same shape as Purchase |

---

## Wave 2 — the negatives (moved behind the writes; owner decision 2026-08)

Exit condition: every Type B/C page's fallback is justified by a recorded
negative, not by assertion in this document. Each test records **what was
searched**, per §12.5's negative-evidence pattern. **Still runs before any
Type B/C page ships** — these just don't block the slice or the write
machinery anymore.

| # | Test | Matrix row |
|---|---|---|
| 22 | `testQBOAClientListUnavailable` | 1.5 |
| 23 | `testFilingStatusUnavailable` | 2.4 |
| 24 | `testBooksReviewUnavailable` | 3.4 |
| 25 | `testTransactionReviewAnomaliesUnavailable` | 3.5 |
| 26 | `testBooksCloseProgressUnavailable` | 3.6 |
| 27 | `testForReviewQueueUnavailable` | 4.2 |
| 28 | `testBankRulesUnavailable` | 4.3 |
| 29 | `testExcludedItemsUnavailable` | 4.4 |
| 30 | `testMatchSuggestionsUnavailable` | 4.5 |
| 31 | `testStatementBalanceUnavailable` | 5.2 |
| 32 | `testReconciliationHistoryUnavailable` | 5.3 |
| 33 | `testFinishUndoReconciliationUnavailable` | 5.4 |
| 34 | `testAccountMergeUnavailable` | 6.5 |
| 35 | `testReclassifyToolUnavailable` | 7.6 |
| 36 | `testPayrollCorrectionUnavailable` | 7.7 |
| 37 | `testTaxFilingStatusUnavailable` | 9.5 |
| 38 | `testTaxCenterAdjustmentsUnavailable` | 9.6 |
| 39 | `testActualTaxLiabilityUnavailable` | 10.2 |
| 40 | `testBooksCloseExecutionUnavailable` | 11.2 |

---

## Wave 4 — the awkward ones (special sandbox setup required)

Exit condition: Pages 2, 5, 9, 11 have honest completion criteria. These need
sandbox state that must be created by hand first — **write the setup procedure
into a checked-in runbook as you go**, per §12.6, since it will be needed again
on a fresh sandbox.

| # | Test | Matrix row | Setup needed first |
|---|---|---|---|
| 41 | `testBookCloseDateRead` | 2.1 | Set a closing date in the sandbox UI, with and without a password |
| 42 | `testBookCloseDateWrite` | 2.2 | Attempt via `Preferences` sparse update either way — record the result, don't assume it fails |
| 43 | `testClosedPeriodRejectionCodes` | 2.3 | Requires 41 done first. Attempt a write dated inside the closed period; capture exact fault code/message, with and without password set, across ≥2 entity types. Needs `closed-period.json`. |
| 44 | `testClearedStatusFilter` | 5.1 | Requires a reconciled or partially-reconciled account — needs `reconciliation.json` |
| 45 | `testTaxModeDetection` | 9.1 | Sandbox company configured for **Automated Sales Tax** (per Q5 — legacy mode is out of scope, don't bother setting it up) |
| 46 | `testTaxCodeShapeAST` | 9.1, 9.3 | Same setup as 45 |
| 47 | `testWebhookDelivery` | C4 | **Deferred per Q2** — CDC-polling-only ships first. Run this when webhooks are picked back up, not before. Needs a reachable public HTTPS endpoint; capture legacy envelope vs. CloudEvents, self-echo behavior (whether our own writes trigger a notification — needed for `intentID` suppression, §6.4), signature verification. |
| 48 | `testReportParityBS` | 12.5 | Generate a Balance Sheet via API and in the QBO UI for the same period; compare numbers (must tie) and layout (won't) |

---

## ✅ Wave 5 — all three items (49-51) run 2026-08-17

Items 49-50 pulled forward from `docs/backlog/CLEANUP_MODE.md` §2.7 and
`docs/backlog/REDDIT_FEEDBACK_ASSESSMENT.md` item 6 (`NEXT_INSTRUCTION.md`
Part 4, 2026-08-16) — filed as queue items only, not run at the time.
**Approved and run 2026-08-17** (owner: "go on and run spike items 49/50").
Item 51 needed the owner to manually void Purchase #151 in the sandbox UI
first — done the same day, then verified. `backend/spike/runWave5.ts`,
`backend/spike/tests/11-categorization-provenance.spike.ts`,
`12-reconciled-transaction-detection.spike.ts`,
`13-manual-void-purchase-shape.spike.ts`. Fixtures:
`backend/spike/fixtures/results-2026-08-17T16-06-42-317Z.json` (49-50) and
`results-2026-08-17T16-33-01-191Z.json` (51). Matrix regenerated — new rows
13.1/13.2/13.3, `docs/phase-0/02_QBO_CAPABILITY_MATRIX.md`.

| # | Test | Matrix row | Asserts | Result (2026-08-17) |
|---|---|---|---|---|
| 49 | `testCategorizationProvenance` | 13.1 | Is QBO's rule-vs-AI-vs-human categorization source exposed via any read API (transaction detail, CDC, or report)? Source: Hector Garcia's walkthrough showed QBO's own UI stating "100% a guess, no historical transactions" per-transaction — the question is whether that provenance is reachable outside the UI. If yes: an enormous cleanup filter (sort the whole file by "categorized by a guess"). If no: record as DISPROVEN — still a useful, permanent answer, not a failure to work around. | ❌ **DISPROVEN** — checked across a `Purchase` query (35 keys), `cdc` (93 keys), and `TransactionList` report columns; none of 12 candidate field names present anywhere. The cleanup-filter idea in `CLEANUP_MODE.md` §2.7 has no API path — closed, not just unimplemented. |
| 50 | `testReconciledTransactionDetection` | 13.2 | Can we tell from the API whether a transaction has already been reconciled? Source: `REDDIT_FEEDBACK_ASSESSMENT.md`'s sensitive-write-preflight risk-tier proposal — a write against an already-reconciled transaction breaks that reconciliation, and §10.3's five preflight checks don't currently check for this. Needed before any write-risk-tiering work, not needed for the Phase 1 slice (Branch B makes no write at all, §11.1). If yes: which field/endpoint, and whether it's per-line or per-transaction. If no: record as DISPROVEN; the preflight risk-tier design would need a different signal (e.g., cross-referencing an imported reconciliation report). | ❌ **DISPROVEN, with a caveat** — same three-surface check, 8 candidate names, none found. **But no seed data in this sandbox has ever been through a real Finish Reconciliation**, so this only confirms the field is absent on an *unreconciled* transaction — a field that only appears once reconciled would still be missed. Genuinely needs Wave 4 item 44 (`testClearedStatusFilter`, `seeds/reconciliation.json` already exists) before this can be called fully closed. |
| 51 | `testManualVoidPurchaseAPIShape` *(added during Phase 1 step 1.6's build, 2026-08-16)* | 13.3 | What does the API read of a `Purchase` look like after it's voided **manually in the QBO UI** (as opposed to `?operation=void`, already confirmed unsupported — §11.1)? | ✅ **VERIFIED (2026-08-17).** The owner manually voided Purchase #151 in the live sandbox UI. Real signal found: a top-level **`"status": "Voided"`** field, present only on voided Purchases (absent entirely — not `false`, not `null` — on every non-voided Purchase, including the #146 control fixture that broke the earlier `TotalAmt == 0` heuristic). `QBORawPurchase.swift`'s `isVoided` now decodes this field. Confirmed end-to-end: a `sync-check` run immediately after showed #151 as `voided=true`, and the `VL-DUP-EXP-001` finding for #145/#151 disappeared — resolved via the `isVoided` exclusion, zero QBO writes made by Voice Ledger. Branch B's full resolution path is now proven against real data, not just fixtures. See matrix row 13.3 for the full before/after JSON. |

---

## ✅ Live verification, 2026-08-17 — the slice's rule engine run against real sandbox data

Not a formal queue item — a direct check that Phase 1 step 1.6's build
actually works against the connected sandbox, not just offline fixtures.
`voiceledger-devtool sync-check 2026 7` against realm `9341456442848752`:

- Health check genuinely green: 2101ms, live, not cached.
- 10 real `Purchase` records synced and normalized correctly (vendor, date,
  amount, account, DocNumber all matched the seed data exactly).
- `VL-DUP-EXP-001` fired correctly: Purchase #145/#151 ($486.20, same
  date/account, differing DocNumbers 4471/4471-DUP) matched **T1 at
  `.high`** — the documented §11.4 worked example, confirmed against real
  data, not just the offline test suite. Purchase #153/#154 (Odessa Water,
  $120, 2 days apart) matched **T3 at `.medium`** — an unplanned but correct
  real-data confirmation of the near-date tier, from a fixture built for a
  different purpose (§11.5 acceptance criterion 3). The near-miss fixture
  (#152, same $486.20, different vendor) correctly produced no finding.
- **Also found a real bug this way, not by inspection:** Purchase #146 (the
  `VL-SPIKE-ZERO` $0 edge-case fixture) was misclassified `isVoided: true`
  by the sync layer's `TotalAmt == 0` heuristic — see item 51 above, now
  fixed (hardcoded `false` pending a real signal).

This was the first time any part of the vertical slice ran against the real
sandbox rather than synthetic fixtures. At the time, it did not close item
51 (no manual void had been performed yet) — **that gap closed the same
day**, see the Wave 5 section above and matrix row 13.3. UI rendering
verification (no screenshot tool available) remains the one open item from
this note, still documented in `docs/VOICE_LEDGER_HANDOFF.md` §13.

---

## After the queue runs

1. Regenerate `02_QBO_CAPABILITY_MATRIX.md` from the passing tests (§12.5 — not
   hand-edited).
2. Any `DISPROVEN` row blocks its dependent feature automatically — check
   `CAPABILITY_CLASSIFICATION.md` for what moves from 🟢/🟡 to 🔧/⛔.
3. Item 1's result (`testPurchaseVoid`) determines which branch of
   `11_VERTICAL_SLICE.md` §11.1 to build. Confirm the branch before starting
   slice implementation.
4. Item 2's result (`testIdempotencyKeySupport`) determines whether §10.5's
   idempotency design treats QBO's own guarantee as primary or as a backstop
   behind the resolution probe.
5. Item 15's result determines whether the Page 6 deactivate path is safe to
   build as designed, or needs the adjusting-entry case handled first.
6. Items 41–43 determine whether Page 2/11's closing-date UX can offer an
   API-settable close date (upgrade) or stays guided-manual as designed.
