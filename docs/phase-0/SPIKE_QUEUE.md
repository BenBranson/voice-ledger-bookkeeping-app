# Spike Queue — Ordered, Runnable

The capability spike (§2.8, §12.5) as an execution list rather than a plan.
Each item is a single `@CapabilityTest`, runnable independently, that emits one
matrix row's verdict and one fixture. Run them in this order — later items
assume earlier ones passed, and the ordering puts the highest-consequence
unknowns first.

**Mechanics recap (§12.5):** a row becomes `VERIFIED` only when its test passes
against a live sandbox; the matrix is regenerated from test results, never
hand-edited. `VERIFIED` expires after 90 days.

Prerequisite for all of it: Wave 0 (Intuit developer account, sandbox company,
OAuth round trip, backend token refresh, environment badge visually proven) must
be done first. Not listed as a numbered item because it's setup, not a
capability test — but nothing below runs without it.

---

## 0. The gate — run before anything else in this queue

Everything downstream of the vertical slice branches on this one test
(§11.1). Running it first means the rest of the queue — and the Phase 1 plan
for the slice's write path — is scoped correctly from day one instead of
discovered mid-build.

| # | Test | Matrix row | Asserts |
|---|---|---|---|
| **1** | `testPurchaseVoid` | 11.x (slice gate) | Create a `Purchase` in sandbox, void it via `?operation=void`. Record: HTTP status, response body, whether the record survives, whether `TotalAmt` becomes 0, whether `SyncToken` increments, whether it still appears in `TransactionList`, whether it can be un-voided, Balance Sheet before/after. **Output determines Branch A vs. Branch B for the entire vertical slice (§11.1).** |

Do not proceed to slice-adjacent design work until this returns. Everything
else in this queue can proceed in parallel with slice design regardless of its
outcome.

---

## Wave 1 — read surface (unblocks read-only sync)

Exit condition: a full read-only sync of a seeded sandbox, reproducible and
checksum-clean.

| # | Test | Matrix row | Asserts |
|---|---|---|---|
| 2 | `testCompanyInfoHealthCheck` | C1 | Live, timestamped, non-cached. Latency distribution. Whether it counts against CorePlus metering. Exact error shape on a revoked token. |
| 3 | `testPreferencesRead` | C3 | `Preferences` read succeeds; shape of `AccountingInfoPrefs`, tax-mode fields, `BookCloseDate` presence. |
| 4 | `testAccountsRead` | 1.2 | Full COA read; classification/type/subtype fidelity against §4.6's enum. |
| 5 | `testPurchasesRead` | 3.1 (subset) | Read `Purchase` for a bounded window; field completeness against §4.7's `LedgerTransaction`. |
| 6 | `testPaginationOffsetIntegrity` | §2.6 | Seed >2 pages of `Purchase`; mutate the set mid-sweep (insert/delete); assert whether rows are skipped or duplicated. **This is the correctness bug, not a formality — run it, don't skip it.** |
| 7 | `testPaginationChecksum` | §2.6 | `COUNT` query vs. rows collected; confirm mismatch is detectable and drives `Coverage.partial`. |
| 8 | `testCDCSince` | C5 | Supported entity list (observed, not documented); lookback boundary at 29/30/31 days; tombstone shape; behavior past the window (error vs. silent truncation — assume the dangerous one until disproven). |
| 9 | `testRateLimitThreshold` | §2.5 | Drive to 429; record threshold, `Retry-After` behavior, which endpoints are metered. |
| 10 | `testBaselineReports` | 1.3, 8.1–8.3, 12.1–12.4 | BS, P&L, TB, GL, Transaction List — read succeeds; column binding by `ColTitle`/`ColType` (§4.9), never index. |

---

## Wave 2 — the negatives (unblocks honest UI)

Exit condition: every Type B/C page's fallback is justified by a recorded
negative, not by assertion in this document. Each test records **what was
searched**, per §12.5's negative-evidence pattern.

| # | Test | Matrix row |
|---|---|---|
| 11 | `testQBOAClientListUnavailable` | 1.5 |
| 12 | `testFilingStatusUnavailable` | 2.4 |
| 13 | `testBooksReviewUnavailable` | 3.4 |
| 14 | `testTransactionReviewAnomaliesUnavailable` | 3.5 |
| 15 | `testBooksCloseProgressUnavailable` | 3.6 |
| 16 | `testForReviewQueueUnavailable` | 4.2 |
| 17 | `testBankRulesUnavailable` | 4.3 |
| 18 | `testExcludedItemsUnavailable` | 4.4 |
| 19 | `testMatchSuggestionsUnavailable` | 4.5 |
| 20 | `testStatementBalanceUnavailable` | 5.2 |
| 21 | `testReconciliationHistoryUnavailable` | 5.3 |
| 22 | `testFinishUndoReconciliationUnavailable` | 5.4 |
| 23 | `testAccountMergeUnavailable` | 6.5 |
| 24 | `testReclassifyToolUnavailable` | 7.6 |
| 25 | `testPayrollCorrectionUnavailable` | 7.7 |
| 26 | `testTaxFilingStatusUnavailable` | 9.5 |
| 27 | `testTaxCenterAdjustmentsUnavailable` | 9.6 |
| 28 | `testActualTaxLiabilityUnavailable` | 10.2 |
| 29 | `testBooksCloseExecutionUnavailable` | 11.2 |

