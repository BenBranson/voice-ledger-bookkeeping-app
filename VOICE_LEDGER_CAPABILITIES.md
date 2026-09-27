# Voice Ledger — Capabilities Reference for MCP Integration

**Audience:** an engineer (working on the "Miss Moneypenny" voice assistant) connecting to Voice Ledger over MCP. This document describes what the running system actually does today, not what the product spec aspires to. Every claim below cites the file and function that implements it, and is labeled:

- **TESTED** — a named automated test exercises this behavior; the test is named.
- **SANDBOX-VERIFIED** — checked against a real QuickBooks Online sandbox company. Where this is a claim from the project's own institutional-memory doc (`docs/VOICE_LEDGER_HANDOFF.md`) rather than something re-run during the writing of this document, that is stated explicitly — treat those as project self-report, not independently reproduced.
- **UNTESTED** — implemented, builds, but has no automated test and no sandbox verification on record.

Where this document's own findings contradict the project's institutional memory (`docs/VOICE_LEDGER_HANDOFF.md`), that memory doc is stale on the specific point noted, not this document.

As of this writing: **all 774 desktop tests pass** (`swift test`, run in `desktop/`, exit 0, verified during the writing of this document) and **all 91 backend tests pass** (`npm test` in `backend/`, run via `vitest`, verified during the writing of this document).

---

## 1. Overview

Voice Ledger is a native macOS SwiftUI app that runs as a bookkeeper's workpaper layer on top of QuickBooks Online (QBO), which remains the client's system of record (`docs/VOICE_LEDGER_HANDOFF.md` §1). It ships as three separate processes, started together by a launcher app:

1. **The desktop app** (`VoiceLedgerApp`, SwiftUI) — the UI, local `ClientStore` persistence, the rules engine.
2. **The thin backend** (`backend/`, Node/Express/TypeScript) — the only process that holds the QBO client secret, AI provider API keys, and refresh tokens. Deploys to Render (`docs/VOICE_LEDGER_HANDOFF.md` §4).
3. **`voice-service`** (Python, faster-whisper + Piper, FastAPI) — local speech-to-text/text-to-speech for the in-app voice assistant, unrelated to the MCP server below (`docs/VOICE_LEDGER_HANDOFF.md` §D8).

There is a fourth, separate executable relevant to MCP integration: **`voiceledger-mcp`** (`desktop/Sources/VoiceLedgerMCP/`), a small stdio MCP server that exposes a read-only slice of one client's already-computed data. It is a distinct target from the desktop app (`desktop/Package.swift`: `.executable(name: "voiceledger-mcp", targets: ["VoiceLedgerMCP"])`) and reads the same on-disk `ClientStore` the desktop app writes — not a separate copy (`desktop/Sources/VoiceLedgerMCP/main.swift:49-58`).

### QBO authentication

- OAuth is a standard authorization-code exchange, entirely server-side (`backend/src/routes/oauth.ts`, `backend/src/auth/oauth.ts`). `GET /oauth/authorize` redirects to Intuit with a CSRF `state` token (10-minute TTL, in-memory map) (`backend/src/routes/oauth.ts:21-32`). `GET /oauth/callback` validates `state`, exchanges the code, and stores the refresh token.
- **Refresh tokens** are encrypted at rest with **AES-256-GCM** (`backend/src/auth/crypto.ts:13`, 96-bit IV, key from the `TOKEN_ENCRYPTION_KEY` env var, no hardcoded fallback) and stored in SQLite, one row per `realmId` (`backend/src/auth/tokenStore.ts:71-111`). TESTED: `backend/test/tokenStore.test.ts` (15 tests) — encrypt/decrypt round-trip, write-access flag persistence, access-token cache TTL.
- **Access tokens** are cached in-process memory only, never persisted, refreshed ~60 seconds before real expiry (`backend/src/auth/tokenStore.ts:173-191`).
- Refresh is serialized per `realmId` so a crash between "wrote the new token" and "discarded the old" can't race a second concurrent refresh (`backend/src/auth/tokenStore.ts:193-204`).
- **Sandbox vs. production** is a property of the connection record, resolved once at connect time from which credential set authorized it, never a global flag (`backend/src/qbo/environment.ts:1-20`). Production credentials are only ever returned if **both** `ALLOW_PRODUCTION=true` **and** `QBO_PRODUCTION_CLIENT_ID`/`QBO_PRODUCTION_CLIENT_SECRET` are set (`backend/src/config.ts:65-96`); otherwise the resolver can only ever produce sandbox credentials. TESTED: `backend/test/productionGuard.test.ts` (14 tests), e.g. "defaults to sandbox even if production env vars happen to be present but ALLOW_PRODUCTION is unset."
- App sessions are opaque 32-byte random bearer tokens (not JWTs), only their SHA-256 hash is stored, 12-hour TTL, bound to exactly one `realmId` at creation and never widened (`backend/src/auth/session.ts`). TESTED: `backend/test/session.test.ts` (4 tests).
- **QBO has no read-only OAuth scope** — `com.intuit.quickbooks.accounting` grants read and write together. Voice Ledger self-enforces read-only by construction: see §3.

---

## 2. MCP server

Source: `desktop/Sources/VoiceLedgerMCP/main.swift`, `MCPDispatcher.swift`, `VoiceLedgerTools.swift`. Target name: `voiceledger-mcp`.

