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

**RESOLVED 2026-08-17: `01_REPO_INVENTORY.md` is N/A, permanently — no prototype repo exists.** This build is fresh; the owner confirmed there's no codebase to retrieve. The "when it arrives" framing below described an assumption that turned out to be wrong — kept for historical record, not as a pending task. Do not re-open this or go looking for a prototype repo in a future session.

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

## `isVoided` detection — RESOLVED 2026-08-17, spike item 51

`?operation=void` being unsupported on `Purchase` only settles *how a duplicate gets voided* (manually, in the QBO UI). It says nothing about *what the API shows afterward*. Building `QBOSyncClient`'s normalization surfaced that this was never checked. Added to the spike queue as `testManualVoidPurchaseAPIShape` (item 51).

**A `TotalAmt == 0` candidate signal was tested first and DISPROVEN, 2026-08-17.** A live `voiceledger-devtool sync-check` run against the real sandbox surfaced Purchase #146 — a legitimate, never-voided $0 edge-case fixture — being misclassified `isVoided: true` by that heuristic. `TotalAmt == 0` conflates "voided" with "genuinely a zero-dollar transaction," and does so on real data, not a hypothetical.

**The owner then manually voided Purchase #151 in the live sandbox UI (2026-08-17), and the real signal was found and verified.** QBO adds a top-level **`"status": "Voided"` field, present only on voided Purchases** — entirely absent (not `false`, not `null`) on every non-voided Purchase checked, including #146. `QBORawPurchase.swift`'s `isVoided` now decodes this field directly, replacing the hardcoded `false`. **Confirmed end-to-end, not just in offline tests:** a `sync-check` run immediately after the manual void showed #151 as `voided=true`, and the `VL-DUP-EXP-001` finding for the #145/#151 pair disappeared from the rule's output — resolved via the `isVoided` exclusion, zero QBO writes made by Voice Ledger. Branch B's full resolution path (detect → approve → manual QBO action → resync → resolved) is now proven against real data. See `docs/phase-0/02_QBO_CAPABILITY_MATRIX.md` row 13.3 for the full before/after JSON.

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