---

## Wave 3 — the writes (unblocks the vertical slice's remaining machinery)

Exit condition: write machinery proven, including the `UNKNOWN`/timeout
recovery path. Item 1 already ran (Wave 0 above); this wave covers the rest.
**Every write test in this wave runs twice** — once normally, once with an
injected timeout after send — per §12.7's failure-injection requirement.

| # | Test | Matrix row |
|---|---|---|
| 30 | `testAccountCreate` | 6.2 |
| 31 | `testAccountEditNameOnly` | 6.3 |
| 32 | `testAccountDeactivateZeroBalance` | 6.4 |
| 33 | `testAccountDeactivateNonZeroBalance` | 6.4 | ⚠ material — QBO's UI creates an adjusting entry on deactivate-with-balance; confirm whether the API does the same, refuses, or strands it. Do not build the deactivate path until this returns. |
| 34 | `testPurchaseSparseUpdateAccountRef` | 7.1 | Also assert unrelated fields (`PrivateNote`, `DocNumber`, `Memo`) survive — the constraint that matters (§2 row 7.1). |
| 35 | `testBillSparseUpdateLine` | 7.2 | Specifically test whether a line-level change requires resending the full `Line` array (§2 row 7.1, constraint 2). |
| 36 | `testBatchPartialFailure` | C6 | 10-item batch, deliberately include one invalid item; confirm per-item fault isolation. |
| 37 | `testAttachableUpload` | C7 | |
| 38 | `testJournalEntryCreate` | 8.4 | |
| 39 | `testTransferCreate` | 8.6 | |

---

## Wave 4 — the awkward ones (special sandbox setup required)

Exit condition: Pages 2, 5, 9, 11 have honest completion criteria. These need
sandbox state that must be created by hand first — **write the setup procedure
into a checked-in runbook as you go**, per §12.6, since it will be needed again
on a fresh sandbox.

| # | Test | Matrix row | Setup needed first |
|---|---|---|---|
| 40 | `testBookCloseDateRead` | 2.1 | Set a closing date in the sandbox UI, with and without a password |
| 41 | `testBookCloseDateWrite` | 2.2 | Attempt via `Preferences` sparse update either way — record the result, don't assume it fails |
| 42 | `testClosedPeriodRejectionCodes` | 2.3 | Requires 40 done first. Attempt a write dated inside the closed period; capture exact fault code/message, with and without password set, across ≥2 entity types |
| 43 | `testClearedStatusFilter` | 5.1 | Requires a reconciled or partially-reconciled account in sandbox |
| 44 | `testTaxModeDetection` | 9.1 | Sandbox company configured for **Automated Sales Tax** (per Q5 — legacy mode is out of scope, don't bother setting it up) |
| 45 | `testTaxCodeShapeAST` | 9.1, 9.3 | Same setup as 44 |
| 46 | `testWebhookDelivery` | C4 | **Deferred per Q2** — CDC-polling-only ships first. Run this when webhooks are picked back up, not before. Needs a reachable public HTTPS endpoint; capture legacy envelope vs. CloudEvents, self-echo behavior (whether our own writes trigger a notification — needed for `intentID` suppression, §6.4), signature verification. |
| 47 | `testReportParityBS` | 12.5 | Generate a Balance Sheet via API and in the QBO UI for the same period; compare numbers (must tie) and layout (won't) |

---

## After the queue runs

1. Regenerate `02_QBO_CAPABILITY_MATRIX.md` from the passing tests (§12.5 — not
   hand-edited).
2. Any `DISPROVEN` row blocks its dependent feature automatically — check
   `CAPABILITY_CLASSIFICATION.md` for what moves from 🟢/🟡 to 🔧/⛔.
3. Item 1's result (`testPurchaseVoid`) determines which branch of
   `11_VERTICAL_SLICE.md` §11.1 to build. Confirm the branch before starting
   slice implementation.
4. Item 33's result determines whether the Page 6 deactivate path is safe to
   build as designed, or needs the adjusting-entry case handled first.
5. Items 40–42 determine whether Page 2/11's closing-date UX can offer an
   API-settable close date (upgrade) or stays guided-manual as designed.
