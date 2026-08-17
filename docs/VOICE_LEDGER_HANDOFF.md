# VOICE_LEDGER_HANDOFF.md

**Purpose:** long-term institutional memory for Voice Ledger. Written at the point where the project moved from a planning conversation into Claude Code as its permanent home. Everything a future instance needs to continue as though it had participated in the original conversation.

**Status legend used throughout:**
- **IMPLEMENTED** — code exists, builds, and has been verified running
- **IN PROGRESS** — approved and actively being built at handoff time
- **PLANNED** — approved and specified, not yet built
- **PROPOSED** — suggested, argued for, but not yet approved by the owner
- **REJECTED** — considered and deliberately not done, with reason
- **UNKNOWN / NEEDS VERIFICATION** — believed but not proven against a live sandbox

**Never mark something IMPLEMENTED because it was discussed. The distinction between "specified" and "verified running" is load-bearing in this project.**

> **Editorial note (2026-08-16, applied when this file was filed into the repo):** this document was drafted in a separate Claude.ai conversation, one work session behind the Claude Code session that then finished the vertical slice. §13, §16, and §19 below contained status claims that were current when written but became stale within the same day — Part 5 (the vertical slice's Core logic, QBO sync/normalization, per-realm persistence, and minimal UI) was committed and its Wave 3 void-on-other-entities question was already resolved. Those sections have been corrected in place, each flagged with a note explaining what changed and why, rather than silently edited — the same discipline this document itself argues for in §20. Everything else is preserved as written.

---

# 1. Origin and vision

## How this started

The project began as an unrelated question: which reporting software to use for a new bookkeeping business (Datarails, Syft, Fathom were evaluated). That evolved into building a report generator, then into rebuilding an existing prototype called Voice Ledger as a native macOS application.

There is a **prior prototype** built in Google AI Studio and later Base44, with a GitHub repo. Its code is conceptual reference only — near-zero reuse expected, since the rebuild is native Swift. The prototype's screenshots established the visual direction (dark, dense, "financial command center") and its feature set seeded the rules backlog.

**IMPORTANT: `01_REPO_INVENTORY.md` is still BLOCKED.** The prototype repo URL was never supplied. When it arrives, the highest-value output is not a code inventory but section D — capability claims to re-verify. The prototype is a record of which QBO endpoints actually returned useful data in practice, which is stronger evidence than documentation.

## What Voice Ledger is

A native macOS app that runs on one monitor while QuickBooks Online runs on the other. **QBO remains the client's system of record.** Voice Ledger is the structured workpaper layer a bookkeeper would otherwise keep in scratch spreadsheets and memory — made auditable, evidence-backed, and partly automated.

The one-line framing the owner settled on, and the one that should govern product decisions:

> **Not "the app that does my bookkeeping." The app that proves my bookkeeping is right, and teaches me while I do it.**

## The positioning argument (why this exists at all)

QuickBooks now ships its own Claude connector and its own AI (Intuit Intelligence, August 2026: categorization, reconciliation assistance, anomaly detection, insights). A generic "ask questions about your QuickBooks" interface is chasing something Intuit already ships.

Voice Ledger specializes in what a generic connector cannot do:
- A structured, gated month-end workflow
- Deterministic error detection with evidence
- Safe staged corrections instead of silent writes
- Client-specific bookkeeping memory
- Review-and-approval controls
- Audit-ready close packages
- **A bookkeeper actually learning the craft while using it**

The term used for this: **controlled bookkeeping intelligence.**

**The strategic fact that justifies the product:** QBO's bank rules plus Intuit Assist reportedly land around **50% categorization accuracy on novel transactions**, and that is a stated design constraint — QBO's categorization was built for owners managing a single company, not a bookkeeper running 15–25 client files. Third-party categorizers reportedly reach 85–90%. That gap is the business.

---

# 2. Intended user and workflow

## The user

A **solo bookkeeper, new to the craft**, with an MBA and Google Data Analytics certificate, working toward CompTIA certs and transitioning into IT/cybersecurity in parallel. Based in the Odessa/Dallas, Texas area. **He has zero clients as of handoff.**

He described the app as **"training wheels and bowling bumpers"** — that phrase is the design north star. He is building judgment, not exercising established judgment.

Services offered: reconciliations, monthly closing, transaction categorization, duplicate fixing, and cleanups for messy books. **He does NOT do AR or AP work** — this is why those workflows are explicitly out of scope.

Longer term: he intends to build a combined accounting/bookkeeping/tax firm, likely hiring offshore staff. Multi-operator support is deliberately deferred (see §5, D-Single-Operator).

## The operating model (governs everything)

**Voice Ledger on one monitor, QBO on the other.** This changes what "the API can't do that" means — it is not a blocker, it is a **defined handoff**.

Three consequences that shape every design decision:

1. **Every step in the process gets a page** — including steps the app cannot perform at all. A page whose only job is to say what to do in QBO, give a checklist, and record that it was done is still worth having. *Missing a step is the real risk for a new bookkeeper; an incomplete-but-honest page beats no page.*
2. **Where the API can't reach, Universal Ingestion fills the gap.** If QBO's UI can export it — or even just display it on screen — the app can ingest it.
3. **Every page ends with an Ask Claude panel**, because the moment of uncertainty is exactly when you need to ask rather than guess.

## The three page types

| Type | Meaning |
|---|---|
| **Type A — API-Driven** | App pulls data, runs rules, presents findings, stages corrections, writes back with approval |
| **Type B — Import-Driven** | API can't reach it, but it can be exported or screenshotted. App analyzes the import identically. |
| **Type C — Guided Manual** | App can't do the work and can't get the data. It gives the exact QBO procedure, pitfalls, done-criteria, and records attested completion. |

Pages can be hybrid (A+C, B+C). **A Type C page is not a failure** — it is the difference between a checklist covering the whole process and one with silent holes.

---

# 3. The 12-page workflow — PLANNED (none built)

Ordered deliberately: early pages gate later ones. You cannot safely detect or fix anything until access, scope, and a baseline exist.

| # | Page | Type | App does | You do |
|---|---|---|---|---|
| 1 | Access & Evidence Pack | A + C | Reads CompanyInfo, accounts, baseline reports; verifies `realmId`; generates Baseline Evidence Pack | Attest QBOA accountant access (unverifiable via API) |
| 2 | Scope & Period Lock | A + C | Stores scope; reads `BookCloseDate`; enforces its own stricter lock; warns on closed-period dates | Set the official QBO closing date; confirm filing status |
| 3 | File Health Scan | A | Analyzes accounts, transactions, BS, P&L, TB, GL | — |
| 4 | Bank Feed Cleanup | B | Compares posted QBO activity against imported statement; duplicates and missing postings | Resolve in QBO's bank feed |
| 5 | Reconciliation | B + C | Compares statement lines to ledger; identifies unmatched/duplicates; calculates difference | Execute Finish Reconciliation in QBO |
| 6 | Chart of Accounts Cleanup | A + C | Reads/creates/renames/deactivates accounts; detects duplicate candidates; prepares merge plan | Perform the merge in QBO |
| 7 | Batch Fixes | A | Full-entity updates with round-trip verification; pre-run impact preview | May prefer QBOA's Reclassify tool for large jobs |
| 8 | Balance Sheet Integrity | A | Strongest API coverage; negative balances, suspense, clearing, undeposited aging, loans, equity | — |
| 9 | Sales Tax Review | A + C | Reads tax codes, rates, agencies, liability balances (AST only) | Confirm filing status, jurisdiction, adjustments |
| 10 | Taxes | A | Estimates exposure and deduction flags — **always labeled an estimate** | Everything actual |
| 11 | Month-End Close | A + C | Checklist, dependencies, approvals, carry-forwards, validation scan | Set official QBO closing date; complete Books Close |
| 12 | Reporting | A | P&L, BS, cash flow, GL, TB, aging; branded PDF; Close Package | — |

**Dependency-aware staleness runs across all pages:** change an upstream transaction after a later page was completed, and everything downstream is automatically marked for revalidation. Never a false checkmark.

## Page structure (every page)

1. Page type badge · 2. What was checked / passed / needs review · 3. Why flagged, with evidence · 4. Recommended solutions and consequences · 5. Approve / edit / dismiss / ask client · 6. (Type B) import status and "get this file from QBO here" · 7. (Type C) QBO procedure, pitfalls, done-criteria · 8. Re-run checks / mark complete · 9. Ask Claude panel

**Sections cannot be marked complete on missing data.** A Type B page with no import shows "Coverage incomplete," never green.

## Cleanup mode — PROPOSED

Cleanup is **triage-ordered, not sequence-ordered**. The sequential close order is right for a monthly close and wrong for a rescue. Assessment first, then reconciliation oldest-first (a beginning-balance error propagates forward), then highest-dollar miscoding classes, then everything else.

New client onboarding and a messy-books cleanup are **the same flow with a wider date range**, not separate modes.

---

# 4. Architecture — IMPLEMENTED and PLANNED

## Layer structure

```
/core            platform-agnostic: metrics, rules engine, finding detection,
                  severity/confidence classification. Pure functions.
/integrations
  /quickbooks     QBO API via the thin backend, normalization
  /imports        parsers, on-device OCR, extraction verification
  /xero           (future) same contract, different adapter
/staging          local diffable record of every proposed correction
/voice            whisper.cpp, local intent parser, optional LLM fallback
/db               findings, activity log, imports, memory rules
/ui               SwiftUI screens
```

**`/core` never imports from `/integrations`.** IMPLEMENTED and enforced by a source-scan lint wired into `swift test` — not a comment, an actual failing test.

**API data and imported-file data normalize into the same shape.** This is what keeps Type B pages from becoming a parallel codebase. There is a property test for it (source equivalence: same data via API and via CSV yields the same findings modulo provenance).

## The thin backend — IMPLEMENTED (read-only)

**Why it exists:** Intuit's OAuth is designed around a server-side exchange. Embedding the QBO client secret or Claude API key in a distributed desktop binary makes them extractable.

Responsibilities: stores refresh tokens encrypted (AES-256-GCM) · issues opaque sessions bound to one realm · exchanges and refreshes OAuth tokens · proxies and authorizes QBO writes · enforces the operation catalog · rate-limits per realm · structured logging with a redaction backstop · sandbox-only production guard.

**Stated precisely, and this precision matters:** the backend *does not persist* accounting payloads, but QBO and Claude requests *transit* it and it may process selected data in memory while proxying. "Never touches accounting data" would be false.

**Imported files stay local to the desktop app and never transit the backend** — including OCR, which runs on-device via Apple's Vision framework. The one exception is Tier 3 Claude vision escalation, which requires explicit per-file consent precisely because it breaks that property.

Deploy target: Render (owner has a Render connector). `render.yaml` exists with a persistent disk attached, because Render's default filesystem is ephemeral. SQLite for tokens/sessions is an explicit temporary scope decision — a managed database is worth provisioning past sandbox testing.

## The operation catalog (Decision D5) — IMPLEMENTED

**The desktop client cannot express a QBO request.** No path, no method, no body. It can only invoke named, typed operations like `voidPurchase(realmId:id:syncToken:intentId:)`.

Consequence: an operation not in the catalog is **structurally unreachable, not merely unauthorized**. `deletePurchase` is deliberately absent, so no modified or decompiled client can hard-delete anything. Adding a QBO capability requires a backend deploy.

`assertReadOnlyCatalog()` plus a test enforces that only read operations exist today. **6 read operations currently.**

---

# 5. Architectural decisions and why

## D1 — Three rule outcomes, not two — IMPLEMENTED (as of 2026-08-16's slice work; PLANNED when this doc was drafted)

```swift
enum RuleOutcome {
    case pass(coverage: Coverage, checkedCount: Int)   // ONLY outcome that can produce green
    case findings([Finding])
    case cannotEvaluate(MissingRequirement)            // NOT the same as finding nothing
}
```

**Why:** with two cases, "zero findings" and "couldn't check" collapse into the same value, and that collapse is precisely how a missing import becomes a green checkmark. With three, the compiler forces every consumer to handle "couldn't check" separately.

Additionally, `.pass` **cannot be recorded** when coverage isn't complete — the engine validates the returned outcome and downgrades a rule author's mistake to `.cannotEvaluate`, recording an engine defect. This is defense against our own future carelessness. **This exact defect was caught by a test during the slice build** — `DuplicatePostedExpenseRule` initially could return `.pass` with partial coverage on a zero-transaction input; fixed at the rule level, not just relied on the engine's backstop. See `desktop/Sources/Core/RuleEngine.swift`, `RuleEngineActor.swift`, `DuplicatePostedExpenseRule.swift`.

## D2 — One SQLite database per `realmId` — PLANNED (scoped-down substitute IMPLEMENTED for the slice)

Not a `realm_id` column with a `WHERE` clause. **A cross-client query is not a missing predicate — it is a different file.** The failure mode is eliminated rather than guarded against.

Stated cost: no cross-client SQL. The Firm Cockpit must fan out across stores and aggregate in memory. Accepted — the aggregation is over small summary data, not ledger rows.

Four layered isolation mechanisms: per-realm database · `ClientScope` actor with no ambient "current client" · phantom-typed `Scoped<Scope, Value>` at crossing points only (staging queue, activity log, QBO write path — not every read) · runtime assertions at four crossing points.

`realmDirectoryName` is a **hash** of the realmId, so directory listings don't enumerate client identifiers.

**What actually shipped for the slice (2026-08-16):** `desktop/Sources/DB/ClientStore.swift` — one JSON-file-per-realm-directory, not SQLite, and the directory name is the raw `realmId`, not a hash. Same isolation *property* (no shared table a missed `WHERE` could leak across), explicitly documented in the file's own doc comment as a scoped-down substitute, not the spec'd design. The four-mechanism layered model above (phantom types, runtime assertions at crossing points, hashed directory names) is **not yet built** — only the outermost layer (per-realm directory) exists.

## D3 — Staleness is derived, never marked — PLANNED

**There is no `markStale()` function anywhere.** A page is fresh iff the evidence watermark it was completed against still equals the current watermark for its declared inputs. Code cannot forget to call something that doesn't exist.

Watermark components include rule versions and materiality policy — so bumping a rule version or changing materiality automatically stales completed pages.

**Not yet built.** The slice's `ClientStore` has no watermark concept — `reconcileAgainstLatestRun` resolves findings when a rule stops reproducing them, which is a different (narrower) mechanism than the general watermark design. Do not confuse the two when this is built for real.

## D4 — Three-phase write journal with explicit `UNKNOWN` — PLANNED

`SUBMITTED` is persisted and flushed to disk **before** the network call. A journal written after the call would lose the record of a write that may have landed.

`UNKNOWN` is a first-class persisted state. **Never retry.** It blocks all further writes to that entity until a resolution probe settles it. The probe's load-bearing step: an unchanged `SyncToken` is strong evidence the write did not land, since any successful write increments it. An `AMBIGUOUS` outcome escalates to the human — never guessed.

**Still fully PLANNED, not built.** The slice's Branch B makes no QBO write at all (see §14), so this machinery has no caller yet in the desktop app. It IS specified in more detail than when this doc was drafted — see `docs/phase-0/10_STAGING_APPROVAL_AUDIT.md` §10.5a for the HTTP-200-is-not-success correction (§15.A below) folded into the design, including a revised probe step 1. None of §10.5a's `classifyWriteResponse` chokepoint exists in backend code yet.

## D5 — Operation catalog, not a proxy — IMPLEMENTED (see §4)

## D6 — Reports are a distinct data class from entities — PLANNED

No CDC, no webhooks, no `SyncToken`, no pagination, non-deterministic column layout across minor versions. Separate normalization layer and time-based (not event-based) staleness.

**Bind report columns by `ColTitle`/`ColType`, never by index.**

## D7 — The slice's write path was gated on one unverified fact — RESOLVED

Whether `Purchase` supports `?operation=void`. **It does not.** See §6. Branch B selected — and, per the correction to §16/§19 below, confirmed to apply broadly across the TXN profile (`Bill`, `JournalEntry`, `BillPayment` also confirmed unsupported), not narrowly to `Purchase` alone.

## D-Single-Operator — PLANNED

Confirmed single operator. Multi-operator is deferred as its own future design pass, not pre-built. The five mechanisms that would need revisiting are recorded in `07_CLIENT_ISOLATION.md` §7.9: `ApprovalRecord.approvedBy`, `ClientScopeRegistry`'s one-scope-per-realm assumption, per-entity write serialization, the backend's realm-only (not realm+role) session model, and `ActivityLogEntry.actor`'s single-identity attribution.

## D-Native-Swift — decided

Chose native SwiftUI over Electron/Tauri. **Consequence accepted:** no code reuse from the web prototype; slower path to a running app; better native feel. The prototype becomes pure conceptual reference.

---

# 6. QBO integration — VERIFIED findings

**Matrix state at handoff: 69 rows · 21 VERIFIED · 6 DISPROVEN · remainder ASSUMED.**

**The matrix is generated from passing sandbox tests, never hand-edited.** A human cannot type a row into VERIFIED. `VERIFIED` expires after 90 days and reverts to `STALE`, which surfaces `ResolutionConstraint.capabilityUnverified` in the UI.

## Hard API limits — VERIFIED or well-established

| Limit | Consequence |
|---|---|
| **No read-only OAuth scope.** `com.intuit.quickbooks.accounting` grants read+write together | The app must self-enforce read-only. This is the entire safety story. |
| **"For Review" bank feed queue has no API access at all** | Page 4 is Type B. Screenshot or statement import only. |
| **No REST endpoint for the reconciliation action** | Page 5 cannot Finish/Undo. Type C handoff. |
| **No reconciliation history, statement balances, or attached statement** | Import or screenshot only |
| **QBO Audit Log has no API** | Hence "Activity & Correction Log," never "Audit Log" |
| **No endpoint returns an accountant's QBOA client list** | Firm Cockpit is Voice Ledger's own connected-company registry |
| **No API for Books Review, Transaction Review anomalies, or Books Close progress** | Hence "Voice Ledger Health Scan," not "Books Review" |
| **Cannot set the official QBO closing date or its password** | Type C |
| **CDC lookback is 30 days** | Not usable as a permanent history feed |

## Findings from the capability spike — all VERIFIED against live sandbox

**⚠ `Purchase` void is unsupported.** QBO returns: `"Message": "Unsupported Operation", "Detail": "Operation void is not supported."` Not a malformed request — a direct answer. **This selected Branch B for the vertical slice.**

**⚠ Void is unsupported on the whole TXN profile tested, not just `Purchase` — corrected from this doc's original draft, see the note below.** `Bill` void returned **HTTP 200 with a `SystemFault` body** (a leaked Java exception). `JournalEntry` void returned **HTTP 200 with an empty `BatchItemResponse`** (a silent no-op). `BillPayment` void returned a clean HTTP 400, same shape as `Purchase`. **Every write response must be validated on its body, not its status.** An empty or structurally unexpected success body is `UNKNOWN`, not success.

> **Correction to the original handoff draft:** §16 and §19 below, as originally written, described the `Bill`/`JournalEntry`/`BillPayment` void results as "partially run" and left open whether Branch B's scope was narrow (`Purchase` only) or broad (the whole TXN profile). By the time this file was filed into the repo, `docs/phase-0/11_VERTICAL_SLICE.md` §11.1 had already been revised to state this plainly: **all three were tested, all three confirmed unsupported, Branch B is confirmed for the whole tested TXN profile, not conditional.** The anomalous-200 shapes on `Bill`/`JournalEntry` are real and important (they're why §10.5a's response-validation chokepoint exists), but they do not leave open whether void "works" on those entities — it doesn't, on any of the four tested. §16 and §19 are corrected in place below rather than left contradicting this section.

**⚠ Sparse updates silently lose data.** Confirmed: a `Purchase` line memo and a `Bill`'s second line were dropped. This makes §10.3's **round-trip fidelity check load-bearing, not precautionary** — it was previously flagged as the check most likely to be dropped as over-engineering. It is not. **Page 7 must send full entities with complete line arrays and round-trip verify every one.**

**Pagination skip is real, not theoretical.** Reproduced directly: delete an earlier record mid-sweep and a never-deleted, still-existing record silently vanishes from every page. Default order is **descending**, not ascending — an early test bug came from assuming otherwise. The `COUNT`-query checksum mitigation is confirmed viable. **Not yet wired into `QBOSyncClient`** (the slice's sync layer, built 2026-08-16) — that client conservatively marks coverage `.partial` whenever a full page comes back, rather than trusting an unpaginated single-page read, but it does not implement the checksum/offset-integrity machinery itself yet.

**`requestid` idempotency works** for `Purchase` creates: a repeated call returned the identical entity Id and CreateTime rather than duplicating. The design does not *depend* on this (the resolution probe works either way), but it's available.

**Undocumented constraints discovered while fixing the seeding script:**
- `Purchase` **requires `PaymentType`** on create (undocumented)
- **`DocNumber` must be unique per company by default** — governed by `VendorAndPurchasesPrefs.UseCustomTxnNumbers` (vendor-side) and `SalesFormsPrefs.CustomTxnNumbers` (sales-side); these are **two separate settings**
- `DocNumber` has a **21-character maximum**
- **`PrivateNote` is not a queryable field** — this silently broke the seed script's own idempotency check via swallowed optional-chaining
- **Deactivating an account renames it**, appending `(deleted)` to the name

## The DocNumber consequence — important

Because `DocNumber` must be unique per company by default, **the original §11.4 worked example (two purchases sharing DocNo 4471) is unreachable in a default QBO company.** The revision uses real sandbox data (Purchase 145/151) with differing DocNumbers, T1-only match.

**T2's practical value is much lower than assumed.** It only fires when Custom Transaction Numbers is enabled. Design decision: add `.customTxnNumbersForPurchases` as a company feature flag and surface T2's status as **informational, not a coverage gate** — T1/T3 keep the rule fully evaluable. A tier that can never fire and doesn't say so is a silent false-negative source.

This required adding **per-tier introspection to `Rule`** as a general capability, not a special case. **IMPLEMENTED 2026-08-16** — `MultiTierRule` protocol, `RuleTier`/`TierStatus`, `desktop/Sources/Core/RuleEngine.swift` §8.2b, tested in `DuplicatePostedExpenseRuleTests.swift`.

## What's still genuinely unverified about `isVoided` — new finding from building the sync layer, 2026-08-16

`?operation=void` being unsupported on `Purchase` only settles *how a duplicate gets voided* (manually, in the QBO UI). It says nothing about *what the API shows afterward*. Building `QBOSyncClient`'s normalization surfaced that this was never checked: there is no sandbox test in this project, at any point, of reading a `Purchase` back via the API after voiding it manually in the QBO UI. Added to the spike queue as `testManualVoidPurchaseAPIShape` (item 51).

**Update, 2026-08-17: the candidate signal was tested and DISPROVEN, not merely left unverified.** A live `voiceledger-devtool sync-check` run against the real sandbox surfaced Purchase #146 — a legitimate, never-voided $0 edge-case fixture — being misclassified `isVoided: true` by the `TotalAmt == 0` heuristic. `TotalAmt == 0` conflates "voided" with "genuinely a zero-dollar transaction," and does so on real data, not a hypothetical. `isVoidedHeuristic` is now hardcoded `false` in `QBORawPurchase.swift` — an honest "no signal yet," not the old wrong heuristic under cover. **Branch B's resolution path is still not reachable end-to-end against real data — it needed a different reason before, and needs one now.** Spike item 51 is still open: void Purchase #151 manually in the QBO UI and diff the before/after raw JSON to find what actually changes.

## API cost and scale

Most reads are metered "CorePlus" calls under Intuit's usage-based pricing, with a large free monthly allowance (Builder Tier: 500K calls/month). Cache locally, prefer CDC over full syncs, paginate (~1,000 records/page), batch carefully (30 payload max — **we cap at 10**, because 30 simultaneous `UNKNOWN` records is a recovery problem), exponential backoff on 429s.

Intuit is migrating webhooks toward CloudEvents — build for that, not just the legacy envelope. **Webhooks are deferred**; CDC polling ships first as the correctness path.

---

# 7. Data models — mostly PLANNED, core subset IMPLEMENTED for the slice

## Universal Finding Record

Every discrepancy is the same object — duplicates, stale balances, uncategorized transactions, reconciliation gaps, report warnings.

```
Finding
  client_id                     accounting_period
  rule_id + rule_version         title / category
  severity                      confidence
  dollar_exposure               affected_transactions
  evidence                      explanation
  recommended_actions           risk_if_ignored
  detection_capability          automatic | assisted | import_required | unavailable
  resolution_capability         automatic_api | staged_api | manual_qbo | unsupported
  data_source                   qbo_api | imported_file | screenshot | manual_entry
  extraction_method             none | deterministic | ocr_local | claude_vision
  extraction_confidence         coverage (complete | partial)
  source_file / import_date     cross_foot_result
  status                        assigned_to
  client_question               resolution
  resolved_by / resolved_at
  qbo_before_snapshot           qbo_after_snapshot
```

**As of 2026-08-16, `desktop/Sources/Core/Finding.swift` implements a real subset of this** — `id`, `ruleID`/`ruleVersion`, `realmID`, `period`, `title`, `severity`, `confidence`, `dollarExposure`, `evidence`, `proposedActions`, `provenance`, `status`. Not yet modeled: `client_question`, `assigned_to`, `qbo_before_snapshot`/`qbo_after_snapshot`, `extraction_method`/`extraction_confidence` (no import path exists yet — see §9), `risk_if_ignored` as a distinct field. Extend this type rather than creating a parallel one when those are needed.

**Detection and resolution are separate axes.** Finding a problem and being able to fix it via API are different questions.

**Finding IDs are derived, not random** — a digest over `(ruleID, ruleVersion, realmID, period, sorted affected source identities)`. Re-detection of the same problem produces the same ID, which is what makes "unchanged since last sync" answerable and prevents duplicate findings accumulating on every sync. **IMPLEMENTED** — `FindingIDGenerator` in `Finding.swift`, SHA-256 digest, tested for determinism across reruns.

## Other core types

- **`StagedCorrection`** — PLANNED, not built. with `intentID` (stable across every retry, generated at draft), `baselineSnapshot` (the entity **verbatim as read**, never the normalized form), `baselineSyncToken`, `diff`, `consequences`, `ReversalPlan`, `ApprovalRecord`
- **`ApprovalRecord`** — PLANNED, not built. includes `diffDigest`, a hash of exactly what was displayed. If anything changes between approval and submission, the digest no longer matches and the approval is void. *An approval that survives a change to what's being approved isn't an approval.*
- **`ActivityLogEntry`** — **IMPLEMENTED** (a real subset — `desktop/Sources/Core/ActivityLog.swift`). Append-only, no update, no delete — enforced by `ClientStore` exposing no update/delete method on the activity log, not just by convention. Only `.findingDetected`/`.manualCompletionAttested`/`.findingResolved` kinds exist; the full spec's larger `ActivityKind` enum is not yet needed since no staged-write path is built.
- **`MaterialityPolicy`** — **IMPLEMENTED** as a flat-floor policy (`Money` absolute floor, $25 default), per client, but **not yet** part of an evidence watermark (D3 isn't built) and **not yet** versioned.
- **`Rule` / `RuleIdentity` / `DataRequirements`** — **IMPLEMENTED**. `accountingPrinciple` is a **required** field (Training Mode reads it; a rule cannot be added without articulating its justification) — enforced by the initializer, not by convention.
- **`PeriodState`** — PLANNED, not built. Keeps `closedInVoiceLedger` and `closedInQBO` **separate**. Conflating them would be an overclaim.

## Rule registration

**Compile-time only.** A static array in `RuleRegistry`. No runtime discovery, no reflection, no plugin loading — because a rule that silently fails to register produces a page that passes because nothing ran, which is the exact false-green failure mode. **IMPLEMENTED** — `desktop/Sources/Core/RuleEngineActor.swift`'s `RuleRegistry.all`.

`rule(id:version:)` must resolve **historical** versions, because explaining why a finding was raised three months ago requires the rule as it was then. **NOT yet implemented** — `RuleRegistry` currently only exposes `rules(for:)`, no version-scoped lookup. Needed before any rule gets its first version bump.

## Materiality — decided

**$25 flat absolute floor, no percentage-of-revenue component.** Reasoning: this is bookkeeping cleanup, not audit. A duplicate is an error regardless of size, and a revenue-scaled floor would suppress small duplicates on larger clients — backwards for this tool's purpose. Cash and clearing accounts get a tighter `accountOverrides` floor. **`accountOverrides` is specified but not yet modeled in code** — the current `MaterialityPolicy` struct has only `absoluteFloor`.

---

# 8. Reporting architecture — PLANNED

## The report engine (designed early, predates the 12-page structure)

**Core principle, identical to the rest of the app:** deterministic JavaScript/Swift computes every variance, ratio, and severity; the LLM only narrates already-computed numbers.

Metrics computed in code: Gross Margin %, Net Margin %, Total Expenses, MoM and YoY variance per line, Working Capital, Current Ratio, Quick Ratio, Debt-to-Equity, AP, AR, Cash Balance, Average Monthly Burn, Cash Runway.

Severity thresholds, fixed and in code (**not** decided by the AI): cash runway <6mo CRITICAL, <12mo WARNING; net margin <0% CRITICAL, <5% WARNING; current ratio <1.0 CRITICAL; debt-to-equity >2.0 WARNING.

## Chart design — Storytelling with Data principles

The owner specifically referenced Cole Nussbaumer Knaflic's book. Applied rules:
- Every chart has a **stated takeaway** as its title, not a generic label ("Expenses grew faster than revenue this quarter," not "Revenue and Expenses")
- **Direct labels over legends**
- **One accent color** — everything gray/navy except the thing the eye should land on
- **No pie charts, no 3D, minimal gridlines**
- Horizontal bars **sorted by value**, never alphabetical
- Annotate outliers directly on the chart
- Round for the client view; full precision only in the underlying data
- Monospaced/tabular digits everywhere money appears

Charts: KPI header cards · P&L waterfall (Revenue → COGS → Gross Margin → OpEx → Net Income) · 12-month net income trend · margin trend · balance sheet comparison · cash & burn dual-axis · cash runway straight-line projection (**clearly labeled "what happens if nothing changes," not a forecast**) · sorted expense breakdown · signed variance bars.

## Close Package

One bundle at month-end: P&L, balance sheet, cash-flow summary, MoM variance, key warnings, completed checklist, corrections made, unresolved carry-forward items, full client Q&A, Ask Claude history, and who closed the period and when.

**The client-facing PDF must not look like a cybersecurity infographic.** Restrained executive version of the design system — professional, financially credible, readable when printed.

---

# 9. Universal Ingestion — PLANNED

**"If you can get it out of QBO in any form, the app can use it."**

## Three tiers

**Tier 1 — Deterministic parsers** (CSV, OFX, QFX, Excel). No AI. Column mapping with confirm-and-correct, never a silent guess.

**Tier 2 — Apple Vision on-device OCR** (PDFs, screenshots). Runs on the Neural Engine, understands document layout. Two properties make it the default: free, and **the document never leaves the Mac.** macOS 15+ `RecognizeDocumentsRequest` returns structured document data. **UNKNOWN: the owner's actual macOS version was never confirmed.** If macOS 14, Tier 2 falls back to `VNRecognizeTextRequest` plus our own bounding-box column clustering — noticeably worse on tables, and more Tier 3 escalations.

**Tier 3 — Claude vision, escalation only.** Sends the document **off-device**, so it requires explicit per-file consent with the UI saying so plainly. Claude's job is structuring what was read, not deciding what the numbers mean.

## The extraction guardrail

**Extraction is not computation, but a misread number becomes an authoritative number** the moment it enters the rules engine. `$486.20` OCR'd as `$48.620` propagates silently.

- Extracted financial data is **never auto-approved** into a finding that leads to a QBO write
- The verification screen shows extracted table **side by side with the source image**
- Corrections become mapping hints for that document type from that source

## Cross-foot validation — the deterministic quality check

Financial documents have internal arithmetic, so extraction quality is verifiable **deterministically** rather than by trusting a confidence score: do line items sum to subtotals and ending balance? Does beginning + credits − debits = ending? Does the count match a stated count? Are all dates inside the period?

**If a document fails cross-foot, extraction is unreliable and the page cannot go green.** Stronger than any OCR confidence score, and costs nothing but arithmetic.

## Screenshots carry a specific risk

A screenshot is **partial by nature** — one scroll position of a longer list. Screenshot-sourced data defaults to `coverage: partial` unless the document states a total the rows reconcile against. Multi-screenshot stitching is supported with overlap detection.

## What imports unlock

Bank statements · QBO Audit Log export (CSV **or** PDF — sources disagree which, so the layer accepts both and doesn't care) · any QBO report · reconciliation history · Books Review findings (screenshot) · For Review queue (screenshot) · bank rules export · chart of accounts · customer/vendor lists · prior-period workpapers.

**Note:** QBO's main "Export Data" silently omits the audit log, attachments, recurring templates, and bank rules — each needs its own export from its own screen.

**Nothing in this section is built.** No Tier 1/2/3 parser exists in `desktop/Sources/Integrations/Imports/` — it's still the placeholder stub. The slice (§14) deliberately uses QBO API data only, no imports (§11.3's exclusion list).

---

# 10. Security requirements — MUST NOT BE WEAKENED

1. **No secrets in the desktop binary.** QBO client secret and Claude API key live only in the backend.
2. **The desktop client cannot invoke arbitrary QBO endpoints.** Named catalog operations only.
3. **Every new client connection starts in Read-Only Mode.** Writes enabled per-client, explicitly, and re-disableable without disconnecting.
4. **Write access enforced in three places, deliberately redundant:** `ClientScope.accessMode` (UI won't offer approval) · preflight check (client won't submit) · **the backend refuses write-classed operations for a read-only realm** (authoritative — a local flag is a flag a modified client could flip).
5. **Production credentials are deliberately hard to enable.** `resolveQBOCredentials()` requires both `ALLOW_PRODUCTION=true` and the production client ID/secret. Neither is in `.env.example`, `render.yaml`, or any CI config. `test/productionGuard.test.ts` asserts it fails closed.
6. **Never modify production QBO data during development.** Sandbox only. Production and sandbox connections visually unmistakable.
7. **Client isolation by `realmId`**, structurally — never by a mutable "current client" variable.
8. **`.gitignore` correction worth remembering:** the original used broad `*token*`/`*secret*` filename patterns, which silently excluded `tokenStore.ts`, its tests, and `.env.example`. Rewritten to rely on the actual defenses — the redaction filter and secret-scan script — rather than filename guessing. **Filename patterns that look like security and aren't are worse than nothing.**
9. **A log-hygiene canary test** runs a full write path with distinctive values and asserts none appear in captured backend log output.

---

# 11. AI / Claude responsibilities and boundaries

## The contract

**Deterministic code:** calculates amounts, detects duplicates, determines materiality, compares periods, identifies abnormal balances, calculates ratios, assesses reconciliation coverage, ranks risk, decides pass/fail.

**Claude:** explains findings in plain English, describes possible causes, explains proposed choices and consequences, drafts client questions, writes report commentary, answers Ask Claude questions, converts accounting language to owner-friendly language.

Claude receives **compact pre-selected facts** — never a raw company-file dump. Schema-controlled JSON, versioned prompts, all output visibly labeled as draft or guidance.

## The kill switch — non-negotiable

A single toggle disables **all** AI features app-wide. Every deterministic rule, finding, calculation, and report still works with it off.

**This is proven by a test suite, not by assertion:** the entire deterministic suite runs with AI disabled, and every finding, severity, dollar figure, evidence item, and proposed action must be **byte identical** to the AI-enabled run. Only `GeneratedProse` fields differ (present vs. `nil`).

**Why it matters:** if the UI degrades badly with AI off, nobody will ever turn it off and the guarantee becomes theoretical.

**Status as of 2026-08-16: there is no AI integration in the codebase at all yet** — not enabled, not disabled, simply absent. The "byte-identical" guarantee is therefore currently true by construction (`Core` has zero dependency on anything that could call an LLM — enforced by the existing module-boundary test) rather than proven by a kill-switch toggle test, since there's no toggle yet to test. Do not confuse "no AI exists to turn off" with "the kill switch is implemented and tested" — they look similar in a test suite (both produce identical output) but are different claims. Build the real toggle and its test suite when Claude explanations are actually added (§11's Ask Claude panel, still PLANNED).

## Ask Claude panel — PLANNED

At the bottom of every page. Receives the current client/period, that page's findings and evidence, data source, and what's resolved.

**Guardrails, non-negotiable:**
- It can read and explain. **It cannot execute writes, approve findings, or change state** — advisor, not a second control surface.
- Answers visibly labeled as guidance, not authoritative accounting determinations.
- If asked for a number, it cites the deterministic value the engine already computed rather than calculating its own. A `citedValues` check discards any response containing a currency figure not in the cited set.
- Conversations are saved to the client-period record — they're part of the workpaper.

## Model strategy

**Opus for the Ask Claude panel and complex multi-finding explanations.** A cheaper, faster model for routine per-finding narration — the highest-volume, lowest-judgment call in the app. **Per-task configurable, not hardcoded.**

## Voice — PLANNED, deliberately last in build order

Local Whisper (`whisper.cpp`), on-device transcription, local intent parser first, optional LLM fallback for ambiguous phrasing only.

Voice can navigate, filter, search, read findings, draft, and prepare a proposed action. **Voice can never finalize a QBO write** — every write requires a visible on-screen confirmation showing the exact company, period, transaction, and change.

Built last on purpose, so a voice bug never blocks the rest of the app. Voice was the feature that failed in both prior prototype attempts (Base44 and Google AI Studio).

---

# 12. UI/UX design philosophy — tokens IMPLEMENTED, slice-scoped components IMPLEMENTED, remaining pages NOT

## Visual language: "Midnight Neon Operations Console"

Dark navy (never pure black), thin cyan borders, restrained glow, technical detail used only where it explains a real relationship. Should feel like a financial command center — intelligent, precise, credible. **Not a gaming dashboard.**

## The rule that matters most

**Accent colors and status colors are separate vocabularies.** Cyan glow on a selected row means "this row is selected." It does **not** mean "this row is fine." Enforced in code: status hues live in a `private` enum inside `VLStatus.swift`, environment hues in a separate `private` enum inside `VLEnvironment.swift`. **Neither file can see the other's constants** — verified by attempting a cross-file access and confirming it fails to compile.

## Green — the four preconditions

`VLStatus.verified` may only render when **all four** hold: required data was present · the check completed · the result is current · no exception was found.

Three enforcement layers: **type level** (there is no `.success` case — the only green is named `verified`) · **rule engine** (three outcomes, D1 — now IMPLEMENTED, see §5) · **UI** (`VLCoverageStrip` puts DATA AVAILABLE and CHECKS COMPLETED to the *left* of EXCEPTIONS FOUND, so a page answers "can I trust this screen?" before "what did it find?").

A **green-audit test suite** enumerates every path to green per page and asserts green is unreachable with: no data · partial coverage · stale data · unhealthy connection · `.cannotEvaluate` · failed cross-foot · screenshot source with no stated total. **Not yet built as a dedicated suite** — the slice's `DuplicatePostedExpenseRuleTests.swift` and `RuleEngineGatingTests.swift` cover the equivalent ground for `VL-DUP-EXP-001` specifically (partial coverage, connection-unhealthy-as-partial-coverage, zero-findings-is-green), but there is no cross-page enumeration yet since only one rule and no full page exists.

## Status vocabulary

| Status | Treatment |
|---|---|
| `.verified` | Green + checkmark |
| `.reviewNeeded` | Amber + magnifier |
| `.urgent` | Coral + alert triangle |
| `.informational` | Blue + info (dedicated status blue `#4FA3E8` — **not** the cyan accent) |
| `.awaitingClient` | Violet + speech bubble |
| `.notChecked` | Gray + clock (filled pill) |
| `.actionRequired` | Gray **dashed outline** + upload |

`.notChecked` and `.actionRequired` share a hue, differentiated by **form** — hue alone would make them indistinguishable.

## Environment is a third vocabulary

Neither accent nor status. **Production:** solid bar on a dedicated near-black surface (`#050B14`) with a shield — serious by form and permanence, **not coral**. Coral is reserved for `.urgent`; production is the permanent normal state once live, and a coral badge on screen every working hour would dull coral for actual risk. **Sandbox:** diagonal hazard stripes, which appear nowhere else in the system and survive colorblind viewing.

## Accessibility — IMPLEMENTED and enforced

- `VLStatusPill` has **no initializer producing a bare colored dot.** The label is not optional. Status-by-color-alone is structurally impossible.
- WCAG AA contrast enforced by `ContrastTests.swift` over a 45-pair catalog. `textMuted` was raised to **`#7E92AA`** (5.03:1 worst case) after measurement showed the original `#71849B` failed at 4.19:1 on `surfaceCard`. `blue #2788D9` is documented as **non-text-safe** and excluded from the valid-pairs catalog.
- **OPEN:** violet `#9B6EF3` passes at **4.52:1** — a 0.02 margin with no headroom. `#A67CF5` was recommended (5.22:1, same hue). **UNKNOWN whether this was applied** — still genuinely unresolved; nothing in the Claude Code session that built the slice touched `VLColor.swift`'s violet value. Ask the owner or check `VLColor.swift` directly before relying on either answer.
- SF Symbols, not Lucide (Lucide is a web library). System font at `.width(.condensed)`, since Barlow Condensed isn't on macOS.
- Reduce Motion honored via `VLMotion.respecting(_:_:)`, which returns `nil` under the setting so honoring it is the default path.
- Condensed type is **display only** — never paragraphs, inputs, or table data.

## Two UI states that were nearly missed

**The `UNKNOWN` write state** — a write submitted, outcome unknown, entity locked. The most dangerous state in the app; a retry there double-voids a transaction. Renders as a **blocking banner plus a persistent global indicator**, and the button says **"Run resolution probe," never "Retry."** Keep that wording locked. **Not yet built in UI** — no staged-write path exists yet for this state to attach to (see §14: Branch B makes no QBO write, so `UNKNOWN` has no trigger in the shipped slice).

**The AI-off state for every AI-touching surface** — specified per-surface, and covered by a UI-layer sub-suite of the kill-switch tests. **Not applicable yet** — see §11's note that no AI integration exists in the codebase at all.

---

# 13. Current implementation state — CORRECTED 2026-08-16, see the editorial note at the top of this file

## IMPLEMENTED and verified

**Phase 1 steps 1.0–1.2, both fronts verified.**

- **Repo skeleton** — `desktop/` (Swift package) and `backend/` (Node/TS)
- **Module-boundary lint** — real, wired into `swift test`, source-scan enforced
- **Spike harness + seeding** — `backend/spike/`, `@CapabilityTest` pattern in TS, five `Seeds/` files, idempotent `seed.ts` with incremental manifest saves and `DocNumber`-based lookup
- **Thin backend, read-only** — OAuth exchange/refresh against Intuit's real endpoints, AES-256-GCM encrypted refresh tokens, opaque realm-bound sessions, 6-operation read-only catalog with `assertReadOnlyCatalog()`, structured logging with redaction backstop, per-realm rate limiting, sandbox-only production guard
- **DesignSystem tokens** — `VLColor`, `VLStatus`, `VLEnvironment`, `VLStatusPill`, `VLContrast`, `VLMotion`, `VLTypography`
- Git initialized with a corrected `.gitignore`

**Phase 1 step 1.6 — the vertical slice (Branch B). Committed, not "in progress," as of this file's filing.** This corrects the original draft's "IN PROGRESS... uncommitted at ~+1,046/−117 lines" — that was accurate when written and stale within the same day. What actually shipped, across five commits (`49996f2`, `003b9b5`, `bca8c52`, `d0e838a`, `e9d78d8`):

- **`desktop/Sources/Core/`** — domain types (`AccountingPeriod`/`AccountingDate`, `LedgerTransaction`/`Provenance`/`NormalizedDataSet`/`Coverage`), the rule engine (`RuleIdentity`/`RuleClass`/`RuleTier`/`TierStatus`/`MultiTierRule`, the `RuleEngine` actor implementing §8.5's sequence including the new §8.2a relationship-before-category gating), `Finding`/`Confidence`/`Severity`/`ProposedAction`/`GuidedProcedure`/`ActivityLogEntry`, and `DuplicatePostedExpenseRule` (`VL-DUP-EXP-001`, all three tiers, all §11.2 exclusions).
- **`desktop/Sources/Integrations/QuickBooks/QBOSyncClient.swift`** — fetches `Purchase`+`Preferences` via the existing read-only catalog and normalizes into Core's shape. **Flagged, not hidden:** the `isVoided` mapping is an unverified heuristic — see §6's note above and spike item 51.
- **`desktop/Sources/DB/ClientStore.swift`** — per-realm JSON persistence for findings and the activity log (a scoped-down substitute for D2's SQLite design — see §5).
- **`desktop/Sources/VoiceLedgerUI/`** (new library target) and **`desktop/Sources/VoiceLedgerApp/`** (new executable target) — findings list (Page 3 shell), finding detail, guided-procedure/attestation view, activity log view, wired into a real running app.
- **41/41 tests passing**, all offline (no network) — 10 Core rule/engine tests, 5 sync-normalization tests, 5 persistence tests, plus the pre-existing 21 (Money, Contrast, module-boundary, secret-scan).

**What's still explicitly unverified about this slice, flagged rather than claimed:**
- The `isVoided` heuristic (§6, spike item 51) — **update 2026-08-17: run once, DISPROVEN, fixed to a safe `false` default, still no real signal found.** See §6.
- The UI was never visually verified — no screenshot tool for a native macOS window was available in the session that built it. It was confirmed to build and launch without crashing; nothing about its actual rendered appearance or interaction flow is confirmed. Still true as of 2026-08-17.
- **Update 2026-08-17: a real live-sandbox sync-and-evaluate run DID happen**, via a new `voiceledger-devtool sync-check` command — health check green, 10 real `Purchase` records synced, and `VL-DUP-EXP-001` fired correctly against real data (T1 on the documented #145/#151 pair, and an unplanned but correct T3 match on #153/#154). What still hasn't happened: clicking through Approve → guided procedure → attestation → resync in the actual UI, since that requires the UI (still visually unverified, above) and a manual QBO-UI void (spike item 51, still open).
- Pagination (§2.6) is not wired into `QBOSyncClient` — coverage is conservatively `.partial` on any full page as a placeholder, not a real offset-integrity check. Confirmed via the live run: this period's 10 transactions came back as one page, so coverage read `.complete` — this path hasn't yet been exercised against a period large enough to actually hit the page boundary.

**UI scope decision made, and honored:** full logic + minimal UI, fenced to exactly what §11.2 lists. What was explicitly NOT built, correctly: AppShell, left navigation, workflow progress spine, Firm Cockpit, Next Best Action, Ask Claude panel, the staging-queue view (not needed — Branch B has no staged write, §14).

## NOT STARTED

Every one of the 12 workflow pages except the slice's minimal Page 3 shell · Universal Ingestion (all three tiers) · voice · reporting and Close Package · Firm Cockpit · all rules except `VL-DUP-EXP-001` · spike Waves 2 (negatives) and 4 (awkward, needs manual sandbox setup) · the staged-write path (`StagedCorrection`, preflight, `UNKNOWN`, resolution probe) in actual code — fully specified, not implemented, since Branch B never exercises it (§14, §16)

---

# 14. The vertical slice — Branch B

**Scope:** one sandbox company, `Purchase` entity only, one accounting period, QBO API source only (no imports).

**Rule `VL-DUP-EXP-001`, three tiers:**
- **T1 exact** — same vendor · same `TxnDate` · same `TotalAmt` · same payment account → `.high`
- **T2 reference** — same vendor · same `TotalAmt` · same non-empty `DocNumber` → `.high` (**conditional on Custom Transaction Numbers being enabled; inert-but-visible otherwise**)
- **T3 near-date** — same vendor · same `TotalAmt` · same payment account · ±3 days → `.medium`

**Severity is a function of `dollarExposure` against materiality — not of tier.** Severity is how damaging, confidence is how sure. Keeping them independent is first exercised here.

**Exclusions applied after detection and recorded as suppressions** (suppressed, not vanished): already voided · already resolved/dismissed · client memory marks it legitimately recurring · below materiality floor.

**Explicitly not excluded, but flagged:** transactions in a closed period. They are detected and carry `ResolutionConstraint.closedPeriod`. Failing to detect a closed-period duplicate would be a false green.

**Branch B resolution path:** approve → guided manual procedure → attestation → activity log entry marked **attested rather than verified**. Once the duplicate is voided in QBO and Voice Ledger resyncs, the `isVoided` exclusion auto-resolves the finding with no write of its own. **Branch B is a clean path, not a degraded one.**

**Branch B explicitly does NOT fall back to hard delete.** Delete is permanent. Trading a destructive operation for slice completeness would be exactly the wrong call.

**Acceptance criteria** are §11.5's, with Branch B substitutions (11b, 12b). The ones that must not be softened: forced pagination checksum failure → **gray, not green** · zero duplicates with complete coverage → green · zero duplicates with no sync → **gray** · AI kill switch produces byte-identical findings · a Claude explanation containing a currency figure not in `citedValues` is **discarded** · second sandbox company with identical data produces findings referencing only its own transactions · golden fixtures pass with no network.

**As of 2026-08-16, all of the above except the live-sandbox and visual-verification pieces has been built and offline-tested** — see §13's corrected status. The isolation criterion was tested as two different `RealmID`s against the same in-memory data, not two live sandbox companies. The golden-fixture criterion used inline Swift literals as fixtures rather than the on-disk `Tests/Rules/VL-DUP-EXP-001/case-NN/{input,expected}.json` layout §8.7 describes — documented in the test file as a scoped-down but still-real substitute (deterministic, offline, versioned in source control), worth revisiting once a second rule exists and a shared fixture format has a real payoff.

---

# 15. Corrections pending at handoff — apply before/with the slice

**Status: both A and B are now applied to the docs (`docs/phase-0/10_STAGING_APPROVAL_AUDIT.md`), 2026-08-16. Neither is implemented in backend code yet — the slice needed no QBO write, so there was nothing to wire the chokepoint into.**

**A. HTTP 200 is not success.** Validate every write response on its **body**, not its status. A fault element anywhere in a 200 is a failure. An empty or structurally unexpected body is `UNKNOWN` → resolution probe. Single chokepoint in backend response handling so no operation can forget. Add a structural test asserting no code path treats 2xx as success without body validation. **This also changes the probe's step 1** — it should first ask whether the original response was well-formed, since an anomalous 200 is the case where we least know what happened. *Documented as `§10.5a` with a `classifyWriteResponse` design and a revised probe numbered step 1. Not yet backend code.*

**B. Sparse updates lose data.** Mark §10.3's round-trip fidelity check explicitly as **verified-necessary** with the fixture reference, so nobody removes it later as redundant. Page 7 must use **full-entity updates with round-trip verification**. **This question was answered, not left open:** an assessment was written into `docs/phase-0/CAPABILITY_CLASSIFICATION.md` (Page 7 section) — recommendation, not a unilateral decision: keep Page 7 as a real API write path for single-field reclassification, add a QBOA hand-off as the recommended path specifically for line-level batch edits where the round-trip cost is highest. Still a Phase 2 decision, not settled, but no longer an open question with no answer on record.

**C. Two interface accommodations — design only, do not build the rules. Both landed as design, 2026-08-16:**
- **Relationship-before-category gating.** `RuleIdentity` gained a `ruleClass: RuleClass` field (`.relationship`/`.categorization`) and the engine (`RuleEngineActor.swift`) implements the gating branch — exercised by a fixture-only relationship rule in tests, since no real relationship rule ships yet. See `docs/phase-0/08_RULE_ENGINE.md` §8.2a.
- **Many-to-one matching contract.** `StatementMatch` designed with `bankSide`/`ledgerSide` as arrays (sets), `MatchReason`, `MatchTolerance`, `netDifference`. See `docs/phase-0/09_INGESTION_PIPELINE.md` §9.11. No matcher implementation exists — correctly, since no import pipeline exists yet either (§9).

---

# 16. Features PROPOSED but not approved

Filed as backlog. **Do not build without explicit approval.** As of 2026-08-16, `CLEANUP_MODE.md`, `REDDIT_FEEDBACK_ASSESSMENT.md`, and `STRATEGY_MERIDIAN.md` are filed in full under `docs/backlog/` (with a `README.md` index) and referenced from `docs/phase-0/00_OVERVIEW.md` — not just described here. New rule IDs below are reserved in `docs/phase-0/08_RULE_ENGINE.md` §8.8 with phase assignments.

## From the cleanup analysis
- **Cleanup Assessment page** (Type A, read-only) — months unreconciled per account, uncategorized balances, duplicate counts, miscoded CC payments, opening-balance integrity, estimated hours and price band. **Doubles as a sales document.** Recommended as the first page after the slice.
- `VL-CC-PAYMENT-001` — credit-card payment coded to an expense account. **QBO's own AI actively suggests this error.** Double-counts expenses. Highest frequency, highest dollar impact. **Note:** the Reddit voice-of-customer analysis identifies this as the same error as `VL-RELATIONSHIP-002` below — flagged as an unresolved overlap in `08_RULE_ENGINE.md` §8.8, not silently merged.
- `VL-PAYROLL-LUMP-001` — payroll processor net amount coded to a single expense line
- `VL-VENDOR-MISMATCH-001` — QBO's cleaned vendor name vs. the original bank description (this is what the Right Tool Chrome extension exists to display; ours can detect and rank)
- `VL-PREPAID-PERIOD-001` — payment whose attached document shows a service period after the transaction date
- `VL-OPENING-BAL-001` — opening balance double-count
- **Reconciliation gap map** — accounts × months grid

## From the Reddit voice-of-customer analysis
- **Transaction Relationship Guard** — *the strongest single idea contributed to this project.* Ask "is this the right kind of transaction?" (match / CC payment / transfer / grouped deposit / split / refund / owner equity) **before** "is the category right?" Every catastrophic error lives in the first set. Reserved as `VL-RELATIONSHIP-001` through `-006`, one per branch — see §15.C above for the interface accommodation this already justified.
- **Many-to-one and one-to-many statement matching** — a correctness requirement, not a feature. Without it, a client's normal Stripe settlement is reported as missing every month and the page gets ignored. Interface designed, §15.C.
- **Account-Month Control Grid** — with the rule: **never show a percentage without its denominator.** "8 of 10 required controls complete — two accounts lack August statements," not "85% ready."
- **Client Accounting Control Profile** — versioned, watermark component. *A $900 purchase might be an expense for one client and a fixed-asset review item for another.*
- **Balance-sheet evidence workpapers** — evidence required per material account; **prior-year anchor** (does the opening balance sheet agree with the prior tax return?) is the highest-value piece. **Flag the discrepancy, never invent the correcting journal entry.**
- **Sensitive-write risk tiers** — low/moderate/high/blocked. The real gap: **is the transaction already reconciled?** Changing it breaks the reconciliation. Spike item added (`testReconciledTransactionDetection`, item 50) — not yet run.
- **Client Exception Packet** — grouped monthly version of the Client Question Builder
- `VL-CLOSED-PERIOD-DRIFT-001` — **changed-after-close detection.** Snapshot the closed period's trial balance at close; recompute on every sync; flag movement. Needs no audit log. **This is the finding that protects the bookkeeper** when a client says "these numbers changed."
- `VL-FORCED-RECON-001` / `VL-OBE-BALANCE-001` — forced reconciliation (Reconciliation Discrepancies balance) and Opening Balance Equity balance; both classic inherited-books signatures
- `VL-AUTOADD-RULE-001` — bank rules with auto-add enabled posting without review

## Spike items — status corrected 2026-08-16 (see §6's note)
- `testCategorizationProvenance` — is QBO's rule-vs-AI-vs-human categorization source exposed? **Filed, not run** (`SPIKE_QUEUE.md` Wave 5, item 49).
- `testReconciledTransactionDetection` — can the API tell us a transaction is reconciled? **Filed, not run** (item 50).
- `testManualVoidPurchaseAPIShape` — **new item, not in the original draft of this handoff.** What does the API show for a `Purchase` voided manually in the QBO UI? Discovered as a gap while building `QBOSyncClient` — see §6. Item 51.
- ~~Void on `Bill` / `JournalEntry` / `BillPayment` — partially run; still open~~ **corrected: this was fully run, not partial, and it is resolved, not open.** All three confirmed unsupported (§6). The anomalous-200 shapes on `Bill`/`JournalEntry` are a real, separate, already-addressed finding (§15.A's response-validation chokepoint), not an indication the void question itself is unanswered.

---

# 17. REJECTED — and why

| Rejected | Why |
|---|---|
| **Copying Meridian (Pilot.com's autonomous close)** | Their moat is 187,000 months of closed books as training data since 2017. Cannot be replicated. Their model also assumes the reviewer is an experienced accountant — the opposite of this user. **Their model requires a competent reviewer to be safe; ours creates one.** |
| **The Meridian QuickBooks MCP connector** | Built by Pilot.com, which also runs a direct bookkeeping business — a competitor. Also write-access with a large blast radius (create/delete arbitrary transactions and journal entries). |
| **Datarails** | ~$24K+/yr enterprise FP&A, sold to finance teams. Category mismatch for a solo bookkeeper. |
| **Electron / Tauri** | Chose native SwiftUI. Accepted cost: no prototype code reuse. |
| **Building a better categorization engine** | QBO does it in the workflow where categorization happens, through a bank feed the API cannot even see. Our job is **auditing what QBO's AI already did**, not competing with it. |
| **Generic anomaly detection** | QBO ships this now. Redundant. |
| **A separate "Stop & Ask Client" subsystem** | Owner explicitly declined. Client-blocked items are a tagged finding. |
| **Full AR/AP workflows** | The owner does not do this work. |
| **Payroll, inventory, multicurrency, custom fields, sales-form config** | One-time QBO admin tasks, not recurring monthly work. |
| **Hard delete in the operation catalog** | Permanent and irreversible. Deliberately absent so it is structurally unreachable. |
| **Beancount as the staging ledger** | Considered as a plain-text double-entry staging layer. Left undecided, then superseded by the local staging design. |
| **Rebuilding QBO's "group and sort by column" batch categorization** | QBO does it well, in the right place. Build the *plan*, not the tool. |
| **Batch size of 30** | QBO's max. We cap at **10** — 30 simultaneous `UNKNOWN` records is a recovery problem. |

---

# 18. Things Claude Code must NEVER remove or break

1. **The three-outcome `RuleOutcome`.** Collapsing `.pass` and `.cannotEvaluate` reintroduces the false-green failure mode. — **IMPLEMENTED**, `Core/RuleEngine.swift`.
2. **The four green preconditions**, and the single guarded construction site for `FindingColor.green`.
3. **`ResolutionCapability.automaticAPI` is never constructed.** There is a structural test. — Note: the shipped `ResolutionKind` enum only has `.manualQBO`/`.stagedAPI`; there is no `.automaticAPI` case to construct in the first place, which is a stronger guarantee than a runtime-checked test. Keep it that way — do not add the case "for completeness."
4. **No `markStale` function.** Staleness is derived. — Still true; D3 isn't built yet at all (§5), so there's nothing to have added one to.
5. **`LedgerRepository` exposes no method taking a `RealmID`.** The question cannot be asked.
6. **No untyped logging API in the backend.**
7. **Every `Rule` has a non-empty `accountingPrinciple`.** — **IMPLEMENTED**, enforced at `RuleIdentity` construction.
8. **Every rule has at least one `.cannotEvaluate` golden fixture.** — **IMPLEMENTED** for `VL-DUP-EXP-001` (`case05PartialCoverageNeverPasses`, `case07EngineCoverageGate`). Keep this true for every future rule.
9. **`Scoped.rebind` appears in no production target.**
10. **No `Double` in any money path under `/core`.** — **IMPLEMENTED**, `Money` uses `Int64` minor units throughout; `QBOSyncClient.minorUnits(from:)` converts QBO's `Decimal` at the integration boundary, never inside `Core`.
11. **`VLStatusPill` has no bare-colored-dot initializer.** The label is not optional.
12. **There is no `.success` color.** The only green is `.verified`.
13. **Status hues and environment hues stay in separate `private` enums in separate files.**
14. **The round-trip fidelity check in preflight.** Verified necessary — sparse updates lose data. Explicitly marked verified-necessary with fixture citation in `10_STAGING_APPROVAL_AUDIT.md`, 2026-08-16.
15. **`UNKNOWN` never auto-retries.** The button says "Run resolution probe," never "Retry."
16. **`SUBMITTED` is journaled and flushed before the network call**, never after.
17. **The AI kill switch, and the byte-identical test that proves it.** — Not built yet at all (§11); when it is, this rule still applies.
18. **The terminology:** *Baseline Evidence Pack* (not backup) · *Voice Ledger Health Scan* (not Books Review) · *Activity & Correction Log* (not Audit Log). Each name exists because the alternative overclaims. `ActivityLogEntry`'s Swift type name already honors this.
19. **Production credentials fail closed.**
20. **The matrix is generated from tests, never hand-edited.** A human cannot type VERIFIED.

**Item to add, from the slice build:** **21. A rule must never claim `.pass` on incomplete coverage, even for a trivial "zero transactions" input.** This is exactly item 1's principle, but it was caught as a real bug during the slice build (`DuplicatePostedExpenseRule` initially did this on an empty-transaction, partial-coverage input) — worth its own line because "the engine catches it" is not sufficient; the rule itself must be correct, not merely backstopped.

---

# 19. Outstanding decisions and next steps — corrected 2026-08-16

## Blocked on the owner
- **Prototype repo URL** — `01_REPO_INVENTORY.md` still blocked. Still true; the three backlog strategy documents (`CLEANUP_MODE.md` etc.) were located and filed in this session, but they are not the prototype repo — a separate, still-missing item.
- **macOS version** — determines Tier 2 OCR quality and whether the `VNRecognizeTextRequest` fallback is needed. Still unconfirmed as far as any repo artifact shows, though the Swift toolchain work this session implies at least macOS 15-class tooling is present (full Xcode installed, `swift test` passing) — that's evidence about the *development* machine, not necessarily a confirmed answer for the *target* minimum version question in `OPEN_QUESTIONS.md` Q4.
- **Violet contrast fix** — whether `#A67CF5` was applied. **Still unknown** — check `desktop/Sources/DesignSystem/VLColor.swift` directly; nothing in the slice-building session touched it either way.

## Open technical questions
- Is **Page 7** still worth building as designed, given sparse-update data loss? **Answered as a recommendation** (§15.B) — not settled, but no longer unaddressed.
- ~~Does void work on `Bill` / `JournalEntry` / `BillPayment`?~~ **Resolved, not open — corrected from the original draft.** All three confirmed unsupported for void; Branch B applies to the whole tested TXN profile. See §6.
- Is **categorization provenance** (rule vs. AI vs. human) exposed via API? Still genuinely open — filed as spike item 49, not run.
- Can the API tell us a transaction is **reconciled**? Still genuinely open — filed as spike item 50, not run.
- Are **T1's fixtures rich enough** now that T2 is largely inert? Still correctly deferred — no golden fixture set exists yet in the on-disk sense (§14's note on inline-Swift-fixtures-as-substitute).
- **New, from the slice build:** does a manually-voided `Purchase` actually show `TotalAmt == 0` (or some other signal) via the API? **Half-answered 2026-08-17: `TotalAmt == 0` is confirmed NOT a reliable signal** (it false-positived on a legitimate $0 fixture against live data). Still genuinely open what the real signal is — spike item 51, gates whether Branch B's resolution path is trustworthy against real data.

## Recommended sequence
1. ~~**Finish the vertical slice** (Branch B, fenced UI scope)~~ — **the logic/sync/persistence/UI build is done and committed as of 2026-08-16; a real live-sandbox sync-and-evaluate pass ran successfully 2026-08-17** (see §13). What's still left: finish spike item 51 (a real `isVoided` signal — `TotalAmt == 0` is now confirmed wrong, not just unverified), and get eyes on the actual rendered UI (no screenshot tool was available in either session).
2. **Cleanup Assessment** — read-only, no writes, highest immediate business value; it prices engagements and doubles as a sales artifact
3. **Get the first client**
4. Reprioritize everything else against that client's actual books

**Deliberately not committed past step 2.** Half the backlog will matter more than expected and some of it won't matter at all, and no amount of planning will reveal which before real data does.

---

# 20. Context that would otherwise be lost

## The scope-discipline problem — read this before adding features

Over the course of the originating conversation, the spec grew through **four substantial rounds of feature additions** while the first vertical slice — one rule, end to end — remained unbuilt. The features are individually good. Collectively they are several months of work.

**The standing guidance:** the spec is frozen. `CLEANUP_MODE.md` and `REDDIT_FEEDBACK_ASSESSMENT.md` are backlog, not plan. New ideas get filed, not built. The app gets meaningfully better the moment it runs against one real client's messy books, and it cannot until a client exists.

**Update, 2026-08-16: the slice got built.** This section's warning did its job — worth noting explicitly, since a standing guidance document that never records a win reads as pure caution and nothing else. The discipline held: five backlog-adjacent instructions arrived in the same session as the slice approval (T2-conditional design, two corrections, two interface accommodations, three backlog documents), and none of them became a build task — they were filed, designed at the interface level only, or answered as a reported assessment, exactly as instructed. The next test of this discipline is whatever arrives after this handoff file is read.

## The owner's business context

Building this alongside several other ventures — an HVAC business, government contracting, a drone photography business, and a Toyota internet sales role — while studying for CompTIA certs. **Time is the scarce resource.** Bias toward fewer, better-finished things.

**Pricing note worth preserving:** the owner planned $300–500 cleanups. A CPA running a 40-person firm charges **$475 just to assess** a file before quoting, and $750–1,200/month for ongoing bookkeeping. The Cleanup Assessment exists partly to let the owner *show* a client why an engagement is $900 rather than guess at $300 and eat the difference.

## Working patterns that proved valuable

**Adversarial review across models.** Much of this design was strengthened by running it past ChatGPT and bringing the critique back. Real catches included: the Base44 SDK method being wrong, the missing thin backend, the QBO API limits, the Transaction Relationship Guard, and many-to-one matching. **This is worth continuing.**

**Verify before trusting, including yourself.** The best moments in this project were self-caught errors: recognizing that a pagination test assumed ascending order when QBO returns descending, and that a "no bug found" result was therefore meaningless; catching that `.informational` was using an accent hue as a status color mid-way through fixing exactly that class of error; independently recomputing contrast ratios before applying a recommended fix; catching, via a test rather than by inspection, that the duplicate-expense rule could claim `.pass` on incomplete coverage. **A false negative recorded as a finding is worse than no test.**

**Report before acting on anything with downstream consequences.** This was an explicit instruction and it worked. When the void test came back DISPROVEN, the correct behavior was to record it and stop — not to redesign around it.

**A handoff document is itself subject to the project's own honesty rule.** This file was drafted with good status labels but went stale within the same day on three points (§13, §16, §19) because the drafting conversation and the building session were different contexts. The fix wasn't to silently patch those sections — it was to correct them in place with a visible note explaining what changed and why, the same standard this document asks of the capability matrix (§6) and the green-status rule (§12). A handoff doc that can't apply its own rule to itself isn't trustworthy about anything else in it either.

## The philosophical core, restated

Meridian's model: **AI produces finished books; a competent accountant reviews.**
Voice Ledger's model: **deterministic code detects; the human decides; AI only explains.**

Both are coherent. They are not two implementations of the same idea — they are opposite bets about where trust comes from. Meridian's works because of nine years of production data. Ours works because it doesn't require any.

Every design decision in this document traces back to one asymmetry: **this app's user is still building the judgment that other tools assume he already has.** That is why green means verified, why the AI never computes, why nothing writes without review, why a Type C page is a legitimate page, and why Training Mode exists.

Do not optimize that away in the name of automation.