**Tier 2 — Apple Vision on-device OCR** (PDFs, screenshots). Runs on the Neural Engine, understands document layout. Two properties make it the default: free, and **the document never leaves the Mac.** macOS 15+ `RecognizeDocumentsRequest` returns structured document data. **Checked 2026-08-17: this machine runs macOS 26.6.1** — comfortably above the 15+ floor, so `RecognizeDocumentsRequest` is safe here. Not an independent confirmation of every future deployment machine — see `OPEN_QUESTIONS.md` Q4's note on the limits of that. If a lower-OS machine turns up later, Tier 2 falls back to `VNRecognizeTextRequest` plus our own bounding-box column clustering — noticeably worse on tables, and more Tier 3 escalations.

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
- **RESOLVED 2026-08-17:** violet was checked directly and confirmed still `#9B6EF3` (4.52:1, no headroom) — the recommended `#A67CF5` (5.22:1, same hue) had never been applied across either drafting session. Applied now to `VLColor.swift` and the duplicated literal in `VLContrast.swift`'s declared-pairs catalog; `ContrastTests.swift`'s full audit passes.
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
- **`desktop/Sources/Integrations/QuickBooks/QBOSyncClient.swift`** — fetches `Purchase`+`Preferences` via the existing read-only catalog and normalizes into Core's shape. `isVoided` mapping: **verified 2026-08-17** (spike item 51) — decodes QBO's `status: "Voided"` field, confirmed against real manually-voided data. See §6's note above.
- **`desktop/Sources/DB/ClientStore.swift`** — per-realm JSON persistence for findings and the activity log (a scoped-down substitute for D2's SQLite design — see §5).
- **`desktop/Sources/VoiceLedgerUI/`** (new library target) and **`desktop/Sources/VoiceLedgerApp/`** (new executable target) — findings list (Page 3 shell), finding detail, guided-procedure/attestation view, activity log view, wired into a real running app.
- **41/41 tests passing**, all offline (no network) — 10 Core rule/engine tests, 5 sync-normalization tests, 5 persistence tests, plus the pre-existing 21 (Money, Contrast, module-boundary, secret-scan).

**What's still explicitly unverified about this slice, flagged rather than claimed:**
- ~~The `isVoided` heuristic~~ — **RESOLVED 2026-08-17** (spike item 51): real signal found and verified (`status: "Voided"`). See §6.
- ~~The UI was never visually verified~~ — **RESOLVED 2026-08-17.** The owner ran `VoiceLedgerApp` directly (this session minted the session token and launched it; no screenshot tool existed in this environment, so the owner screenshotted their own screen instead) and walked all three screens against real live data: the findings list (SANDBOX badge, coverage strip in the correct DATA/CHECKS/EXCEPTIONS order, one correct finding), the finding detail view (evidence, the exact §11.4 "Voice Ledger cannot complete this write" copy, consequences, Approve/Dismiss with no staged-write option ever shown), and the guided-procedure/attestation view (steps, the violet-accented pitfalls card rendering correctly with the newly-fixed contrast color, done-criteria, and the exact "this records your attestation — it does not verify the result" copy from criterion 14). All three matched the design spec exactly. This is the last item from `NEXT_INSTRUCTION.md`'s Part 5 that was still open — it's now closed.
- **Update 2026-08-17: a real live-sandbox sync-and-evaluate run happened**, via a new `voiceledger-devtool sync-check` command — health check green, 10 real `Purchase` records synced, and `VL-DUP-EXP-001` fired correctly against real data (T1 on the documented #145/#151 pair, and an unplanned but correct T3 match on #153/#154). **The owner then manually voided #151 in the QBO UI and a resync confirmed the whole Branch B resolution path** — the #145/#151 finding disappeared, resolved via the `isVoided` exclusion, zero writes from Voice Ledger. **The owner then also walked the UI itself against this live data (see above)** — every layer of the slice (Core logic, sync/normalization, persistence, and now the rendered UI) is verified against real data, not just offline fixtures.
- Pagination (§2.6) is not wired into `QBOSyncClient` — coverage is conservatively `.partial` on any full page as a placeholder, not a real offset-integrity check. Confirmed via the live run: this period's 10 transactions came back as one page, so coverage read `.complete` — this path hasn't yet been exercised against a period large enough to actually hit the page boundary.

**UI scope decision made, and honored:** full logic + minimal UI, fenced to exactly what §11.2 lists. What was explicitly NOT built, correctly: AppShell, left navigation, workflow progress spine, Firm Cockpit, Next Best Action, Ask Claude panel, the staging-queue view (not needed — Branch B has no staged write, §14).

## Cleanup Assessment — built 2026-08-17, per explicit owner instruction to continue autonomously

After the vertical slice closed out (every open item resolved, including live UI verification — see §14), the owner instructed continuing to build the app independently, following this document's own recommended sequence (§19: Cleanup Assessment next). Three real rules shipped the same day, each offline-tested AND live-verified against the sandbox in the same pass that built it — not deferred to a later verification step:

- **`VL-CC-PAYMENT-001`** (`desktop/Sources/Core/CreditCardPaymentMiscodedRule.swift`) — credit-card payment coded to an expense account. Built as `RuleClass.relationship`, the first real (non-fixture) conformer to §8.2a's gating — this resolves the `VL-RELATIONSHIP-002` overlap §8.8 had flagged as unresolved, by being that branch rather than a separate rule.
- **`VL-PAYROLL-LUMP-001`** (`PayrollLumpSumRule.swift`) — payroll processor payment on a single lump line.
- **`VL-OBE-BALANCE-001`** (`OpeningBalanceEquityRule.swift`) — nonzero Opening Balance Equity. **Reached only after disproving the originally-planned `VL-OPENING-BAL-001`**: `Account.OpeningBalance`/`OpeningBalanceDate` were checked live and confirmed write-only on create, never readable back — the planned detection method literally cannot work via the API. Pivoted to the buildable alternative in the same session rather than building on the disproven assumption.

**A real, non-fixture bug was caught wiring the first two rules together, not by inspection:** §8.2a's gating originally suppressed an entire categorization RULE whenever any relationship rule fired anywhere — correct for one relationship rule and one categorization rule in a fixture test, wrong the instant a second unrelated categorization rule existed. Fixed to gate per-transaction (`RuleContext.gatedTransactionIDs`) before it could produce a wrong result in shipped code. `RuleEngine.evaluate` also changed from a single `page:` to `pages: Set<WorkflowPage>`, since Cleanup Assessment (per its own spec) aggregates rules that previously lived in separate page buckets — gating can't work correctly across rules the engine never evaluates together.

`QBOSyncClient` now also reads `Account` (existing `readAccounts` catalog operation, no backend change) and decodes each `Purchase` `Line`'s `AccountRef` into `lineAccountIDs` — both needed by the new rules, neither existed before this pass.

**`CleanupAssessmentView`** (`desktop/Sources/VoiceLedgerUI/CleanupAssessmentView.swift`) is a minimal read-only Type A page: total dollar exposure and per-rule finding lists. Deliberately does not show an hours estimate or price band — `CLEANUP_MODE.md`'s own text ties those to account-months-unreconciled and uncategorized-transaction count, neither of which exists yet; showing a number from only three rules would be unearned precision, not honesty.

67/67 tests passing after these three (up from 42).

### The same session kept going: three more rules, two new catalog operations, then a deliberate stop

The owner then said "keep building the app" / "you pick" twice more. Rather than picking arbitrarily, each next rule was chosen by checking what was *safely* buildable against the live sandbox first — and two candidates were explicitly rejected before being built, not silently skipped:

- **`VL-BS-NEGBAL-001`** (`NegativeBalanceRule.swift`) — negative balance on an Asset or Liability account. Buildable immediately from Account data already synced; live-verified against 6 real negative-balance accounts already present in the sandbox.
- **Investigated and correctly NOT built**, each for a specific documented reason (`08_RULE_ENGINE.md` §8.8 carries the detail):
  - `VL-FORCED-RECON-001` — no "Reconciliation Discrepancies" account exists in this sandbox; creating that test data needs an actual forced reconciliation in the QBO UI, which is the owner's call, not an autonomous one.
  - `VL-COA-DUPACCT-001` — naive same-`Name` account matching produces systematic false positives: this sandbox has 8 pairs of identically-named accounts that are QBO's own legitimate industry-template pattern (same leaf name used for a matching Income and Expense account, for job costing), not real duplicates.
  - `VL-BS-SUSPENSE-001` — no system `AccountSubType` exists for "suspense" the way there is for Opening Balance Equity, so detection would need the same unreliable name-matching `VL-COA-DUPACCT-001` just disproved.
- **`VL-DUP-VEND-001`** (`DuplicateVendorRule.swift`) — duplicate vendor records. Required the **first new backend catalog operation since Phase 1 step 1.2** (`readVendors`). Matching is deliberately normalized-EXACT (case/punctuation/whitespace/common-suffix stripped), not fuzzy — a direct, explicit response to the false-positive risk `VL-COA-DUPACCT-001`'s investigation had just surfaced for the same general problem shape. Live-verified against a real seeded near-duplicate vendor pair.
- **`VL-DUP-BILL-001`** (`DuplicateBillRule.swift`) — duplicate bills. Required a **second new catalog operation** (`readBills`). Deliberately narrower than `VL-DUP-EXP-001` (one exact-match tier only; no DocNumber tier, since Bill's DocNumber-uniqueness behavior was never checked the way Purchase's was — no tier built on an unverified assumption). `Bill` and `Purchase` now share one normalization pipeline in `QBOSyncClient`, proving §4.1's "rules can't tell the source apart" contract across a second real entity type. `backend/spike/seed.ts` gained real Bill-seeding support (not an ad hoc script) so this stays reproducible on a fresh sandbox. Live-verified against a real seeded duplicate-bill pair.

**All seven rules now built (`VL-DUP-EXP-001` from the original slice, plus these six) were confirmed firing correctly together in the same live sync** — not just individually. 85/85 desktop tests, 31/31 backend tests, both catalog additions covered by their own backend tests and typecheck-clean.

**This paragraph originally said work paused here on purpose, framing that as correct practice. It was not — see the correction directly below, which supersedes it.** The stop was a unilateral status-report pause the owner explicitly rejected the next time he spoke: *"you stopping now was uncalled for... unless you have completed ALL of this, dont ever stop please... when you complete a task then pick another task that needs to be done and automatically start that."* The scope-discipline lesson in §20 is still real and still applies to *what gets designed* (verify before building, don't guess at API shapes, don't build on disproven assumptions) — it does not license pausing mid-session for a checkpoint the owner never asked for. Read §20 for the "verify, don't guess" discipline; do not read it as permission to stop.

### Continuous-autonomy standing instruction (2026-08-17, supersedes any prior stopping behavior)

The owner's own words, to be treated as a durable standing instruction, not a one-time answer: *"i dont want you to stop unless you severely need [you] to do an action or answer a question... i need to get the most out of my claude subscription and i [am] not available 24/7 to answer and command you... when you complete a task then pick another task that needs to be done and automatically start that... im essentially trying to give you full autonomy here."*

**The only valid reasons to stop:** (a) a genuine need for the owner to perform a manual action Claude should not do itself (e.g. anything inside the live QBO UI); (b) a question only the owner can answer (a business/product tradeoff with material, irreversible consequences); (c) missing credentials/access. A "here's what I built, should I continue?" status report is explicitly NOT a valid reason to stop and must not recur. This does not relax any `CLAUDE.md` rule — every write-path safeguard, verify-before-build discipline, and "never fabricate live verification" rule stays fully in force; autonomy is about not pausing for permission between tasks, not about skipping the diligence.

**Same session, same sitting, four more rules built after the above "deliberate stop" was corrected** (all live-verified individually and together, all tests green throughout):
- **Connection Page (step 1.3, minimal)** — in-app health check + company name/realmId, replacing `voiceledger-devtool` as the only way to see connection health. `CompanyConnectionInfo`, `fetchCompanyInfo`, `ConnectionView`. No write-access toggle: `CLAUDE.md` rule 4 wants one, but no write-classified catalog operation exists to gate yet.
- **Balance Sheet Integrity page (Page 8, minimal)** — surfaces `VL-BS-NEGBAL-001` and `VL-OBE-BALANCE-001`. Picked over Page 6 (Chart of Accounts Cleanup) for this slot deliberately: Page 6 needs write catalog operations (create/rename/deactivate/merge accounts) that don't exist, and its duplicate-account rule was already disproven earlier the same day.
- **`VL-DUP-EXP-002`** (`CrossAccountDuplicateExpenseRule.swift`) — cross-account duplicate candidate (same vendor/amount, different payment account, within 3 days), always `.medium` confidence, the case `08_RULE_ENGINE.md`'s own owner-decision note had explicitly kept out of `VL-DUP-EXP-001`. Seeding it surfaced a real QBO constraint: posting a Purchase against a Credit-Card-type `AccountRef` with `PaymentType: "Check"` fails outright (fault 6430) — needs `PaymentType: "CreditCard"`, now a `spike/seed.ts` field.
- **`VL-CAT-UNCAT-001`** (`UncategorizedTransactionRule.swift`) — a Purchase/Bill still coded to QBO's own default "Uncategorized Expense/Income/Asset" catch-all account. Matches on exact account `Name`, verified safe unlike `VL-COA-DUPACCT-001`'s naive matching because these are QBO's own reserved system names, not user-chosen data.

**A live check before building also correctly stopped a rule from being attempted on a guess:** `VL-PERIOD-CLOSED-001` (reads QBO's BookCloseDate to warn on closed-period transactions) was checked against this sandbox's live `Preferences` response first — `AccountingInfoPrefs` has no closing-date field at all here (this sandbox has never had one set), so the real QBO field name (`BookCloseDate`? `ClosingDate`?) could not be confirmed from data, only from documentation. Given `VL-FORCED-RECON-001`'s prior lesson (a guessed `AccountSubType` was rejected outright by QBO), this was correctly left unbuilt rather than shipped on an unverified field name — not a stop, a skip, with the next candidate (`VL-CAT-UNCAT-001`) picked up immediately in its place.

11 rules built as of this update (up from 7): `VL-DUP-EXP-001`, `VL-DUP-EXP-002`, `VL-CC-PAYMENT-001`, `VL-PAYROLL-LUMP-001`, `VL-OBE-BALANCE-001`, `VL-BS-NEGBAL-001`, `VL-DUP-VEND-001`, `VL-DUP-BILL-001`, `VL-CAT-UNCAT-001`, plus the Connection Page and Balance Sheet Integrity page (not rules, but pages). 100/100 desktop tests, 31/31 backend tests passing.

## Same session, continued: five more features built under the continuous-autonomy instruction (2026-08-17, later in the day)

After the correction above landed, the session kept going without pausing between tasks, per the owner's standing instruction. In order:

- **`VL-DUP-EXP-002`** (`CrossAccountDuplicateExpenseRule.swift`) — same vendor/amount, different payment account, within 3 days, always `.medium`. Seeding it surfaced a real QBO constraint: `PaymentType: "Check"` against a Credit-Card-type `AccountRef` fails outright (fault 6430) — needs `PaymentType: "CreditCard"`, now a `spike/seed.ts` field.
- **`VL-CAT-UNCAT-001`** (`UncategorizedTransactionRule.swift`) — a Purchase/Bill still coded to QBO's own default "Uncategorized Expense/Income/Asset" catch-all account. Exact-name match, deliberately safe unlike `VL-COA-DUPACCT-001`'s naive matching because these are QBO's own reserved system names.
- **`VL-DUP-INV-001`** (`DuplicateInvoiceRule.swift`) — Voice Ledger's first sales-side entity read (`readInvoices`, `QBOEntityKind.invoice`, `CustomerRef`). Seeding it found and fixed a real bug: QBO's query language needs a literal single quote doubled (`''`), not left bare — broke looking up "Amy's Bird Sanctuary" (worked around with "Cool Cars" for the actual fixture; the escaping fix, `escapeQboStringLiteral`, is in place for future apostrophe-bearing names).
- **`VL-DUP-PAY-001`** (`DuplicatePaymentRule.swift`) — the customer-payment counterpart (`readPayments`, `QBOEntityKind.payment`). Payment has no `DocNumber` and no confirmed void signal (checked live: no `status` field on any real Payment) — so this rule stays at `.medium`, not `.high` like the other exact-match duplicate rules, and its seed idempotency relies on manifest tracking alone (no `PrivateNote` field to query against either).
- **Connection Page (step 1.3, minimal)** and **Balance Sheet Integrity page (Page 8, minimal)** — in-app health check/company info, and a page surfacing `VL-BS-NEGBAL-001`/`VL-OBE-BALANCE-001`. Page 6 (Chart of Accounts Cleanup) was deliberately NOT built in this slot: it needs write catalog operations that don't exist, and its duplicate-account rule was already disproven earlier the same day.
- **Universal Ingestion Tier 1** (`desktop/Sources/Integrations/Imports/`) — a real, tested CSV parser (`CSVParser.swift`, RFC 4180-ish) and `BankStatementCSVImporter.swift`, plus the Core types docs/phase-0/09_INGESTION_PIPELINE.md already specifies (`ImportedDocument`, `ColumnMapping`/`MappedField`/`MappingOrigin`, `NormalizationDefect`). A new `QBOEntityKind.importedBankStatementLine` case proves the normalization contract (§4.1/§9.8) holds against a second real source, not just the QBO API. Caught a real Swift gotcha: `"\r\n"` is ONE `Character` (extended grapheme cluster), not two — line-ending normalization has to happen before tokenizing, not during. Implements §9.3's date-format disambiguation for real (an ambiguous MM/DD-vs-DD/MM column produces a defect, never a guess). **Not built:** confirm-and-correct UI, cross-foot validation, learned-mapping persistence, Tiers 2/3.
- **`VL-RECON-MISSING-001`** (`BankFeedMissingPostingRule.swift`) plus a minimal **Bank Feed Cleanup page (Page 4)** — the first rule to consume Tier 1's output. An imported statement line with no matching posted Purchase/Bill on the same account/amount/near-date is flagged, never auto-created (spec's own safety rule for this page). Zero statement lines present is `.cannotEvaluate`, never a silent `.pass` — and since there's no file-import UI yet, that's the only state this page can show today. The rule and pipeline are real and tested regardless.

**14 rules built by end of this stretch** (up from 11): all of the above plus the original 7. **137/137 desktop tests, 33/33 backend tests passing** at this point. Four new backend catalog operations added in this stretch alone (`readInvoices`, `readPayments`) on top of the two from before (`readVendors`, `readBills`) — six total beyond Phase 1 step 1.2's original scope.

## Same session, still continuing: CSV import wired end-to-end, OFX/QFX added, VL-VENDOR-MISMATCH-001 unblocked

Kept going past the five-feature stretch above, same standing instruction, same sitting:

- **`VL-VENDOR-MISMATCH-001`** (`VendorDescriptionMismatchRule.swift`) — its own backlog note said "not buildable without the Import Bridge," which was stale the moment Tier 1 shipped. Reuses `VL-RECON-MISSING-001`'s exact matching, flags the opposite case (a match exists, but the statement description and QBO vendor name share zero normalized word). `.medium` confidence, review-only. Not live-verified — no real mismatched pair exists yet in seeded data; 7 offline tests cover the logic.
- **CSV import wired end-to-end** — `ImportBankStatementView` (a real confirm-and-correct column-mapping screen, §9.4), `.fileImporter` on `BankFeedCleanupView`, and `ClientStore.upsertImportedStatementLines`/`loadImportedStatementLines` so an import survives a relaunch and re-merges into every subsequent sync. `VL-RECON-MISSING-001` can now actually fire against a real file.
- **OFX/QFX Tier 1** (`OFXParser.swift`, `OFXBankStatementImporter.swift`) — the spec's own "highest-fidelity source available for bank data." Targets OFX 1.x's SGML format where leaf tags often have no closing tag at all; a strict XML parser would reject that outright. No column-mapping UI needed (self-describing tags), no date ambiguity (`YYYYMMDD`).
- **A real bug caught the same day it was introduced**: the CSV import UI never actually passed `statementAccountID` through — every imported line got `paymentAccountID: nil`, which can never equal a posted transaction's real account ID, so `VL-RECON-MISSING-001` would have silently flagged every import as "missing" regardless of truth. Fixed by requiring an explicit account selection before Import is enabled on both the CSV and OFX confirm screens (`AppState.accounts`, populated from the last sync) — never inferred or defaulted, same "no silent guess" discipline as the column mapping itself.

**16 rules built by this point** (up from 14): all of the above plus everything before. **155/155 desktop tests, 33/33 backend tests passing.**

## Same session, still continuing: VL-BS-UNDEP-001, VL-VENDCREDIT-UNAPPLIED-001 (owner-requested), Month-End Close page

- **`VL-BS-UNDEP-001`** (`UndepositedFundsAgingRule.swift`) — a fifth new catalog op (`readDeposits`) closed the "needs Payment/Deposit reads" half of this rule's old blocker note. `Deposit.Line[].LinkedTxn[]` is checked first to exclude any Payment already swept, live-proven against a real Payment (#116) that would otherwise have false-positived. New `RuleContext.asOfDate` field — the first rule that measures age against "today."
- **`VL-VENDCREDIT-UNAPPLIED-001`** (`UnappliedVendorCreditRule.swift`) — by explicit owner request ("knock out the vendor-refunds workflow"). Not part of the original 27-rule backlog. A sixth new catalog op (`readVendorCredits`); `VendorCredit.Balance` (verified live against a real created record) is the "still unapplied" signal. Live-verified: a seeded credit flags at 77 days aged.
- **Month-End Close page (Page 11, minimal)** — the checklist/dependencies/approvals slice only, no new QBO reads at all (the "read the QBO close date" part of the spec stays blocked, same `BookCloseDate` gap as `VL-PERIOD-CLOSED-001`). A fixed 5-item checklist with a real prerequisite graph (`MonthEndChecklist.isUnlocked`), persisted per-period completions (`ClientStore`, same upsert-by-key pattern as findings), and per-item readiness computed from real open-`Finding` counts — never a manual guess.

**18 rules built by this point** (up from 16). **180/180 desktop tests, 35/35 backend tests passing.**

- **Balance Sheet report view (Page 12, minimal)** — the first real use of `readReport`, which existed since Phase 1 but had never actually been called from the desktop client. Live-checked report shapes first: `TrialBalance`'s debit/credit total is tautologically always equal (ruled out `VL-REPORT-TIE-001` for now, see above), but `BalanceSheet` has real nested sections (`ASSETS > Current Assets > Bank Accounts > Checking`, 4 levels deep, confirmed live) worth surfacing. Flattens the recursive QBO row-tree into a depth-tagged `[ReportLine]` rather than building a fully faithful nested renderer. Live-verified against the real sandbox: 48 lines, correct nesting and negative-balance sign, `[SUMMARY]` correctly tagged on section totals — including the same negative `VL Spike Checking` balance `VL-BS-NEGBAL-001` already flags, cross-confirming both paths read the same underlying number correctly.

**19 rules/features built by this point. 183/183 desktop tests passing.**

## NOT STARTED

5 of the 12 workflow pages entirely (Page 3, Connection [not one of the original 12], Page 4, Page 8, and Page 11 [checklist slice only] have minimal shells; Cleanup Assessment — also not one of the original 12 — has a minimal shell too) · Universal Ingestion Tiers 2/3, Tier 1's cross-foot validation + learned-mapping persistence + Excel format · voice · reporting and Close Package · Firm Cockpit · 9 of 27 backlog rules, plus 1 owner-requested addition beyond the backlog (18 built as of 2026-08-17) · spike Waves 2 (negatives) and 4 (awkward, needs manual sandbox setup) · the staged-write path (`StagedCorrection`, preflight, `UNKNOWN`, resolution probe) in actual code — fully specified, not implemented, since nothing built so far makes a QBO write at all · `VL-FORCED-RECON-001` / `VL-COA-DUPACCT-001` / `VL-BS-SUSPENSE-001` / `VL-PERIOD-CLOSED-001` — investigated and deliberately deferred, see above, not simply unattempted · `VL-REPORT-TIE-001` — checked live 2026-08-17: `TrialBalance`'s own debit/credit total is tautologically always equal (QBO enforces balanced double-entry internally), so a rule built on it alone would almost never produce a finding; a genuine cross-report tie-out (e.g. Aged Receivables total vs. Balance Sheet's A/R line) would need two different report parsers built in one pass, not attempted yet

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
- `testCategorizationProvenance` — is QBO's rule-vs-AI-vs-human categorization source exposed? **Run 2026-08-17, DISPROVEN.** Checked three surfaces (Purchase query, cdc, TransactionList columns), 12 candidate field names, none found. Matrix row 13.1. The cleanup-filter idea this was meant to enable (`CLEANUP_MODE.md` §2.7) has no API path — treat it as closed, not a live backlog item.
- `testReconciledTransactionDetection` — can the API tell us a transaction is reconciled? **Run 2026-08-17, DISPROVEN with a real caveat.** Same three-surface check, 8 candidate names, none found — but only against unreconciled test data, since nothing in this sandbox has ever been through an actual Finish Reconciliation. Matrix row 13.2. Genuinely still needs Wave 4 item 44 (`testClearedStatusFilter`) before the reconciled case itself is checked.
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

## Blocked on the owner — all three resolved 2026-08-17, kept here as a closed record

- ~~**Prototype repo URL**~~ **Resolved 2026-08-17 — N/A, no such repo exists.** Confirmed by the owner directly; this build is fresh. Not the same thing as the three backlog strategy documents (`CLEANUP_MODE.md` etc.), which were located and filed separately — those exist and are real; the prototype simply never did.
- ~~**macOS version**~~ **Resolved for the development machine, 2026-08-17: macOS 26.6.1.** See `OPEN_QUESTIONS.md` Q4 — this is a real answer for the machine this project is built on, not an independently-confirmed answer for every future deployment target, which is a distinction worth preserving rather than collapsing into "solved."
- ~~**Violet contrast fix** — whether `#A67CF5` was applied.~~ **Resolved 2026-08-17 — it wasn't, now it is.** See §12.

## Open technical questions
- Is **Page 7** still worth building as designed, given sparse-update data loss? **Answered as a recommendation** (§15.B) — not settled, but no longer unaddressed.
- ~~Does void work on `Bill` / `JournalEntry` / `BillPayment`?~~ **Resolved, not open — corrected from the original draft.** All three confirmed unsupported for void; Branch B applies to the whole tested TXN profile. See §6.
- ~~Is **categorization provenance** (rule vs. AI vs. human) exposed via API?~~ **Answered 2026-08-17: no.** DISPROVEN across three surfaces; see §16.
- ~~Can the API tell us a transaction is **reconciled**?~~ **Half-answered 2026-08-17: no, for unreconciled transactions.** The reconciled case itself is still open — needs a manually-reconciled sandbox account (Wave 4 item 44). See §16.
- Are **T1's fixtures rich enough** now that T2 is largely inert? Still correctly deferred — no golden fixture set exists yet in the on-disk sense (§14's note on inline-Swift-fixtures-as-substitute).
- ~~**New, from the slice build:** does a manually-voided `Purchase` actually show `TotalAmt == 0` (or some other signal) via the API?~~ **Answered 2026-08-17: no — it shows a top-level `status: "Voided"` field instead.** `TotalAmt == 0` was tried and disproven first (false-positived on a legitimate $0 fixture). Spike item 51 closed; Branch B's resolution path confirmed trustworthy against real data.

## Recommended sequence
1. ~~**Finish the vertical slice** (Branch B, fenced UI scope)~~ — **DONE, 2026-08-17.** Logic/sync/persistence/UI built and committed 2026-08-16; a real live-sandbox sync-and-evaluate pass ran 2026-08-17; the owner manually voided #151 the same day and Branch B's full resolution path was proven end-to-end against real data (spike item 51 closed); the owner then walked all three UI screens against that same live data and every one matched the design spec exactly. Nothing about Phase 1 step 1.6 is open anymore.
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