### Transport and launch

Stdio JSON-RPC 2.0 — one JSON message per line, UTF-8, no `Content-Length` framing (`main.swift:6-8`). All diagnostics go to **stderr**; stdout carries only JSON-RPC response lines (`main.swift:29-35`) — this is load-bearing, since a stray stdout write would corrupt the protocol stream.

Launch command and environment:

```
VOICE_LEDGER_REALM_ID=<realmId> \
VOICE_LEDGER_ENVIRONMENT=sandbox \
VOICE_LEDGER_BACKEND_URL=https://your-backend.example.com \
VOICE_LEDGER_SESSION_TOKEN=<token> \
swift run voiceledger-mcp
```

- `VOICE_LEDGER_REALM_ID` — **required**. Missing → logs to stderr and exits with code 2 (`main.swift:37-40`).
- `VOICE_LEDGER_ENVIRONMENT` — optional, defaults to `"sandbox"`. Only the literal string `"production"` selects production; anything else (including typos) silently resolves to sandbox (`main.swift:46-47`) — worth being precise about this string when a caller configures it.
- `VOICE_LEDGER_BACKEND_URL` / `VOICE_LEDGER_SESSION_TOKEN` — both optional. `get_open_findings` needs neither (local-data only). `get_client_status` degrades gracefully to local-only data without them (`main.swift:21-23`, `VoiceLedgerTools.swift:172-187`).

Registration example given in the source itself: `claude mcp add voiceledger --env VOICE_LEDGER_REALM_ID=<realmId> -- swift run --package-path <path-to-desktop> voiceledger-mcp` (`main.swift:25-27`).

### JSON-RPC methods (`MCPDispatcher.swift`)

