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

| # | Test | Matrix row | Asserts |
|---|---|---|---|
| **1** | `testPurchaseVoid` | 11.x (slice gate) | Create a `Purchase` in sandbox, void it via `?operation=void`. Record: HTTP status, response body, whether the record survives, whether `TotalAmt` becomes 0, whether `SyncToken` increments, whether it still appears in `TransactionList`, whether it can be un-voided, Balance Sheet before/after. **Output determines Branch A vs. Branch B for the entire vertical slice (§11.1).** |
| **2** | `testIdempotencyKeySupport` | §10.5 | Determine whether QBO accepts a caller-supplied idempotency key on the write operations in our catalog. If so: record the header/parameter name, the retention window, and behavior on a repeated key (returns the original result vs. errors vs. silently duplicates). If not: record as a negative, with what was searched. **This sits underneath the entire `UNKNOWN`-state recovery design** (§10.6) — the resolution probe works either way, but the answer determines whether the probe is the primary mechanism or a fallback behind QBO's own idempotency guarantee. |

Do not proceed to slice-adjacent design work until item 1 returns.

---

## Wave 1 — read surface (unblocks read-only sync)

Exit condition: a full read-only sync of a seeded sandbox, reproducible and
checksum-clean.

| # | Test | Matrix row | Asserts |
|---|---|---|---|
| 3 | `testCompanyInfoHealthCheck` | C1 | Live, timestamped, non-cached. Latency distribution. Whether it counts against CorePlus metering. Exact error shape on a revoked token. |
| 4 | `testPreferencesRead` | C3 | `Preferences` read succeeds; shape of `AccountingInfoPrefs`, tax-mode fields, `BookCloseDate` presence. |
| 5 | `testAccountsRead` | 1.2 | Full COA read; classification/type/subtype fidelity against §4.6's enum. |
| 6 | `testPurchasesRead` | 3.1 (subset) | Read `Purchase` for a bounded window; field completeness against §4.7's `LedgerTransaction`. Needs `baseline.json` seeded. |
| 7 | `testPaginationOffsetIntegrity` | §2.6 | Seed >2 pages of `Purchase` (needs the seeding harness); mutate the set mid-sweep (insert/delete); assert whether rows are skipped or duplicated. **This is the correctness bug, not a formality — run it, don't skip it.** |
| 8 | `testPaginationChecksum` | §2.6 | `COUNT` query vs. rows collected; confirm mismatch is detectable and drives `Coverage.partial`. |
| 9 | `testCDCSince` | C5 | Supported entity list (observed, not documented); lookback boundary at 29/30/31 days; tombstone shape; behavior past the window (error vs. silent truncation — assume the dangerous one until disproven). |
| 10 | `testRateLimitThreshold` | §2.5 | Drive to 429; record threshold, `Retry-After` behavior, which endpoints are metered. |
| 11 | `testBaselineReports` | 1.3, 8.1–8.3, 12.1–12.4 | BS, P&L, TB, GL, Transaction List — read succeeds; column binding by `ColTitle`/`ColType` (§4.9), never index. |

---

## Wave 3 — the writes (moved ahead of the negatives; owner decision 2026-08)

Exit condition: write machinery proven, including the `UNKNOWN`/timeout
recovery path. Items 1–2 already ran above. **Every write test in this wave
runs twice** — once normally, once with an injected timeout after send — per
§12.7's failure-injection requirement.

| # | Test | Matrix row | Notes |
|---|---|---|---|
| 12 | `testAccountCreate` | 6.2 | |
| 13 | `testAccountEditNameOnly` | 6.3 | |
| 14 | `testAccountDeactivateZeroBalance` | 6.4 | |
| 15 | `testAccountDeactivateNonZeroBalance` | 6.4 | ⚠ material — QBO's UI creates an adjusting entry on deactivate-with-balance; confirm whether the API does the same, refuses, or strands it. Needs `edge-cases.json`. Do not build the deactivate path until this returns. |
| 16 | `testPurchaseSparseUpdateAccountRef` | 7.1 | Also assert unrelated fields (`PrivateNote`, `DocNumber`, `Memo`) survive — the constraint that matters (§2 row 7.1). **Gates the entire batch-fix machinery.** |
| 17 | `testBillSparseUpdateLine` | 7.2 | Specifically test whether a line-level change requires resending the full `Line` array (§2 row 7.1, constraint 2). |
| 18 | `testBatchPartialFailure` | C6 | 10-item batch, deliberately include one invalid item; confirm per-item fault isolation. |
| 19 | `testAttachableUpload` | C7 | |
| 20 | `testJournalEntryCreate` | 8.4 | |
| 21 | `testTransferCreate` | 8.6 | |

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
