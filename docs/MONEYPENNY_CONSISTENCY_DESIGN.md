# Design: one set of facts for pages, Moneypenny, and regression checks
Written 2026-09-30 (Fable review). Owner priorities: (3) Moneypenny computes the same as the pages,
(4) cached-vs-synced state never looks like a bug, (6) a fix in one place can't silently change a number elsewhere.
Sandbox path only for now. This is a design; implement in the order given, one step per commit.

## What's wrong today (verified in code)

### Moneypenny (VoiceToolExecutor / VoiceToolDefinitions / VoiceToolLoop)
1. `search_transactions` is a second, weaker search engine. It searches only the current month
   (`appState.transactions`), matches amounts by `Money.description.contains(query)` ("$500" never
   matches "USD 500.00"), and its description promises date search ("January") that doesn't exist.
   The Search by Amount page (v1.26+) searches current + 24-month history with exact-cents parsing,
   balance explanation, and 2–3-part sums. Two engines → two answers.
2. `get_account_balance` never returns a balance ("Sync dashboard for real-time balance details")
   even though `LedgerAccount.currentBalance` is loaded and shown on pages.
3. `get_report_summary("cash_flow")` returns a transaction count, not the Cash Flow report
   (`appState.cashFlowLines` exists).
4. `get_vendor_details` uses the current month only; Recurring Vendors uses `trailingPurchases`.
5. Money is spoken as `Money.description` ("USD 315.00"); pages show `accountingDescription` ("$315.00").
   The system prompt tells the model to quote figures exactly, so it says "USD".
6. `find_findings` keeps its own category → rule-ID lists; pages use `AppState.cleanupAssessmentRuleIDs`
   / `balanceSheetIntegrityRuleIDs`. Two lists drift.
7. `get_sync_status` says "hasn't been synced yet this session" while the page strip says
   "Cached from last sync 2 hours ago". Same state, two stories.
8. `VoiceDestination` (what `navigate` can reach) is missing: amountSearch, diagnostics, intakeQuestions,
   pricingCalculator, connection, scopeAndPeriodLock, voiceHistory, audioSettings.
9. `currentPageAskAIContext()` describes 14 of 33 screens; the rest hit `default`, so on Cleanup Assessment,
   Balance Sheet Integrity, Bank Feed Cleanup, Close Package, Month-End Close, Trial Balance and the
   Cash Flow report, Moneypenny doesn't know what's on screen.

### Cached vs synced
- `coverage` starts `.partial("not synced yet")`; disk load sets `cachedSyncedAt`; only the Dashboard
  strip translates that into "Cached from last sync …". Each page invents its own empty state
  ("No report loaded yet. Tap Refresh", "Nothing loaded to search yet", "Insufficient information").
- Nothing syncs on launch, so the first minutes of every session run on stale data and every page
  looks broken until the user finds Sync.
- The 24-month history is needed by Search, Client Diagnostics, cleanup quote and Recurring Vendors,
  but only loads when a page asks.