| Method | Behavior |
|---|---|
| `initialize` | Returns `{"protocolVersion":"2024-11-05","capabilities":{"tools":{}},"serverInfo":{"name":"voiceledger-mcp","version":"0.1.0"}}` (`:26-31`) |
| `notifications/*` | No response, per JSON-RPC notification semantics (`:37-38`) |
| `ping` | Returns `{}` (`:40-41`) |
| `tools/list` | Returns `{"tools": [...]}` — see below |
| `tools/call` | Requires `params.name`; missing name → JSON-RPC error `-32602` (unless it's itself a notification, then silently dropped) |
| anything else | If it has an `id` (a request): JSON-RPC error `-32601 Method not found: <method>`. If it's a notification: silently dropped. |

Error shape: `{"jsonrpc":"2.0","id":...,"error":{"code":...,"message":...}}` (`MCPDispatcher.swift:63-65`).

**No explicit per-call timeout exists.** The server is a synchronous `while let line = readLine()` loop (`main.swift:70-87`); a tool call that hangs (e.g. a slow/unreachable backend health check) hangs the whole process. A calling client should apply its own timeout.

**No automated test coverage exists for this server at all** — there is no `Tests/` target for `VoiceLedgerMCP`, and no other test file references it. Every claim in this section is **UNTESTED** in the sense of "no unit test proves it," though it is a direct reading of the actual source.

### Tools exposed (all read-only by explicit design)

`VoiceLedgerTools.swift`'s own doc comment (`:6-22`) states the guarantee plainly: "There is deliberately no tool here that can write anything." Every value returned is read straight from what Voice Ledger already computed and persisted — this process never runs a rule, never computes a dollar figure, and never touches QBO directly (it may make one read-only HTTP health check through the backend; see `get_client_status`).

#### `get_open_findings`

- **Input schema:** `{"severity": {"type": "string", "enum": ["high", "low"], "description": "Only return findings at this severity. Omit to return every open finding."}}` — `severity` is optional (`VoiceLedgerTools.swift:41-54`).
- **Behavior:** loads this realm's findings from `ClientStore`, filters to `status == .open`, optionally filters by severity. An invalid severity string throws `ToolArgumentError.invalidSeverity` (`:135-137`).
- **Output shape:** a JSON array of objects: `{"title": String, "ruleId": String, "severity": "high"|"low", "confidence": "low"|"medium"|"high", "dollarExposure": String (e.g. "USD 486.20"), "period": "YYYY-MM"}` (`:148-158`). If nothing matches, returns a plain sentence string instead (e.g. `"No open findings for realm 123456789."`).
- **Read-only:** yes — local `ClientStore` read only.

Example (constructed by this document's author from the schema above — **no fixture exists in code or tests**, so treat this as illustrative, not sourced):

```json
// tools/call request
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_open_findings","arguments":{"severity":"high"}}}

// response
{"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"[{\"title\":\"Possible duplicate expense — Permian Supply, USD 486.20\",\"ruleId\":\"VL-DUP-EXP-001\",\"severity\":\"high\",\"confidence\":\"high\",\"dollarExposure\":\"USD 486.20\",\"period\":\"2026-07\"}]"}],"isError":false}}
```

#### `get_client_status`

- **Input schema:** no properties (`:56-63`).
- **Behavior:** counts open findings and open high-severity findings from local `ClientStore`; if `VOICE_LEDGER_BACKEND_URL` is configured, also makes one live `BackendClient.healthCheck(realmID:)` call — a non-destructive read (`:161-190`).
- **Output shape:** `{"realmId": String, "environment": "sandbox"|"production", "openFindingsCount": Int, "highSeverityFindingsCount": Int, "backendHealth": <object|string>}`. `backendHealth` is one of: a health object `{"status": String, "checkedAt": ISO8601, "latencyMs": Number, "detail": <value or null>}`; the string `"unreachable: <error>"` on failure; or `"not checked — VOICE_LEDGER_BACKEND_URL is not set for this process"` if no backend is configured.
- **Read-only:** yes.

#### `get_cleanup_assessment_summary`

- **Input schema:** no properties.
- **Behavior:** scoped to exactly `CleanupCategory.ruleIDs` — the same rule subset the in-app Cleanup Assessment page evaluates, not every open finding (`:192-233`). Groups by category (Balance Sheet Integrity, Duplicates & Unresolved Items, Categorization & Coding, Vendor & Fee Anomalies).
- **Output shape:** `{"realmId": String, "openFindingCount": Int, "categories": [{"category": String, "findingCount": Int, "totalExposure": String?}], "totalExposure": String?}`. `totalExposure` is **omitted, never fabricated**, when the findings in scope mix currencies (`sumSameCurrency`, `:240-243`) — in practice this never happens today since only USD is modeled anywhere in this codebase (see §4).
- **Read-only:** yes.

#### `get_pricing_quote`

- **Input schema** (verbatim field names): `hourlyRate` (number, required), `volumeTier` (enum `light`|`growth`|`high`, required), `payrollProcessing`/`salesTaxManagement`/`multipleBankAccounts`/`inventoryTracking` (bool, default false), `needsCleanup` (bool, default false), `monthsBehind` (enum `oneToThree`|`threeToSix`|`sixToTwelve`|`twelvePlus`, **required only if `needsCleanup` is true**), and seven more boolean cleanup-issue flags (`multipleUncategorized`, `personalBusinessMixed`, `payrollNotReconciled`, `salesTaxNotFiled`, `inventoryTrackingIssues`, `negativeBalances`, `duplicatedAccounts`), all default false (`:74-97`).
- **Behavior:** the only tool that does no I/O at all — pure arithmetic via `Core.PricingCalculator`, the exact same module the in-app Pricing Calculator page calls, so it cannot drift from what a bookkeeper sees on screen (`:245-249`).
- **Output shape:** `{"volumeTier": String, "baseHours": Number, "addOnHours": Number, "totalHours": Number, "hourlyRate": String, "monthlyInvestment": String, "cleanupProject": {"monthsBehind": String, "issueCount": Int, "low": String, "high": String, "midpoint": String}?, "dayOneTotal": String?}`.
- **Read-only:** yes (no persistence, no network, no QBO data at all — it's a sales/pricing calculator, not a bookkeeping computation).

### Error handling

Every tool call is wrapped in `do`/`catch`; a thrown error produces `{"content":[{"type":"text","text":"<message>"}],"isError":true}` rather than crashing the server (`VoiceLedgerTools.swift:106-129`). Named argument errors (`ToolArgumentError`): `invalidSeverity`, `missingArgument`, `missingOrInvalidNumber`, `invalidEnum` (`:337-355`), each with a plain-English message.

---

## 3. Read/write boundary

**Confirmed: exactly one write-capable operation exists anywhere in this system**, `updatePurchaseLineAccount`. Everything else — including everything the MCP server above exposes — is read-only.

> **Correction to institutional memory:** `docs/VOICE_LEDGER_HANDOFF.md` §4 states "6 read operations currently" and describes an `assertReadOnlyCatalog()` function. Both are stale. The catalog now has **16 named operations — 15 read, 1 write** (`backend/src/catalog/operations.ts`), and `assertReadOnlyCatalog()` was renamed to `assertCatalogWriteOpsAreApproved()` on 2026-08-17 (`operations.ts:505-515`) when the first write operation's capability spike passed and the owner explicitly approved it. `docs/VOICE_LEDGER_HANDOFF.md`'s own later section (its write-path discussion) already describes this; only the earlier §4 passage is out of date.

### The full catalog (`backend/src/catalog/operations.ts`; mirrored on the desktop side by `desktop/Sources/Integrations/QuickBooks/CatalogOperation.swift`, an identical closed `enum: String`)

| Operation | Class | QBO call | Required params |
|---|---|---|---|
| `readCompanyInfo` | read | `GET companyinfo/{realmId}` | none |
| `readPreferences` | read | `GET query` (`select * from Preferences`) | none |
| `readAccounts` | read | `GET query` on `Account` | — (activeOnly/startPosition/maxResults have defaults) |
| `readPurchases` | read | `GET query` on `Purchase where TxnDate...` | startDate, endDate |
| `readBills` | read | `GET query` on `Bill where TxnDate...` | startDate, endDate |
| `readInvoices` | read | `GET query` on `Invoice where TxnDate...` | startDate, endDate |
| `readPayments` | read | `GET query` on `Payment where TxnDate...` | startDate, endDate |
| `readDeposits` | read | `GET query` on `Deposit where TxnDate...` | startDate, endDate |
| `readVendorCredits` | read | `GET query` on `VendorCredit where TxnDate...` | startDate, endDate |
| `readVendors` | read | `GET query` on `Vendor` | — |
| `readTaxCodes` | read | `GET query` on `TaxCode` | — |
| `readTaxRates` | read | `GET query` on `TaxRate` | — |
| `readTaxAgencies` | read | `GET query` on `TaxAgency` | — |
| `readReport` | read | `GET reports/{reportKind}` — closed enum: BalanceSheet, ProfitAndLoss, TrialBalance, GeneralLedger, TransactionList, CashFlow, AgedReceivables, AgedPayables | reportKind |
| `cdcSince` | read | `GET cdc` — closed entity enum: Account, Vendor, Purchase, Bill, Customer, Item | entityKinds[], since |
| `updatePurchaseLineAccount` | **write** | `GET query` (pre-read) → `POST purchase` (full-entity) → `GET query` (verify) | purchaseId, lineId, expectedSyncToken, newAccountId |

The dispatcher (`backend/src/catalog/dispatcher.ts`) is the **entire surface** through which any client can move QBO data — an operation name absent from `CATALOG_OPERATIONS` is not merely unauthorized, it is structurally unreachable (`dispatcher.ts` doc comment; TESTED `backend/test/catalog.test.ts`, "unreachable operation returns kind: unreachable"). No route in this codebase accepts an arbitrary path or HTTP method.

On the desktop side, `CatalogOperation` is a closed Swift enum mirroring the same 16 names; `BackendClient.call<Params>(_ operation: CatalogOperation, ...)` takes a `CatalogOperation`, not a `String`, so invoking a name outside the enum is a compile error, not a runtime check (`desktop/Sources/Integrations/QuickBooks/CatalogOperation.swift`, `BackendClient.swift:339-364`).

### The one write operation, in detail

`updatePurchaseLineAccount` reclassifies a single line's expense category on an existing `Purchase`. Its steps (`backend/src/catalog/operations.ts:366-469`):

1. Fresh read of the entity (never trusts a caller-supplied "current state").
2. `SyncToken` match check — a mismatch throws `409` ("someone else changed this transaction; resync and try again").
3. Full-entity `POST` — the entire read-back entity, with only the target line's `AccountRef` changed. (Sparse updates are known to silently drop data on this API — see §6 — so this operation deliberately never uses one.)
4. Checks the POST response body for a QBO fault embedded in a 2xx status (`classifyWriteResponse`) before trusting anything happened.
5. A **second, fresh read** (not the POST response) verifies: the target line's account actually changed, and every field in `["DocNumber","PrivateNote","TotalAmt","EntityRef","AccountRef","TxnDate"]` plus every *other* line is byte-for-byte unchanged from the pre-update read.
6. Returns `{verified: Bool, purchaseId, lineId, oldAccountId, newAccountId, newSyncToken, unexpectedFieldChanges: [String], otherLinesUnchanged: Bool, before: <full entity>, after: <full entity>}`.

`verified: false` does **not** mean "no HTTP error occurred" — it means the round-trip check found something wrong, and a caller must treat that as unresolved, not as success (`desktop/Sources/Core/WriteVerificationResult.swift:9-15`).

**Gating (structural, not a convention a route handler could forget):** a write-classified operation is refused inside `dispatch()` itself — the one function every operation call passes through — unless `realmWriteEnabled` is true for that realm (`dispatcher.ts:23-25, 44-60`). The realm's write-enabled flag is read fresh from `TokenStore` on **every** call, never cached (`backend/src/routes/operations.ts` doc comment) — disabling write access takes effect on the very next call. Every new client connection starts with this flag off (`backend/src/auth/tokenStore.ts` doc comment on `isWriteEnabled`). TESTED: `backend/test/writeAccessGate.test.ts` (4 tests), `backend/test/catalog.test.ts` (write op refused for a write-disabled realm).

The set of operations allowed to be write-classified is itself an explicit allowlist, `APPROVED_WRITE_OPERATIONS = {"updatePurchaseLineAccount"}`, checked by `assertCatalogWriteOpsAreApproved()` — adding a second write operation to the catalog without also adding it here throws at startup (`operations.ts:503-515`). TESTED: `backend/test/catalog.test.ts` ("every write-classified operation is on the explicit approved list").

### Desktop-side write path

`QBOSyncClient.reclassifyPurchaseLine(...)` (`desktop/Sources/Integrations/QuickBooks/QBOSyncClient.swift:297-315`) is the only desktop entry point that invokes this operation. `AppState.applyStagedFix` calls it, treats `verified: false` as an error (never silent success), and logs `ActivityKind.apiWriteApplied` only on `verified: true`. In the UI, `FindingDetailView` gates this behind an explicit "Apply Fix" → "Confirm Apply Fix" two-step, disabled entirely when write access is off. **Only one rule** (`CreditCardPaymentMiscodedRule`) currently populates the data needed to surface this button, and only under narrow conditions (single line, structural vendor match, resolvable `SyncToken`). Every other finding type routes to `.manualQBO` resolution — a guided procedure telling a human what to do in QBO's own UI, with no write path at all.

**Write journal** (`desktop/Sources/Core/WriteJournal.swift`): a `.submitted` entry is persisted to disk **before** the network call, so a crash mid-write leaves a durable record. States: `.submitted` → `.success` | `.failed` (verified-false, or an unchanged `SyncToken` on resolution — safe to retry) | `.unknown` (no answer ever came back — **never auto-retried**, blocks further writes to that entity) | `.ambiguous` (SyncToken changed but not to the expected value — escalates to a human, never guessed). TESTED: `WriteJournalResolution.resolve`'s four branches, unit-tested in `desktop/Tests/CoreTests`.

**Has a write ever actually executed against a real QBO sandbox?** Yes, per the project's own institutional-memory doc, which this document did not independently re-run: `docs/VOICE_LEDGER_HANDOFF.md` records a real throwaway 2-line Purchase (#227) reclassified end-to-end with `verified: true`, plus a replay of the old `SyncToken` correctly failing with `409`, and disabling write access mid-session correctly returning `403`. **Treat this as SANDBOX-VERIFIED by project self-report, not re-verified while writing this document.**

---

## 4. Calculations

**Numeric type: no floating point anywhere in the financial model.** `Money` (`desktop/Sources/Core/Money.swift`) stores an `Int64` count of **integer minor units** (cents) plus a `CurrencyCode`. Comparing or adding across currencies is a `precondition` trap, not a silent coercion (`Money.swift:33-53`). The only floating-point conversion (`majorUnitsDouble`) is explicitly documented as presentation-only, for charting, never for arithmetic or comparison (`Money.swift:60-68`).

**Currency: USD only, in practice.** `CurrencyCode` has exactly one static value defined anywhere in the codebase, `.usd` (`Money.swift:27`). Nothing in the rules engine, importers, or MCP tools handles a second currency; a sum across mismatched currencies returns `nil` rather than a wrong number wherever that's checked (e.g. `VoiceLedgerTools.swift:240-243`), but multi-currency QBO companies are not a supported scenario.

**Accounting basis:** no code path selects or requests cash-vs-accrual basis (no `AccountingMethod` parameter appears anywhere in `backend/src` or `desktop/Sources`). Reports come back however QBO's Report endpoint returns them by default (accrual, unless the company itself is cash-basis) — this is a gap, not a deliberate choice; see §8.

**Dates/timezone:** `AccountingPeriod`'s month-boundary math is fixed to UTC (`desktop/Sources/Core/AccountingPeriod.swift:79, 110, 124` — `calendar.timeZone = TimeZone(identifier: "UTC")!`), not the user's local timezone. A transaction dated near midnight in a non-UTC timezone could in principle fall into a different accounting period than a naive local-time reading would suggest — untested edge case.

**Rounding:** the only place a fractional cents value is produced from arithmetic (`TaxEstimate.estimatedSetAside`, below) uses `.rounded()` (round-half-to-even is Swift's default for `Double.rounded()`) before truncating to `Int64` minor units (`desktop/Sources/Core/TaxEstimate.swift:33`).

### Figures the app computes

- **Materiality floor:** a flat $25.00 (`Money(minorUnits: 2_500, ...)`), owner-set default, used to derive severity (`desktop/Sources/Core/RuleEngine.swift`, `MaterialityPolicy.defaultPolicy`). `Severity.derive`: `dollarExposure >= materiality.absoluteFloor ? .high : .low` (`desktop/Sources/Core/Finding.swift`) — a simple floor comparison, not the percent-of-revenue banding the original spec sketches (spec's `.medium` banding is not implemented; flagged in the code's own comment as "not yet exercised by any rule in Phase 1").
- **Aging summary** (`desktop/Sources/Core/AgingSummary.swift`): sums only **leaf** rows of an Aged Receivables/Payables report (a customer/vendor with sub-entities appears as both a summary subtotal row and separate leaf rows — summing every row would double-count). `percentOverdue = overdueAmount / totalAmount × 100`, `nil` if either side is missing or total is zero. `daysOutstanding = (balance / periodAmount) × daysInPeriod` — an approximation, since QBO's API doesn't separately expose "credit sales" vs. total revenue; labeled "approx." wherever it's shown.
- **Tax estimate** (`desktop/Sources/Core/TaxEstimate.swift`): `estimatedSetAside = netIncome × (userSuppliedRatePercent / 100)`. **Contains zero tax law, zero brackets, zero jurisdiction rules** — the rate is a value a human types in (typically from their own CPA), never a rate this app knows or looks up. Returns `nil` for a missing/negative rate or non-positive net income, never `$0` (a `$0` would itself be an unearned claim about tax liability).
- **Pricing quote** (`desktop/Sources/Core/PricingCalculator.swift`): `monthlyBaseHours` by volume tier (light 3.0h / growth 5.5h / high 8.0h) + flat per-flag add-on hours (payroll +1.5h, sales tax +1.0h, multi-bank +1.0h, inventory +2.0h), all × hourly rate. Cleanup-project quote scales by a volume multiplier and a months-behind tier. These coefficients are the owner's own pricing-model defaults, not derived from any client's real data.
- **Finding ID:** a SHA-256 digest over `(ruleID, ruleVersion, realmID, period, sorted affected entity IDs)` (`desktop/Sources/Core/Finding.swift`, `FindingIDGenerator.makeID`) — deterministic, so re-detecting the same problem on a later sync produces the same ID rather than a duplicate.

---

## 5. Findings and checks

**31 rules are registered** (`desktop/Sources/Core/RuleEngineActor.swift:139-172`, `RuleRegistry.all`), covering duplicate expenses/bills/invoices/payments/vendors, uncategorized transactions, negative asset/liability balances, undeposited-funds aging, unapplied vendor credits, forced reconciliations, report tie-outs, avoidable fees, period-closed drift, vendor price increases, category miscoding, debit/credit expectation violations, bank-transfer miscoding, loan-payment lump sums, missing payees, and amount transpositions.

Every rule returns one of three outcomes, never a plain boolean (`desktop/Sources/Core/RuleEngine.swift`, `RuleOutcome`): `.pass(coverage, checkedCount)`, `.findings([Finding])`, or `.cannotEvaluate(MissingRequirement)`. A rule cannot claim `.pass` on incomplete data — the engine independently validates this and downgrades a misbehaving rule to `.cannotEvaluate`, logging an engine defect (`RuleEngineActor.swift:130-133`). This exact bug was once caught by a test (`DuplicatePostedExpenseRuleTests`), fixed at the rule level rather than relied on as a backstop.

### Worked example: `VL-DUP-EXP-001` (`DuplicatePostedExpenseRule.swift`)

Three detection tiers, all against `Purchase` entities on the same payment account, **exact** vendor-name match (never fuzzy — a documented, deliberate choice to avoid false positives):

- **T1 (high confidence):** same vendor, same amount, same date, same payment account.
- **T2 (high confidence):** same vendor, same amount, same non-empty `DocNumber` — only active if the client's QBO company has "Custom Transaction Numbers" enabled (`context.companyFacts.customTxnNumbersForPurchases`), since QBO otherwise enforces unique `DocNumber` and this tier can never fire. Reported as informational tier-status, never a silent false-negative.
- **T3 (medium confidence):** same vendor, same amount, same payment account, dated within 3 days.

Exclusions: either transaction already voided (`isVoided`); either already explained by a relationship-class finding; below the $25 materiality floor (compared on magnitude, not signed value — a negative-amount Purchase pair is not exempted just because it's negative); both sides lack a vendor name (deliberately not matched — a weaker signal without vendor identity).

**Known false-negative:** two genuinely duplicate purchases from *different* payment accounts with no shared `DocNumber` will not be caught by any tier. **Known scope limit:** only `Purchase` entities — a separate rule, `CrossAccountDuplicateExpenseRule`, is registered for the cross-account case; `Bill`/`Invoice`/`Payment` duplicates are each their own separate rule (`DuplicateBillRule`, `DuplicateInvoiceRule`, `DuplicatePaymentRule`).

Voiding is always the recommended resolution, resolved manually in QBO — this rule has no write path. Every finding carries a deterministic plain-English narrative, a pre-approval checklist ("pull the actual bank statement — do not assume either transaction is the duplicate before checking"), and a `riskIfIgnored` statement. None of this prose is AI-generated; it's built from string interpolation over the matched values (`Finding.narrative`'s own doc comment: "there is currently no AI/Claude integration in this codebase at all" that touches findings).

### `isVoided` detection — SANDBOX-VERIFIED (project self-report)

Per `docs/VOICE_LEDGER_HANDOFF.md` §6: a `TotalAmt == 0` heuristic was tried first and **disproven** against real sandbox data (a legitimate $0 Purchase was misclassified as voided). The real signal — a top-level `"status": "Voided"` field present only on voided Purchases — was found and confirmed by manually voiding a real sandbox Purchase and observing the field appear.

### Other rule examples on record

- `NegativeBalanceRule` (`VL-BS-NEGBAL-001`): flags any Asset or Liability account with a negative `CurrentBalance`. Deliberately excludes Equity/Income/Expense (a negative owner's-draw balance is normal, not a defect).
- `UncategorizedTransactionRule` (`VL-CAT-UNCAT-001`): flags any `Purchase`/`Bill` line posted to one of QBO's three auto-created catch-all accounts ("Uncategorized Expense/Income/Asset"), matched by exact account name (QBO's own reserved system name, not user data, so no fuzzy-match risk).

---

## 6. Data completeness and freshness

**Pagination is not wired into the sync path.** `QBOSyncClient.sync` (`desktop/Sources/Integrations/QuickBooks/QBOSyncClient.swift:483-580`) reads at most 1,000 records per entity type in one page (`maxResults = 1000`, `:485`). If a page comes back full (`count == maxResults` for any of Purchases/Bills/Invoices/Payments), coverage is conservatively marked `.partial`, with the reason stated explicitly (`:553-555`) — **it does not fetch a second page.** A client with more than 1,000 transactions of one type in a period will silently see only the first page's worth reflected in findings, correctly flagged as incomplete but not filled in. `docs/VOICE_LEDGER_HANDOFF.md` §6 separately documents a real, reproduced pagination-skip bug in QBO's own API (deleting an earlier record mid-sweep silently drops a still-existing later record from every subsequent page) — the mitigation for that (a `COUNT`-query checksum) is confirmed viable but **not implemented** in `QBOSyncClient`.

**Cross-foot validation is specified but not implemented.** `docs/VOICE_LEDGER_SPEC.md`'s Universal Ingestion section describes cross-foot validation (do line items sum to stated subtotals? does beginning + credits − debits = ending balance?) as "the deterministic quality check" every imported document should pass before its data is allowed to produce findings. **No code implements this anywhere.** Both bank-statement importers say so directly in their own coverage reasons: `desktop/Sources/Integrations/Imports/OFXBankStatementImporter.swift:74` — `"cross-foot validation (§9.5) is not implemented in this importer"` — and `BankStatementCSVImporter.swift:119`, same wording. Every import from these two importers is therefore marked `coverage: .partial` unconditionally, not because of anything about the specific file.

**Extraction tiers:** only Tier 1 (deterministic CSV/OFX/XLSX parsers, `desktop/Sources/Integrations/Imports/`) and Tier 2 (on-device Apple Vision OCR, `VisionDocumentOCR.swift`) are implemented. **Tier 3 (Claude vision escalation) exists only as an enum case** (`ExtractionMethod.claudeVision`, `desktop/Sources/Core/DataModel.swift:207`) with no implementation anywhere in the codebase — it is modeled, not built.

**CDC (change-data-capture) lookback is 30 days** (an Intuit platform limit, not a Voice Ledger choice) — not usable as a permanent history feed; a full resync is still needed periodically (`docs/VOICE_LEDGER_HANDOFF.md` §6).

**Partial results are always labeled, never silent.** The `Coverage` type (`.complete` vs `.partial(reason:)`) is threaded through every rule's input, and a rule returning `.pass` on partial coverage is caught and downgraded by the engine (§5). This is the one completeness guarantee that is actually enforced structurally rather than just documented.

**Report data is a separate, weaker-guarantee class.** Reports (`readReport`, closed enum of 8 report kinds) have no `SyncToken`, no CDC, no pagination — they are fetched fresh each time and normalized by binding on `ColTitle`/`ColType`, never column index (`docs/VOICE_LEDGER_HANDOFF.md` D6, PLANNED as its own decision — column-index binding risk is called out but this decision is not fully built out as a distinct staleness-tracking layer).

---

## 7. Test coverage

**Desktop** (`desktop/Tests/`, Swift Testing framework): **774 tests across 10 targets**, all passing at the time of writing (verified by running `swift test` directly).

| Target | Tests | Covers |
|---|---|---|
| CoreTests | 557 | Every rule in `RuleRegistry` (31 rules), `Money`, `WriteJournal`, `WriteVerificationResult`, `PricingCalculator`, `AgingSummary`, `TaxEstimate`, `FinancialKPIs`, `ActivityLog`, and more |
| DBTests | 48 | `ClientStore` persistence, JSON→SQLite migration, partial-failure handling, resolved-finding recurrence |
| VoiceTests | 40 | Voice intent routing, review queue, voice session context |
| ExportingTests | 39 | PDF/CSV/XLSX/ZIP report exporters |
| IntegrationsImportsTests | 35 | CSV/OFX/XLSX parsers and bank-statement importers |
| IntegrationsQuickBooksTests | 32 | `QBOSyncClient` decode/normalize, report flattening, tax-entity decoding |
| VoiceLedgerUITests | 13 | Findings list view, status-mapping honesty |
| ArchitectureTests | 4 | Module-boundary enforcement (Core⊅Integrations), no-secrets scan |
| DesignSystemTests | 4 | Color-contrast checks |
| IntegrationsVoiceTests | 2 | Voice service client |
| **VoiceLedgerMCP** | **0** | **No test target exists for the MCP server at all.** |

**Backend** (`backend/test/`, Vitest): **91 tests across 12 files**, all passing at the time of writing.

| File | Tests | Covers |
|---|---|---|
| catalog.test.ts | 18 | The full 16-operation catalog, dispatch gates, write-op round-trip verification |
| productionGuard.test.ts | 14 | Sandbox/production credential resolution guard |
| tokenStore.test.ts | 15 | Refresh-token encryption round-trip, write-access flag, access-token cache TTL |
| sanitizeHistory.test.ts | 6 | Ask-AI chat history sanitization/caps |
| openaiClient.test.ts | 6 | OpenAI provider client |
| anthropicClient.test.ts | 6 | Claude (Anthropic) provider client |
| writeResponse.test.ts | 5 | Detecting a QBO fault embedded in an HTTP 200 |
| ollamaClient.test.ts | 5 | Ollama (local, default) provider client |
| redaction.test.ts | 5 | Log-redaction regex patterns |
| session.test.ts | 4 | Session issuance/validation/expiry |
| writeAccessGate.test.ts | 4 | The write-access gate mechanism in isolation |
| aiSettingsStore.test.ts | 3 | AI kill-switch persistence |

**What has never been exercised against real production QBO data:** everything. Every sandbox-verification claim in this document and in `docs/VOICE_LEDGER_HANDOFF.md` is against a QBO **sandbox** company. There is no record anywhere in this codebase of any call — read or write — against a real production QBO company.

---

## 8. Limitations and known gaps

- **No pagination beyond one page** (§6) — data beyond 1,000 records per entity type per sync is invisible, though correctly flagged as `.partial`.
- **Cross-foot validation is unimplemented** (§6) despite being specified as the core deterministic quality gate for imports.
- **Tier 3 (Claude vision) extraction is unimplemented** — modeled as an enum case only.
- **No multi-currency support** — `CurrencyCode` has one value.
- **No cash-vs-accrual selection** — reports come back however QBO's default returns them for that company.
- **Payroll, inventory, multi-currency, custom fields, sales-form configuration** are explicitly out of scope per `docs/VOICE_LEDGER_SPEC.md`'s "Explicitly Out of Scope" section — treated as one-time QBO admin tasks, not recurring bookkeeping work this app assists with.
- **No API access at all** to QBO's "For Review" bank-feed queue, reconciliation history/completion, Books Review, Books Close progress, or the real Audit Log — these are all Type B (import/screenshot) or Type C (guided-manual, attested-only) in the product's own workflow design; there is no code path that could ever close this gap via the API.
- **`AccountingDate` timezone is fixed UTC** for period-boundary math (§4) — a genuine edge case for a bookkeeper working across timezones, untested.
- **A known bug is preserved and documented, not fixed:** `RuleContext.gatingTransactions(_:)` (`desktop/Sources/Core/RuleEngine.swift`) silently drops a caller-supplied `asOfDate` and resets it to "now" — confirmed not live in any production call path today (only test callers ever set a non-default `asOfDate`, and they don't go through this method), but it would matter the moment an age-based rule is tested end-to-end through the full engine with a fixed date.
- **The Apply-Fix write button only exists for one rule** (`CreditCardPaymentMiscodedRule`) under narrow conditions. Every other finding — including the flagship duplicate-expense rule described in §5 — resolves manually in QBO with no write path.
- **The OAuth callback (`GET /oauth/callback`) returns the raw session token as plain JSON** — the route's own doc comment calls this "a Phase 1 development convenience... not the product UI" (`backend/src/routes/oauth.ts:6-11`). This is a real, if self-acknowledged, exposure surface in the current build.
- **No AI-provider integration is "Claude" by default**, despite the product spec's "Ask Claude panel" language. The default is a local Ollama model (`gemma4:12b`, free, no API key), with OpenAI as an opt-in secondary tier and a dedicated Anthropic (`claude-haiku-4-5`) tier available as a selectable model override (`backend/src/config.ts`, `backend/src/routes/ai.ts`). This is a real pivot from the spec's original framing, not an inconsistency in this document.

---

## 9. Security

- QBO client secret and all AI provider API keys live only in the backend process's environment — never in the desktop binary. Enforced partly by a real, running test: `desktop/Tests/ArchitectureTests` scans all of `desktop/Sources/` for secret-shaped literals and fails the build if any are found (TESTED: "No secret-shaped literal exists anywhere in Sources/").
- Refresh tokens: AES-256-GCM at rest, per-realm SQLite row (§1).
- Access tokens: in-process memory only, never written to disk.
- Logging: a typed logger is the primary defense against logging sensitive data; a second, independent regex backstop (`backend/src/logging/redaction.ts`) scans every serialized log line for bearer tokens, long opaque token-shaped JSON values, **any currency-amount-shaped string** (`$1,234.56`-style — dollar amounts are treated as forbidden in logs categorically), and Anthropic-style API keys.
- Imported files (CSV, OFX, PDF, screenshots) and their OCR processing **never leave the desktop app** — they are not proxied through the backend, per `docs/VOICE_LEDGER_HANDOFF.md` §4. (Tier 3 Claude-vision escalation, which would break this property by design, is unimplemented — see §6/§8.)
- Client data isolation: each QBO `realmId` gets its own on-disk store — not a shared database with a `WHERE realm_id = ?` clause. `docs/VOICE_LEDGER_HANDOFF.md` D2 notes this has migrated from one-JSON-file-per-realm to one-SQLite-file-per-realm-directory (2026-08-29), but three of four originally-planned isolation layers (a `ClientScope` actor with no ambient "current client," phantom-typed `Scoped<>` values, runtime assertions at crossing points) remain **not yet built** — only the per-realm-directory separation itself is real today.

---

## Safe to rely on

- The read/write boundary: 15 read operations, exactly 1 write operation (`updatePurchaseLineAccount`), gated per-realm, verified fresh on every call, round-trip verified on every write.
- `Money`'s integer-cents arithmetic — no floating-point drift in any dollar figure.
- The `RuleOutcome` three-state design — a rule cannot silently show green on missing data; this is engine-enforced, not just convention.
- The MCP tools' read-only guarantee — there is no code path in `VoiceLedgerTools` that can write anything, by construction.
- 774/774 desktop tests and 91/91 backend tests passing as of this writing.
- Coverage labeling (`.complete`/`.partial`) is threaded honestly through rules and imports, including two real, currently-unresolved partial-coverage sources (pagination, missing cross-foot validation) that are flagged rather than hidden.

## Do not rely on yet

- Any dataset larger than 1,000 records of one entity type per sync period (pagination gap).
- Any imported bank statement's internal arithmetic being checked before its data is trusted (cross-foot validation is unimplemented).
- Tier 3 (Claude vision) document extraction — it doesn't exist yet.
- Multi-currency, cash-vs-accrual selection, payroll, inventory, or any production QBO company (everything verified so far is sandbox-only).
- The MCP server's behavior under load, concurrent calls, or a hung backend health check — there is no test coverage and no timeout handling for this specific process.
- Any write path for a finding other than `VL-CC-PAYMENT-001` (credit-card payment miscoded) — every other finding type has no write path at all, by design, not as a temporary gap.