### Regression safety
- 633 unit tests cover rules in isolation. `voiceledger-devtool sync-check` prints text; nothing
  compares one run to the last. A change in `flatten`, aging dates, or a rule threshold can move a
  number on a page with no test failing (today's "(other)" postings bug is the example).

## The fix: a `ClientFacts` layer with three consumers

One module of pure functions — `Sources/Core/ClientFacts/` — that turns already-loaded data
(report lines, transactions, accounts, findings, history) into typed answers. **Pages, Moneypenny and
the regression tool all call the same functions.** No consumer computes anything itself.

```swift
public struct FactScope: Codable, Equatable {      // stated with every answer
    public let period: AccountingPeriod            // which month
    public let source: Source                      // .currentSync, .history24Months, .balanceSheetAsOf(date)
    public let freshness: Freshness                // .synced(at) / .cached(at) / .notLoaded
}
public struct Fact<Value: Codable>: Codable { public let value: Value?; public let scope: FactScope; public let note: String? }

public enum ClientFacts {
    // KPIs (already FinancialKPIs — wrap, don't rewrite)
    static func cashBalance(_ d: ClientData) -> Fact<Money>
    static func netIncome(_ d: ClientData, period: PeriodChoice) -> Fact<Money>
    static func workingCapital / currentRatio / quickRatio / grossMargin / netMargin
    // Balances & accounts
    static func accountBalance(_ d: ClientData, name: String) -> Fact<AccountBalance>   // name, type, currentBalance, register link
    static func chartOfAccounts(_ d: ClientData, type: AccountFilter) -> Fact<[AccountBalance]>
    // Search (move AmountSearch + the v1.29 balance/combination logic here)
    static func search(_ d: ClientData, amount: Money) -> Fact<AmountSearchResult>
    static func search(_ d: ClientData, text: String) -> Fact<[LedgerTransaction]>       // vendor/memo, current+history
    static func vendor(_ d: ClientData, name: String) -> Fact<VendorSummary>            // uses trailingPurchases like the page
    static func vendorsBySpend(_ d: ClientData, limit: Int) -> Fact<[VendorSpend]>
    // Reports
    static func reportSummary(_ d: ClientData, kind: ReportKind) -> Fact<[ReportLine]>  // BS, P&L, cash flow, TB, aging
    static func aging(_ d: ClientData, side: .receivable/.payable) -> Fact<AgingSplit>   // owed / credits / over60
    // Findings (the page constants become the only lists)
    static func findings(_ d: ClientData, category: FindingCategory) -> Fact<[Finding]>
    static func openItems(_ d: ClientData) -> Fact<ReportStatus.Summary>                 // same as monthly report
    static func totalExposure(_ d: ClientData, page: FindingsPage) -> Fact<Money>         // Cleanup Assessment header
    // Forecast / recurring: wrap existing CashFlowForecast / RecurringVendorDetector
    // Status
    static func freshness(_ d: ClientData) -> Freshness   // ONE sentence used by the strip, every page, and Moneypenny
}
```
`ClientData` is a plain value built from `AppState` (and, in the devtool, from a sync) — no AppState
dependency inside Core, so the devtool can call the same code.

### Consumer 1 — pages
- Views stop doing `.filter{}.reduce{}` on their own (CleanupAssessmentView exposure total,
  BalanceSheetIntegrityView counts, AmountSearchView). They call `ClientFacts` through AppState.
- `currentPageAskAIContext()` is generated from the same `ClientFacts` calls each page renders, for
  **every** `Screen` case (no `default`). Rule: if a number is on screen, it's in the page context.

### Consumer 2 — Moneypenny
- `VoiceToolExecutor` becomes an adapter: parse arguments → `ClientFacts` → format. It contains no
  filtering, matching, or arithmetic. Every reply ends with the scope sentence
  ("…for July 2026, synced 12 minutes ago" / "…from the 24-month history").
- One formatter: `ClientText` / `accountingDescription`. Never `Money.description` in spoken text.
- `search_transactions` calls the same search as the page (amount or text); description rewritten to
  match what it does. `get_account_balance` returns the balance. `get_report_summary` covers all
  report kinds the pages have. `find_findings` uses the page rule-ID constants.
- `VoiceDestination` = every `Screen` a user can reach from the sidebar (add the 8 missing).
- `get_sync_status` returns `ClientFacts.freshness` verbatim — same sentence as the strip.
- System prompt: drop "fetch live QuickBooks data on demand" (tools read loaded data); add the
  freshness sentence at the top of every turn's context.

### Consumer 3 — regression tool
- `voiceledger-devtool facts <year> <month> [--as-of YYYY-MM-DD] [--out file.json]` syncs the sandbox
  exactly as the app does, builds `ClientData`, and writes every `ClientFacts` answer plus every
  finding (rule, title, amount, evidence IDs) as sorted JSON with no timestamps.
- `voiceledger-devtool facts-diff baseline.json current.json` prints: findings appeared / disappeared /
  changed amount; facts changed (old → new); page-context strings changed. Exit code 1 on any diff.
- Baselines live in `desktop/Regression/<realm>-<period>.json`, committed. `Scripts/preflight.sh` =
  `swift test` + `facts 2026 8` + `facts-diff`; `build-app-bundle.sh release` refuses to build when
  preflight fails unless `--accept-baseline` is passed (which rewrites the baseline after a human
  read the diff). Freeze "today" with `--as-of` so day-count rules (aging, Undeposited Funds days)
  don't drift between runs.
- A unit test asserts, on a fixture `ClientData`, that each Moneypenny tool's structured result equals
  the `ClientFacts` answer (tools return `(facts: [String: Any], text: String)`; the test compares
  facts, not prose).

## Cached-vs-synced, made boring
- `AppState.freshness: Freshness` — `.neverSynced`, `.cached(at)`, `.syncing(started)`, `.synced(at)`,
  plus `historyLoaded: Bool`. Derived once; every page reads it.
- **On launch:** if `.cached` and older than 15 minutes (same rule as Generate Report), start
  `syncAndEvaluate()` automatically with the strip showing "Syncing…". Then load the 24-month
  history in the background. The user should almost never see "Cached".
- One shared `DataStateNotice` view replaces every hand-written empty state. It always says which
  of three things is true — not synced / synced, nothing to show / exists but not loaded here — and
  shows the one button that fixes it (Sync / Load history / Refresh). Search, Aged Payables,
  Reporting Confidence, Diagnostics all use it.
- A report page never shows a blank table: while loading, show "Loading July 2026 Balance Sheet…";
  on failure, the error and a Retry button.

## Order of work (each step = build, tests, one screenshot, commit)
1. `ClientFacts` for search, account balance, vendor, reports, findings categories, freshness —
   wrap existing Core functions; move AmountSearch logic in. Pages switch to it. (No visible change.)
2. Moneypenny adapter rewrite on top of step 1 + missing destinations + full page context +
   formatter. Verify with 8 spoken questions against the sandbox, compare to the page.
3. Freshness model + auto-sync on launch + `DataStateNotice` on the six pages that have custom
   empty states.
4. `facts` / `facts-diff` devtool commands, baseline for 2026-07 and 2026-08, `preflight.sh`,
   build script gate, consistency unit test.

Not in scope now: real-client/production path, backend deployment, hosted signing.
