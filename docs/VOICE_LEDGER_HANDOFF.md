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

## D2 — One SQLite database per `realmId` — the SQLite half now real (2026-08-29); three of four hardening layers still PLANNED

Not a `realm_id` column with a `WHERE` clause. **A cross-client query is not a missing predicate — it is a different file.** The failure mode is eliminated rather than guarded against.

Stated cost: no cross-client SQL. The Firm Cockpit must fan out across stores and aggregate in memory. Accepted — the aggregation is over small summary data, not ledger rows.

Four layered isolation mechanisms: per-realm database · `ClientScope` actor with no ambient "current client" · phantom-typed `Scoped<Scope, Value>` at crossing points only (staging queue, activity log, QBO write path — not every read) · runtime assertions at four crossing points.

`realmDirectoryName` is a **hash** of the realmId, so directory listings don't enumerate client identifiers.

**What shipped 2026-08-16 (the vertical slice):** `desktop/Sources/DB/ClientStore.swift` — one JSON-file-per-realm-directory, not SQLite, and the directory name is the raw `realmId`, not a hash.

**Migrated to real SQLite 2026-08-29** (`desktop/Sources/DB/SQLiteConnection.swift` + `ClientStore.swift`'s rewritten internals): each realm directory now holds one `store.sqlite` file (`import SQLite3` against the system `libsqlite3`, no third-party package — same "hand-roll it against the platform SDK" posture `Exporting`'s ZIP/PDF writers already use), with a single `kv` table (`key TEXT PRIMARY KEY, value TEXT`) — every existing public method on `ClientStore` is unchanged; only the two private `load`/`save` helpers changed what they read from and write to. WAL mode gives a real crash-safety property the JSON files never had: a killed process mid-write leaves the database at its last COMMITted state, not a half-written file, and every load-modify-save sequence that used to be several separate file writes is now backed by one durable store. **Existing realms' JSON data is migrated automatically and once** on first open after upgrading (`ClientStore.migrateLegacyJSONFilesIfNeeded`) — verified against this session's own real accumulated sandbox findings (13 real findings from earlier live-verification runs), not just synthetic test fixtures; the legacy `.json` files are left in place, not deleted, in case a migration bug is ever found later. The directory name is still the raw `realmId`, not a hash — that specific hardening step, and the other three layered mechanisms above (`ClientScope` actor, phantom-typed `Scoped<Scope, Value>`, runtime assertions at crossing points), remain **not yet built**.

## D3 — Staleness is derived, never marked — the checklist half now real (2026-08-29)

**There is no `markStale()` function anywhere.** A page is fresh iff the evidence watermark it was completed against still equals the current watermark for its declared inputs. Code cannot forget to call something that doesn't exist.

Watermark components include rule versions and materiality policy — so bumping a rule version or changing materiality automatically stales completed pages.

**Built for the Month-End Close checklist 2026-08-29** (`desktop/Sources/Core/EvidenceWatermark.swift`): `EvidenceWatermark.current(ruleIdentities:materiality:)` computes a stable signature (sorted `ruleID:major.minor.patch` pairs, joined — not a cryptographic hash, since exact equality is all this is ever used for) over the two components this section's own text names explicitly. `ChecklistItemCompletion` gained an additive `watermark: EvidenceWatermark?` field (`nil` for any completion recorded before this shipped — `MonthEndChecklist.isStale` treats `nil` as stale, never as fresh, same "unknown is never green" posture CLAUDE.md rule 5 applies everywhere else). `AppState.completeChecklistItem` captures the watermark at attestation time; `MonthEndCloseView` renders a "Stale — re-verify" pill in place of "Done" when `MonthEndChecklist.isStale` says the current watermark no longer matches. **Still scoped down, honestly**: this is derived from rule versions + materiality only, not a full content-hash of the synced data itself (D3's design also implies "the underlying data changed" as a staleness trigger — that would need a hash of `NormalizedDataSet`'s actual content, a bigger change touching the sync path, and is a natural additive next step rather than a redesign of what shipped). `ClientStore`'s own `reconcileAgainstLatestRun` remains a DIFFERENT (narrower) mechanism — it resolves individual findings when a rule stops reproducing them; do not confuse the two.

## D4 — Three-phase write journal with explicit `UNKNOWN` — BUILT 2026-08-29

`SUBMITTED` is persisted and flushed to disk **before** the network call. A journal written after the call would lose the record of a write that may have landed.

`UNKNOWN` is a first-class persisted state. **Never retry.** It blocks all further writes to that entity until a resolution probe settles it. The probe's load-bearing step: an unchanged `SyncToken` is strong evidence the write did not land, since any successful write increments it. An `AMBIGUOUS` outcome escalates to the human — never guessed.

**Built 2026-08-29** (`desktop/Sources/Core/WriteJournal.swift` — `WriteJournalState`/`WriteJournalEntry`/`WriteJournalResolution`; `ClientStore.load/upsertWriteJournalEntry`; `AppState.applyStagedFix`/`resolvePendingWrite`). The real gap this closed: before this, `applyStagedFix`'s `catch` block treated EVERY thrown error identically — a clean HTTP rejection and "the network dropped after the request was sent, before any response arrived" both got logged as `.apiWriteRejected` with the same "the call failed before QBO could respond" message, which is not actually knowable to be true for the second case. A bookkeeper retrying after that message could double-apply a write that had, in fact, already landed.

What shipped: `applyStagedFix` now writes a `.submitted` journal entry (keyed `"<purchaseID>:<lineID>"`, not a random id — so "is there already a pending write against this exact line" is a direct lookup) BEFORE calling `reclassifyPurchaseLine`, and checks for an existing `.submitted`/`.unknown` entry for that same key FIRST, refusing to start a second write while one is unresolved. A response with `verified == false` (QBO answered, and said no) resolves to `.failed` — a KNOWN clean outcome, safe to retry, distinct from `.unknown`. A thrown error (no response parsed at all) resolves to `.unknown` and blocks further writes to that line. `resolvePendingWrite` is the probe: re-fetches the purchase (`QBOSyncClient.fetchPurchases`, already-verified, no new capability), compares its current `SyncToken`/line account against what the journal entry recorded before the write, and calls `WriteJournalResolution.resolve` (Core, pure) to reach `.failed`/`.success`/`.ambiguous` — an `.ambiguous` outcome is recorded and surfaced (new `ActivityKind.apiWriteAmbiguous`), never auto-resolved either way. `FindingDetailView` blocks "Apply Fix" and shows a "Resolve Pending Write" button whenever a pending entry exists for that finding's exact purchase+line.

**Not live-tested against a real network failure** — reliably TRIGGERING a genuine "request sent, response lost" condition against the real sandbox isn't practical to simulate deterministically. Shipped on thorough unit coverage of the pure resolution logic (`WriteJournalTests.swift` — all four `WriteJournalResolution.resolve` branches) instead, the same honest "unit-tests-only, no live positive example" posture `VL-FEE-AVOIDABLE-001` already established for a different reason. The two `docs/phase-0/10_STAGING_APPROVAL_AUDIT.md` §10.5a items still genuinely not done: `classifyWriteResponse`'s backend chokepoint doesn't exist in backend code (the desktop client's own catch-vs-verified branching does the equivalent classification client-side instead), and the HTTP-200-is-not-success correction is handled by trusting `WriteVerificationResult.verified` rather than a revised probe step 1 on the backend.

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

## D8 — `/voice` module — BUILT 2026-08-29

Build Order item 12 ("Voice layer last, so a voice bug never blocks anything else") — filled in last, after every other approved-scope item, per that same ordering. `Sources/Voice` was a literal empty placeholder until this.

**Spec text says `whisper.cpp`; what actually shipped is faster-whisper (Python).** Flagged per CLAUDE.md's "flag rather than silently work around" — the owner has a separate, more mature app (`Claude Voice Ledger`, not part of this repo) with an already-working local STT/TTS stack (faster-whisper + Piper, FastAPI) they explicitly chose to reuse rather than build a new whisper.cpp integration from scratch. `voice-service/` at this repo's root is that same stack, adapted (no CORS middleware — the only caller is the native Swift app via `URLSession`, not a browser).

**What's real**: `voice-service/` (STT/TTS, fully local, live-verified end-to-end including a genuine TTS→STT round trip and — separately — the actual Swift `VoiceServiceClient` against the real running service, both via the new `voiceledger-devtool voice-service-check` command); `Sources/Voice` (`VoiceSessionContext`, `VoiceIntentRouter` — the deterministic fast path, ported from a design already battle-tested in that reference app including its own documented, verified LLM hallucination bugs — `ReviewQueue`, `VoiceTurn`); `VoiceEngine` (`VoiceLedgerApp`, `AVAudioEngine`-based recording with RMS silence auto-stop, conversation mode, `AVAudioPlayer` playback); a global mic button + status panel in `RootView`; the launcher starts `voice-service` as a third process alongside the backend.

**The safety guarantee is structural, not a runtime check**: `VoiceIntent` has no case that can apply a staged QBO fix (`AppState.applyStagedFix`) — confirmed by grep, not just by testing that it happens not to fire: the only occurrence of `applyStagedFix` anywhere in `Sources/Voice`/`VoiceEngine.swift` is a doc comment explaining it's never called. The two `VoicePendingAction` kinds voice CAN confirm (`dismissFinding`/`completeChecklistItem`) are Voice Ledger's own low-stakes internal state, never a QBO write — matching docs/VOICE_LEDGER_SPEC.md's Voice Guardrails line exactly: "voice navigates, filters, searches, reads, and drafts, but never finalizes a QBO write without visible on-screen confirmation."

**Not live-tested with a real spoken command** — this environment has no microphone to drive. Everything up to and including the actual mic/speaker round trip is either unit-tested (the deterministic router, review queue, session context — 26 tests) or live-verified against the real running `voice-service` process (STT/TTS, and the full launcher-started three-process stack, confirmed via a real end-to-end launch: backend + voice-service + a genuine foreground app window, not a stuck early-launch process). The one thing that still needs a human to actually speak to the running app once: does a spoken "Cleanup Assessment" navigate, does "why is this flagged" produce a sensible answer.

**Real crash found and fixed the same day, from the owner's own first click.** Clicking the mic and granting the permission prompt crashed the app outright. `~/Library/Logs/DiagnosticReports/VoiceLedgerApp-2026-08-28-222235.ips` (read directly, not guessed at) showed `EXC_BREAKPOINT`/`SIGTRAP` inside `closure #1 in VoiceEngine.startListening()`, specifically in Swift's Task executor-isolation check (`swift_task_checkIsolatedSwift` → `dispatch_assert_queue_fail`). Root cause: the `AVAudioEngine` input-node tap callback runs on a raw CoreAudio real-time thread, not a normal GCD queue — creating a `Task { @MainActor in ... }` directly inside that callback to hop state updates (`micLevel`, silence detection) back to the main actor triggers Swift's Task-executor determination machinery, which asserts on that thread and traps. Fixed by using plain `DispatchQueue.main.async { @MainActor in ... }` instead, which sidesteps Swift's Task/executor machinery entirely — the standard-safe way to hop off a real-time audio callback, and a real, specific lesson for any future `AVAudioEngine` tap work in this codebase: never create a `Task` from inside an audio tap's callback closure.

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
- **`ActivityLogEntry`** — **IMPLEMENTED** (a real subset — `desktop/Sources/Core/ActivityLog.swift`). Append-only, no update, no delete — enforced by `ClientStore` exposing no update/delete method on the activity log, not just by convention. Stale as of 2026-08-24: this used to say only 3 kinds existed; the Gauntlet Loop hardening pass on `VL-DUP-EXP-001` (below) found the enum had actually grown to 9 cases over time, and separately found `.findingDetected`/`.findingResolved` had each gone through a period where the case existed with a human label and a Decodable round-trip test but no production call site ever constructed one — a documented-but-dead code path, not a missing case. Both are now wired (round 5 and round 10/11 respectively). All 9 real kinds as of this writing: `findingDetected`, `manualCompletionAttested`, `findingResolved`, `apiWriteApplied`, `clientQuestionDrafted`, `findingDismissed`, `clientMemoryRuleCreated`, `clientMemoryRuleRemoved`, `findingAutoDismissedByClientMemory`. The full spec's larger `ActivityKind` enum is still not fully modeled since no staged-write path beyond `updatePurchaseLineAccount` is built.
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

- **The Write-Enabled access-mode gate (§10.4 item 3)** — checked what a real write path would need before attempting one. Void is dead everywhere (`Purchase`/`Bill`/`JournalEntry`/`BillPayment` all confirmed unsupported, §16). Full-entity updates DO work (§15.B's earlier finding — sparse updates lose data, full-entity + round-trip verification doesn't), so a real write path is eventually buildable, but building the actual first write operation and a `StagedCorrection` approval UI in the same pass as the access gate itself risked rushing something CLAUDE.md rules 2/3/4/7/8 all deliberately gate. Built the gate alone instead: `connections.write_enabled` (SQLite, migration-safe `ALTER TABLE` verified against the real running backend's existing DB — the realm already connected this session correctly defaulted to `false`), `dispatch()`'s `shouldBlockWrite` checked structurally rather than per-route, `GET`/`PUT /realms/:realmId/write-access`, and a real (not theater) toggle in `ConnectionView` — flipping it changes genuine persisted backend state, live-verified end to end (GET → PUT true → GET confirms → PUT false, left in the safe default). **No write-classified operation exists in the catalog yet** — this gate currently blocks nothing in practice. It's the safety mechanism proven before the capability that needs it, the same sequencing already used for `isVoided` (§11.1, proven before any write path triggered it). The actual first write operation (e.g. single-field Purchase-line reclassification) and its `StagedCorrection`/approval UI are the next real step here, not yet started.

**19 rules/features plus this gate. 183/183 desktop tests, 42/42 backend tests passing** (was 35 — 7 new: 3 TokenStore write-access tests, 4 dispatcher gate tests).

## The Phase 1 -> Phase 2 threshold: Voice Ledger's first real QBO write

**This one crossed a line the project's own docs reserve for the owner, not for autonomous judgment** — `assertReadOnlyCatalog()`'s own error message says a write operation needs "separate, explicit approval per the Phase 1 gate table." Stopped and asked directly rather than treating the earlier "full autonomy" grant as covering this too. **The owner said yes, build it.**

**`updatePurchaseLineAccount`** — reclassifies one Purchase line's `AccountRef`. Full-entity update (not sparse — §15.B's already-verified finding that sparse updates lose data), with round-trip verification BAKED INTO the operation itself, not left to a caller: a fresh read before, the update, a second fresh read after (never trusting the update response body), comparing every field that must not drift (`DocNumber`, `PrivateNote`, `TotalAmt`, `EntityRef`, `AccountRef`, `TxnDate`) plus every OTHER line's content, byte-for-byte. Returns `verified: true` only if all of that holds — `verified: false` means the write happened but something about it doesn't check out, treated as `UNKNOWN`-adjacent (per this doc's own description of that write-state), never silently reported as success.

**Live-verified end to end through the real HTTP stack**, not just unit tests: created a real throwaway 2-line Purchase (#227), reclassified line 1 from Office Supplies to Wages, got back `verified: true`, `otherLinesUnchanged: true`, `unexpectedFieldChanges: []`. Then verified the safety rails independently: replaying the OLD SyncToken correctly failed with `409 Stale SyncToken` (not a silent overwrite), and disabling Write Access mid-session correctly returned `403` on the next call. Sandbox left in its default Read-Only state afterward.

`assertReadOnlyCatalog()` became `assertCatalogWriteOpsAreApproved()` — an explicit named allowlist (`APPROVED_WRITE_OPERATIONS = {"updatePurchaseLineAccount"}`) rather than a blanket "must be read" check, so the same "loud failure if this silently changes" property holds for the new reality instead of just being deleted. `QBOClient` gained its first `.post()` method (previously GET-only by explicit Phase 1 design).

**Desktop plumbing wired the same day**: `CatalogOperation.updatePurchaseLineAccount`, `WriteVerificationResult` (Core), `QBOSyncClient.reclassifyPurchaseLine`. **Deliberately NOT wired to any UI button yet.** Most Cleanup Assessment findings don't have an obviously-correct target account to reclassify TO — `VL-CC-PAYMENT-001` does (the matched credit-card account, already identified structurally by that rule), but `VL-CAT-UNCAT-001` genuinely needs a human to pick the right category. Building an "Apply Fix" button before working out which findings can safely suggest a target account, and which can't, would risk either a wrong auto-suggestion or a button that's really a fake convenience. That per-finding-type design is the next real step here — not started.

11 new backend tests for the write op itself (dispatch gate + verified/unverified/stale-token cases against a fake client), 3 new desktop decode tests. **47/47 backend tests, 186/186 desktop tests passing.**

## Same night, kept going per explicit instruction ("keep working through the night... do not stop no matter what")

- **Profit & Loss report view** — `QBOSyncClient.fetchReport`'s recursive flattening (built for Balance Sheet) checked live against a real P&L report first: byte-identical shape (`Header`/`Rows`/optional `Summary`, leaf `ColData` + `type == "Data"`), so the same decoder applies unchanged. `BalanceSheetReportView` generalized into `FinancialReportView` (title/source-description parameters) rather than duplicating the view for a second report kind. Live-verified: 12 lines, correct nesting (`Income` > `Design income` leaf > `Total Income`/`Gross Profit` summaries).
- **Deliberately deferred, not forgotten**: the "Apply Fix" UI button that would actually USE `updatePurchaseLineAccount` from a Finding. Checked what it needs and found a real gap: `LedgerTransaction.lineAccountIDs` only tracks account IDs per line, never QBO's own `Line.Id` — the write operation needs `Line.Id` (identity, not an index) to target the right line safely. Adding that means touching `QBORawPurchaseLine`'s decode, `LedgerTransaction`'s shape, and the three rules that already read `lineAccountIDs` (`VL-CC-PAYMENT-001`, `VL-PAYROLL-LUMP-001`, `VL-CAT-UNCAT-001`) — real ripple effects into rules already live-verified and tested. Chose not to rush that at the tail end of a very long session; pivoted to the P&L view instead (safe, well-scoped, reused already-tested code) rather than stopping. **This is the actual next step for closing the detect -> draft -> review -> push loop** — not started, but the reason it's not started is recorded here rather than left silent.

## Detect -> draft -> review -> push loop closed for VL-CC-PAYMENT-001 (later the same night)

**The Line.Id/SyncToken gap above is closed, additively.** `LedgerTransactionLine {id, accountID}` and `LedgerTransaction.lines: [LedgerTransactionLine]` added alongside the existing `lineAccountIDs: [String]` — not replacing it, specifically so `VL-PAYROLL-LUMP-001` and `VL-CAT-UNCAT-001` (which only read `lineAccountIDs`) needed zero changes. `LedgerTransaction.syncToken: String?` added the same way. `QBORawPurchaseLine` now decodes `Id`; `QBORawPurchase` now decodes `SyncToken`. `QBOSyncClient.normalize(_ raw: QBORawPurchase)` populates both new fields from the same `raw.line` read already happening; `normalize(_ raw: QBORawBill)` gets `lines:` only (Bill isn't a write target, no `SyncToken` decoded for it). Build + all 186 pre-existing tests reconfirmed clean after this addition, before building on top of it.

**`Finding.swift` gained `StagedAPIWriteDetails`** (`purchaseID`, `lineID`, `expectedSyncToken`, `currentAccountID`/`Name`, `suggestedAccountID`/`Name`) and `ProposedAction.apiWriteDetails: StagedAPIWriteDetails?` (defaulted `nil`, so every other rule's `ProposedAction` init needed no changes).

**`CreditCardPaymentMiscodedRule` now populates it, but only when every one of these holds**: structural (not keyword) vendor match, exactly one line on the transaction, a resolvable `SyncToken`, and a real Credit-Card account whose name matches the vendor. Any one of those failing keeps `resolution: .manualQBO` with no `apiWriteDetails` — the keyword-match path (lower confidence, no guarantee the vendor name IS the card issuer) never gets a staged fix, by design, and neither does a multi-line transaction (which line would be wrong to guess). 3 new unit tests cover: the qualifying case gets correct staged details, a missing `SyncToken` falls back to manual, and a keyword-only match never gets staged details even with lines/SyncToken present.

**`FindingDetailView` renders an "Apply Fix" flow for `.stagedAPI` actions** distinct from the `.manualQBO` Approve/Dismiss buttons: before/after account names shown, disabled entirely when `writeAccessEnabled == false`, and a second explicit "Confirm Apply Fix" tap required after the first "Apply Fix" tap (CLAUDE.md rule 2's review step, not just one click to a live write). `AppState.applyStagedFix(findingID:actorName:)` calls `QBOSyncClient.reclassifyPurchaseLine`, treats `verified: false` as an error state (never silently reported as success — the same posture `updatePurchaseLineAccount` itself already has), and on `verified: true` writes a new `ActivityKind.apiWriteApplied` log entry (distinct from `.manualCompletionAttested` — this one IS QBO-confirmed, not a human's say-so) before re-syncing so the finding actually resolves once QBO reflects the change.

**Live-verified end to end against the real seeded fixture**, not just unit tests: `voiceledger-devtool sync-check 2026 7` against the real sandbox showed `VL-CC-PAYMENT-001` firing on purchase #211 ("VL Spike Amex", $750, coded to "VL Spike Office Supplies") with `resolution=staged_api` — confirming the rule's new branch fires correctly on real QBO data, not just synthetic fixtures. Read the real `Line.Id` ("1"), `SyncToken` ("0"), and target account id (`1150040013`, "VL Spike Amex" Credit Card) via the same `readPurchases`/`readAccounts` operations the rule consumes. Enabled write access, called `updatePurchaseLineAccount` with those exact values through the real HTTP stack (mirroring exactly what `AppState.applyStagedFix` sends) — got back `verified: true`, `otherLinesUnchanged: true`, `unexpectedFieldChanges: []`. Disabled write access again (safe default restored). Re-ran `sync-check` — `VL-CC-PAYMENT-001` now reports `PASS`, confirming the finding actually resolves once the resync sees the corrected account. **The fixture purchase (#211) is now left correctly coded** (Amex payment -> Amex liability account) rather than reverted — that's the intended real-world outcome of Apply Fix, not a side effect to undo; a future capability-matrix or regression pass that needs a fresh miscoded fixture should re-seed a new one rather than expecting #211 to still be broken.

## `VL-VENDOR-MISMATCH-001` closed out from "Built (not live-verified)" to live-verified (later the same night)

The one remaining known live-verification gap in the rule set (per its own row in `08_RULE_ENGINE.md`) was closed. `voiceledger-devtool` gained a new `csv-import-check <csvPath> <statementAccountID> <yr> <mo>` command — it runs the actual production pipeline (`CSVParser` -> `BankStatementCSVImporter` -> `ClientStore.upsertImportedStatementLines` -> merged `NormalizedDataSet` -> `RuleEngine`), the same code path `AppState.confirmCSVImport` uses, rather than hand-constructing a `LedgerTransaction` to bypass real parsing. Required adding `IntegrationsImports` as a `VoiceLedgerDevTool` target dependency (`Package.swift`).

A real one-line CSV statement ("ACH DEBIT ONLINE XFER 4471", $315.00, 07/23/2026 — note the importer needs `MM/DD/YYYY`, not ISO 8601; a first attempt with `2026-07-23` correctly failed with `ambiguousDateFormat` rather than guessing) was matched against real posted purchase #217 ("VL Spike Permian Supply, Inc.", $315.00, 2026-07-22, same Checking account) from the existing `cleanup-assessment.json` seed. `VL-VENDOR-MISMATCH-001` correctly fired at `.medium` confidence; `VL-RECON-MISSING-001` correctly stayed `PASS` on the same data (it found a match — just a suspicious one, which is the other rule's job to flag). No QBO write involved — this is a read/import-only rule.

## OFX statement ending balance surfaced (informational, not automated) — later still

`OFXParser.parseLedgerBalance` extracts the file's own `<LEDGERBAL>` (`BALAMT`/`DTASOF`), and `OFXBankStatementImporter.Result` now carries `statedEndingBalance`/`statedAsOfDate` through to the OFX confirm screen. **Deliberately NOT an automated cross-foot check** — a real one (§9.5) needs a beginning balance to compare the sum of imported transactions against, which nothing here tracks; guessing one would violate `CLAUDE.md` rule 6 the same way a guessed `AccountSubType` was already rejected by QBO earlier this session. This is extraction only, displayed for the human to eyeball against their own bank statement, with the UI copy saying exactly that. CSV has no analogous field to extract (bank CSV exports don't carry a stated balance by convention) — a real CSV-side check would need a manually-entered field, not attempted. 4 new tests (2 parser, 2 importer). 193/193 desktop tests passing.

## CSV learned-mapping persistence (§9.6 stage 6) — still later the same night

Closes another item off the ingestion pipeline's own "still not built" list. `MappingHint` (Core, new) is keyed by a deterministic fingerprint of the exact header row (`MappingHint.makeID` — case/whitespace-insensitive, but never fuzzy across a reordered or renamed column: a different shape gets a different id, full stop). `ClientStore` persists hints per-realm (`mapping-hints.json`, same one-file-per-concern pattern as `checklist-completions.json`), upserting by id so a reimport of the same shape increments `timesUsed` and REPLACES `fields` with the latest confirmed mapping — a correction sticks. `AppState.selectFileForImport` is synchronous (called from inside a `.fileImporter` completion holding a security-scoped resource, no `async` context available there), so `AppState` keeps an in-memory `mappingHints` cache loaded at launch and refreshed after every confirmed CSV import, rather than querying the store mid-selection. `ImportBankStatementView` pre-fills its pickers from a match — the first real use of `MappingOrigin.learned`, which existed unused in `ColumnMapping.swift` since the original ingestion-pipeline design — with a visible "pre-filled from a previous import... review before confirming" note; nothing is silently trusted, the mapping actually sent on Confirm always reflects what's showing in the pickers at that moment. OFX is unaffected (no column-mapping step to begin with). 6 new tests (2 `ClientStore` round-trip/upsert, 2 `MappingHint.makeID` determinism/discrimination, plus the round-trip already covered other paths). 197/197 desktop tests passing.

## Close Package page (minimal real slice) — still later the same night

Both `FinancialReportView` instances (Balance Sheet, P&L) carried a stale "Not a branded client-ready document — that's the Close Package, not built yet" note. A real, honestly-scoped slice now exists: `ClosePackageView` (VoiceLedgerUI, new) consolidates what the app already computes — Month-End Checklist completion status (`MonthEndChecklist.completionStatus`, new pure Core function, period-filtered), Cleanup Assessment open/resolved finding counts, Balance Sheet + P&L summary lines (`ReportLine.isSummary`), and the 10 most recent Activity Log entries — into one read-only page. **Explicitly not** the full spec'd Close Package: no variance analysis, no cash flow/GL/trial balance/aging reports (none of those are parsed anywhere in the app yet), no separate "corrections made" ledger distinct from the Activity Log, no carry-forward items, no client Q&A, no Ask Claude history (no Claude integration exists at all — see the separate queued-but-deferred note on that). Also not an exportable/branded PDF — an in-app view, same posture as `BalanceSheetIntegrityView`/`FinancialReportView`. Auto-loads Balance Sheet/P&L on first visit if not already loaded, reusing the existing `loadBalanceSheet`/`loadProfitAndLoss` calls rather than duplicating that logic. 2 new Core tests for `completionStatus`. 199/199 desktop tests passing.

## Reconciliation summary added to Bank Feed Cleanup (Page 5's "calculates difference") — still later the same night

Spec Page 5 (Reconciliation) wants "compares statement lines to ledger; identifies unmatched/duplicates; calculates difference." Rather than build a whole separate page duplicating `VL-RECON-MISSING-001`'s matching logic a second time, `ReconciliationSummary.compute` (Core, new, pure function + 3 tests) totals what that rule ALREADY decided: total imported statement lines (`AppState.importedStatementLineCount`, new — refreshed every `syncAndEvaluate()`), matched count (total minus unmatched), unmatched count, and the unmatched dollar total ("the difference"). Rendered as a new summary strip on the existing Bank Feed Cleanup page, only shown once at least one statement line has actually been imported (`nil` otherwise, not a misleading all-zero row). Deliberately does not re-derive matching — that stays the one place it's decided, per `CLAUDE.md` rule 1. Also added the "Staged"/"Manual QBO" resolution pill (already on `FindingsListView`'s rows) to `CleanupAssessmentView` and `BalanceSheetIntegrityView`'s rows too, closing a UI inconsistency where a `VL-CC-PAYMENT-001` finding with an Apply Fix available looked identical to one needing the full guided procedure until opened. 202/202 desktop tests passing.

## Client Question Builder (drafting half only) — still later the same night

Spec's Firm Cockpit section: "Client Question Builder — turns an uncertain finding into a ready-to-send client question, answer attached permanently to the finding." Built the drafting half: `ClientQuestionDrafter.draft(finding:clientName:)` (Core, pure, 5 tests) — deterministic template interpolation over fields the `Finding` and its rule's `RuleIdentity.accountingPrinciple` already carry, no invented content, no Claude call (none exists in this app). `FindingDetailView` gets a "Draft Client Question" button opening an always-editable text area pre-filled from the template — "Mark as Sent" records it via a new `ActivityKind.clientQuestionDrafted` log entry (`AppState.recordClientQuestionSent`), same "recorded, not verified by the app" posture as `attestCompletion`. **Deliberately not built**: the "answer attached permanently to the finding" half — needs a real two-way channel (email, a client portal) this app has none of, and a schema decision about where a reply would live; this only tracks that a question was asked. 207/207 desktop tests passing.

## Real bug found and fixed: "Dismiss" never actually dismissed anything — still later the same night

Every rule (all 15) already had a `guard context.dismissedFindingIDs.contains(findingID) { continue }` check, and `Finding.status` already had a `.dismissed` case, and `ClientStore.upsertFindings` already had carry-forward logic for a non-open status on re-detection. **None of it was ever wired together.** `RuleContext.dismissedFindingIDs` defaulted to `[]` and nothing in `AppState` ever passed a real value; nothing anywhere in the app ever set a `Finding`'s status TO `.dismissed` in the first place. Every "Dismiss" button — in `FindingDetailView`'s manual-QBO path, the Apply Fix path, all of it — was a pure UI navigation (`state.screen = .list`) with zero persistence. The very next sync would silently re-show the exact same "dismissed" finding, unconditionally, on every single one of the 15 rules that had already been built expecting this mechanism to exist.

**This looks exactly like the kind of gap `CLAUDE.md` rule 5 ("green means verified, not merely nothing found") and the project's own "verify before trusting, including yourself" working pattern exist to catch** — a plausible-looking UI action that silently did nothing. Found by reading the actual call sites, not assumed from the mechanism existing in `Core`.

**Fixed**: `ClientStore.dismissFinding(id:)` (new, idempotent — a no-op on an unknown id or an already-non-open finding) actually sets the status. `AppState.dismissFinding(findingID:actorName:reason:)` (new) calls it, logs a new `ActivityKind.findingDismissed` entry, and refreshes state. `RootView`'s `onDismiss` now calls it instead of just navigating. `syncAndEvaluate()` now loads dismissed IDs fresh from the store and actually passes them into `RuleContext` before evaluating, so a dismissed finding is suppressed at detection time — not just hidden by the `.status == .open` filter every list view already applies. **Still not built**: an "un-dismiss" control — a real, acknowledged gap, not an oversight; `dismissFinding` is one-way for now, same posture as other still-incomplete reversal paths in this codebase. 8 new tests (4 `ClientStore`, 1 rule-level end-to-end suppression test — the first test anywhere in the suite that actually exercises `dismissedFindingIDs`, closing a testing gap that let this ship unnoticed in the first place). 212/212 desktop tests passing.

## Second wiring gap found the same way, same night: ProposedAction.reversal was never rendered

Same pattern as the Dismiss bug, smaller: every rule already builds a real `ReversalPlan` (e.g. `CreditCardPaymentMiscodedRule`'s `.reversibleManually(procedure: "Change the category back in QBO if done in error")`), but nothing in `VoiceLedgerUI` ever displayed it — `action.reversal` had zero call sites anywhere in the UI layer. `FindingDetailView.actionSection` now shows a "Reversal: ..." line alongside the existing consequence lines, for both the `.manualQBO` and `.stagedAPI` paths. No new Core logic, so no new tests — this is a pure rendering fix. 212/212 desktop tests passing.

## Third wiring gap, same technique, same night: RuleIdentity.accountingPrinciple never shown to the user

Spec's Firm Cockpit: "Training Mode — every flag answers 'why was this flagged?' with the underlying accounting principle, not just the rule." Every rule already writes a real, plain-English `accountingPrinciple` string (used internally by `ClientQuestionDrafter`, added earlier tonight) — but it had zero UI call sites of its own before this. `FindingDetailView` now shows a "WHY THIS MATTERS" section between the evidence and the proposed action, sourced the same way `ClientQuestionDrafter` looks it up (`RuleRegistry.all.first { $0.identity.id == finding.ruleID }`). This is the "why was this flagged" answer specifically — not the rest of spec's Training Mode (no broader tutorial/help system exists). Pure rendering fix, no new Core logic, no new tests needed. 212/212 desktop tests passing.

**A pattern worth naming, now that it's found three of these in one night**: a value that's computed once by every rule (`accountingPrinciple`, `reversal`) or a mechanism every rule already checks (`dismissedFindingIDs`) is not evidence it's reaching the user — only grepping the actual UI/AppState call sites proves that. Worth a deliberate pass over `Finding`/`ProposedAction`/`RuleIdentity`'s remaining fields (`provenance`, `evidence.highlightedFields` — already confirmed wired) next time this kind of audit is warranted, rather than assuming the rest are fine because these three weren't.

## Fourth fix, same pass: FindingDetailView's "Source:" line was hardcoded, not derived from real data

`FindingDetailView`'s header literally hardcoded `Text("Source: QBO API")` — wrong for `VL-RECON-MISSING-001`/`VL-VENDOR-MISMATCH-001`, whose evidence includes an imported statement line, not only QBO-read data. Now derived from `finding.provenance` (`.qboAPI`/`.importedFile`, deduplicated and joined) instead of a fixed string. 212/212 desktop tests passing.

## Next Best Action — still later the same night

Spec's Firm Cockpit: "Next Best Action — the app says where to start." Firm Cockpit itself (every connected client on one screen) needs a multi-client rollup this app's architecture doesn't have — not attempted. What IS buildable standalone is the single-client decision logic Firm Cockpit would need per-client: `NextBestAction.compute` (Core, pure, 7 tests), a deterministic priority order (open high-severity findings, then an unimported bank statement — Type B pages can't run without one, then the next unlocked incomplete Month-End Close item, else `.allClear`). Rendered as a small banner (`NextBestActionView`, new) at the top of the main Findings List with a "Go" button that navigates to the relevant screen. 219/219 desktop tests passing.

## Fifth real gap found, same audit technique: no screen showed the company name at all

Spec's Firm Cockpit: "Wrong-Client Protection — active company and period pinned to every screen." Grepped every view in `VoiceLedgerUI` for `companyInfo`/`companyName` — zero hits outside `ConnectionView`. Every other screen showed the environment badge (sandbox/production, `CLAUDE.md` rule 7's requirement) but never which company or which period, even though `AppState.companyInfo` and `.currentPeriod` were already sitting right there. Not yet dangerous with one connection at a time, but exactly the rail spec wants in place before a second client connection ever exists. Fixed at the `RootView` toolbar level (`.principal` placement) rather than touching every child view individually, so it's automatically on every screen with one change: `"{company name} · {period} · {environment badge}"`. (Along the way, the pre-existing 9 toolbar buttons had to move into a single `ToolbarItemGroup` — `ToolbarContentBuilder` has the same ~10-child ViewBuilder ceiling as other SwiftUI result builders, and the 10th item silently broke compilation with an unhelpful "extra argument in call" pointing at an unrelated line.) Pure UI wiring, no new Core logic, no new tests needed. 219/219 desktop tests passing.

## Client Memory, With Approval — the last Firm Cockpit item buildable without multi-client infra or the Claude API

Spec: "Client Memory, With Approval — learns categories and patterns, but never silently: 'Always categorize future Odessa Water transactions as Utilities?'" The full version implies an actual recategorization write; scoped down to what's safe without a second write operation: remembering that a specific (rule, vendor) pair is a known non-issue for this client, so it's auto-dismissed on every future sync instead of asked about again.

**`Finding.vendorName: String?`** (Core, additive — same pattern as `LedgerTransaction.lines`/`syncToken` earlier this project, default `nil` so no existing rule's `Finding(...)` call needed to change) is now populated by the 5 rules that have a single clear vendor: `VL-CC-PAYMENT-001`, `VL-PAYROLL-LUMP-001`, `VL-CAT-UNCAT-001`, `VL-VENDOR-MISMATCH-001`, `VL-VENDCREDIT-UNAPPLIED-001`. **`ClientMemoryRule`** (Core, 4 tests) matches on `(ruleID, vendorName)` — exact, case/whitespace-insensitive, deliberately never fuzzy and never cross-rule (a memory rule for `VL-CC-PAYMENT-001` + a vendor does not suppress `VL-PAYROLL-LUMP-001` findings for that same vendor), same conservative-matching lesson as `VL-DUP-VEND-001`/`VL-COA-DUPACCT-001`'s false-positive finding earlier this project. `ClientStore` persists rules (`client-memory-rules.json`, 3 tests) with `add`/`remove` — remove is the real reversal this time, not an acknowledged gap.

**Never silently, by construction**: creating a rule is `FindingDetailView`'s new "Always Dismiss for {vendor}" button — a separate, explicit, two-step-confirmed action, never a checkbox bundled into the existing Dismiss button. Every auto-dismissal it later causes gets its own `ActivityKind.findingAutoDismissedByClientMemory` log entry naming the matched rule and its creator — `syncAndEvaluate()` checks every open finding against active memory rules on every sync (this is what makes "future occurrences" real, not just the one finding that prompted the rule), and `createClientMemoryRule` also retroactively dismisses any already-open matches immediately rather than making the user wait for the next sync. A new `ClientMemoryView` page (toolbar: "Client Memory") lists every rule with a "Forget" button — a rule with no visible list and no way to remove it would be exactly the "silently" the spec's own wording rules out.

7 new tests (4 `ClientMemoryRule`, 3 `ClientStore`). 226/226 desktop tests passing.

## Small polish: import error messages were raw Swift enum dumps

`AppState.confirmCSVImport`/`confirmOFXImport` built the error banner via `"\(result.defects)"` — Swift's default `CustomStringConvertible` for an enum with associated values, e.g. `ambiguousDateFormat(column: "Date", sampleValues: ["03/04/2026"])`, shown directly to whoever is importing a statement. `NormalizationDefect.humanDescription` (new, 2 tests) gives each of the 6 cases a real sentence instead ("Column \"Date\" has an ambiguous date format (could be MM/DD or DD/MM) — sample values: ..."). The devtool's own CLI error output was deliberately left as the raw dump — a developer debugging CSV parsing wants the exact enum shape, not a friendlier sentence. 228/228 desktop tests passing.

## Sixth real gap found the same way: before/after entity snapshots were silently dropped

`ActivityLogView`'s own header text claims: "Can prove: what Voice Ledger detected, proposed, and submitted; what you approved; before/after entity snapshots." The backend's `updatePurchaseLineAccount` response has always included full `before`/`after` QBO entity snapshots specifically for this — but `WriteVerificationResult` (the desktop client's decode of that response) was a plain `Decodable` struct that only listed the summary fields (`verified`, `oldAccountId`, etc.). `JSONDecoder` silently ignores unmodeled keys, so `before`/`after` arrived over the wire and were then thrown away, and `AppState.applyStagedFix`'s `ActivityLogEntry` never had anywhere to put them anyway. The header's own claim was not true for the one write operation that exists.

**Fixed**: `WriteVerificationResult.parse(from:)` (replacing a bare `Decodable` conformance) decodes the known summary fields via `JSONDecoder` as before, AND separately re-serializes `before`/`after` from the same raw bytes via `JSONSerialization` into `beforeSnapshotJSON`/`afterSnapshotJSON` — kept as opaque JSON text rather than partially modeling QBO's entity shape just to preserve it for an audit trail. `ActivityLogEntry` gained matching optional fields (additive), populated in `applyStagedFix`, and `ActivityLogView` shows them in a collapsed `DisclosureGroup` per entry, monospaced and text-selectable, only when present. 2 new `WriteVerificationResult` tests (realistic nested JSON, and the missing-key case). 230/230 desktop tests passing.

## CSV/XLSX/PDF export — the biggest single feature this session, owner-requested

The owner asked for exports that work for clients on Excel but mainly need to work in Google Sheets (free, no subscription). CSV is the trivial universal answer; for a richer format, XLSX was chosen over picking one app to favor — Google Sheets opens `.xlsx` natively (no conversion step) and so does Excel, so one writer serves both asks rather than compromising on either.

**New `Exporting` target** (depends only on Core, mirrors the existing module-boundary discipline — added to `check-module-boundaries.sh`'s forbidden-import list for Core too). Three exporters, all consuming one shared `ExportTable`/`ExportCell` shape (Core, additive, new): `ExportCell` carries both a display string (matches what's already on screen) and an optional raw numeric value, so a dollar amount lands in CSV/XLSX as a real number a bookkeeper can sum, not text that merely looks like one.

- **`CSVReportExporter`** — trivial, RFC 4180 quoting.
- **`XLSXReportExporter`** — a hand-rolled minimal OOXML writer, deliberately **no third-party dependency**. Built on `ZIPArchiveWriter`, a from-scratch ZIP writer using STORED (uncompressed) entries only — a fully valid zip per spec, and choosing it sidesteps needing a DEFLATE implementation entirely, since this only ever writes files it generates itself (never reads arbitrary ones, which is the actual hard direction requiring real decompression). Inline-string cells (no shared-strings table — one less OOXML part to get right for report-sized data).
- **`PDFReportExporter`** — CoreGraphics + CoreText directly, no AppKit. Paginated table layout, proportional column widths from content length.

**Two real bugs caught during manual review while the build sandbox was briefly unavailable** (later confirmed by the actual compiler once it came back): `CGContext(consumer:mediaBox:auxiliaryInfo:)` doesn't exist in Swift — the third parameter is positional, not labeled; and `NSAttributedString.Key.font`/`.foregroundColor` are AppKit extensions unavailable without importing AppKit (deliberately not imported) — fixed by using CoreText's own `kCTFontAttributeName`/`kCTForegroundColorAttributeName` keys instead, which is what `CTLineDraw` actually reads regardless of which key looks more familiar.

**Live-verified with three independent tools, not just unit tests** — the ZIP writer especially warranted this, being hand-rolled: added a `voiceledger-devtool export-sample <dir>` command (no realm/network needed) that writes real `.csv`/`.xlsx`/`.pdf` files from a synthetic table. `unzip -t` confirmed the xlsx's zip integrity with no errors; Python's own `zipfile` module (a completely independent implementation from this writer) read back the exact sheet XML with correct inline-string and numeric cells; `file` confirmed the PDF as a valid "PDF document, version 1.3."

**Wired into every report-style page** via a shared `ExportMenuButton` (VoiceLedgerUI, new) and `AppState.exportTable(_:format:suggestedFilename:)` (presents a native `NSSavePanel` — the user picks the location and clicks Save themselves): Balance Sheet, Profit & Loss, Close Package, Cleanup Assessment, and Activity Log all export now. Each page's existing on-screen data is reshaped into an `ExportTable` at the `RootView` layer — no new data path, no risk of an export disagreeing with what's on screen.

21 new tests (CRC-32 known test vector, zip signature/structure, XLSX cell shape and sheet-name sanitization, CSV escaping, PDF header/pagination). 251/251 desktop tests passing.

## VL-FORCED-RECON-001 built and live-verified — and two real "silently-dropped field" bugs found and fixed the same way, same night

The owner performed a real forced reconciliation in the QBO sandbox UI at Claude's guidance (Checking account, Reconcile screen, statement ending balance deliberately set to $1.00, "Finish now" → "Add adjustment and finish" taken over a real $4,264.76 difference) — specifically to generate live test data for this previously-deferred rule (see §08_RULE_ENGINE.md's now-updated backlog row).

**Two detection hypotheses were tried against the live API and disproven, in the project's own established spike discipline**, before landing on the one that works:
1. `Account.CurrentBalance` on the auto-created "Reconciliation Discrepancies" account (Expense-classified) — read `0` despite the real adjustment. QBO doesn't populate `CurrentBalance` meaningfully for Expense accounts.
2. A direct `JournalEntry` query for the adjustment — none found (7 unrelated old entries, none matching).
3. **Confirmed**: the Profit & Loss report is the only place the adjustment is visible via the API — an "Other Expenses" line literally labeled "Reconciliation Discrepancies" with the real `4264.76` value.

`ForcedReconciliationRule.swift` (new) reads exactly that P&L line. Supporting additions: `NormalizedDataSet.profitAndLossLines` (Core, additive), `QBOEntityKind.report` (not a real QBO entity — exists so `SourceDependency` can name "this rule needs a report, not a transaction list"), `FindingCategory.forcedReconciliation`. 7 new unit tests (empty report → `.cannotEvaluate`, real discrepancy line → finding, no line → pass, zero-balance line → pass, below materiality → pass, negative-signed amount → absolute-value exposure, never `.pass` on partial coverage).

**While wiring this in, found a real, separate, pre-existing bug**: `AppState.syncAndEvaluate()`'s reconstruction of `NormalizedDataSet` (needed because P&L lines and imported statement lines are merged in on top of `QBOSyncClient.sync()`'s own output) was missing `vendorCredits: syncedDataSet.vendorCredits` entirely — it silently defaulted to `[]` via the initializer's default parameter. This meant **`VL-VENDCREDIT-UNAPPLIED-001` has been returning a false-green `.pass` in the real, live, running macOS app since the day it was built** — a direct violation of CLAUDE.md rule 5 ("green means verified... missing or stale data renders gray, never green"). It was only ever proven working via `voiceledger-devtool sync-check`, which builds its own `NormalizedDataSet` correctly and so never exposed the gap. Fixed by adding the missing line.

**Found the identical bug shape a second time, in a second file, the same night**: `voiceledger-devtool sync-check`'s own `main.swift` fetches `profitAndLossLines` and prints them, but then built its `NormalizedDataSet` for rule evaluation from `syncClient.sync()`'s raw output alone — never merging the P&L lines it had just fetched. First live-verification run of `VL-FORCED-RECON-001` against the real sandbox data correctly came back `CANNOT EVALUATE` (not a false pass — the coverage gate did its job) rather than the expected finding, which is what surfaced this. Fixed the same way as `AppState`'s copy: reconstruct `NormalizedDataSet` explicitly with all fields, including `profitAndLossLines`, before evaluating. Re-ran; `VL-FORCED-RECON-001` now correctly fires with the real `$4,264.76` finding at `.high` confidence.

**Lesson worth keeping**: any code path that fetches supplementary data (a report, an extra entity list) *separately* from the base `sync()` call and then reconstructs `NormalizedDataSet` by hand is a place where a field can be silently dropped and the compiler will never catch it, because every field has a default. Two instances of exactly this bug shape were found in one evening, in the only two places in the codebase that do this reconstruction. If a third such call site is ever added, check it against this paragraph before trusting it.

258/258 desktop tests passing after this work (7 net new).

## Cash Flow report added; Trial Balance and aging reports investigated and correctly left unbuilt

Continuing the NOT STARTED list's "cash flow/GL/trial balance/aging reports" item. The backend catalog's `readReport` operation already allowed `TrialBalance`, `GeneralLedger`, `TransactionList`, `CashFlow`, `AgedReceivables`, and `AgedPayables` as `reportKind` values (added early on, never exercised) — none had been checked against a real response before now.

Queried all five live against the sandbox via the production `POST /realms/:realmId/operations/readReport` endpoint (the exact path the desktop app itself calls, not a bypass):

- **CashFlow** — confirmed to share the exact same recursive `Header`/`Rows`/`Summary`/`ColData` + `type == "Data"` leaf shape as Balance Sheet and Profit & Loss (single "Total" money column, plus `group`/`type: "Section"` fields on section rows that the existing decoder correctly ignores). **Built**: `QBOSyncClient.fetchCashFlow`, a "Cash Flow" screen (reuses `FinancialReportView` unchanged), `AppState.cashFlowLines`/`loadCashFlow()`, export wiring — same pattern as Balance Sheet/P&L exactly. 1 new fixture test (real-shaped, including a negative leaf amount). Live-verified via `voiceledger-devtool sync-check`.
- **TrialBalance** — **built as its own type, same session, right after the gap was found.** Its leaf rows carry `ColData` only, with **no `type` field at all** (unlike BalanceSheet/P&L/CashFlow, whose leaf rows are always tagged `"type": "Data"`) — reusing `flatten()` unchanged against this shape would have silently dropped every one of the 53 real account rows in this sandbox's July trial balance and rendered only the "TOTAL" summary line, a false-green report that looks complete while showing almost nothing (exactly the class of bug `CLAUDE.md` rule 5 exists to prevent). It's also structurally a debit/credit report (3 columns: Account, Debit, Credit — a `Money` in one or the other, never both), not a single-amount report like the other three. **Built**: `TrialBalanceLine` (Core, new — deliberately not `ReportLine`), `QBOSyncClient.flattenTrialBalance`/`fetchTrialBalance` (its own decoder, leaf-detected by "has `ColData`, no nested `Header`/`Rows`" rather than by `type`), `TrialBalanceReportView` (VoiceLedgerUI, new — two money columns, no depth/indentation since a real trial balance is flat), export wiring. 2 new fixture tests (the exact live-shaped 3-column rows, including the debit-XOR-credit assertion, and an empty-report case). Live-verified via `voiceledger-devtool sync-check`: all 54 real account rows now render (not just the misleading single TOTAL line), and the total ties out at $10,057,055.33 debit = credit, as it must.
- **AgedReceivables / AgedPayables** — **built, same session.** 6-money-column aging-bucket shape (Current/1-30/31-60/61-90/91-and-over/Total) keyed by Customer or Vendor. Turned out to be MORE irregular than Trial Balance on closer live inspection: the same real report mixes two different leaf-row shapes — a customer/vendor with no sub-locations is a bare untagged `ColData` row (like Trial Balance), but a customer/vendor WITH sub-locations (found live: "Freeman Sporting Goods," 2 sub-addresses) wraps them in a `Header`/`Rows`/`Summary` section whose nested leaves ARE tagged `"type": "Data"` (like Balance Sheet). **Built**: `AgingLine` (Core, new — 6 money fields + depth for the sub-customer indentation), `QBOSyncClient.flattenAging`/`fetchAgedReceivables`/`fetchAgedPayables` — leaf-detected structurally (has `ColData`, no `Header`, no nested `Rows`) rather than by the `type` tag, so both shapes are caught correctly without special-casing either. Also verified live: these reports are "as of today," not period-scoped (no `StartPeriod` in the response `Header`) — the fetch calls send no date params at all rather than the current month's bounds. `AgingReportView` (VoiceLedgerUI, new, shared by both reports — horizontally scrollable for the 6 money columns), export wiring. 2 new fixture tests (the exact live-shaped mixed-leaf data, including the sub-customer nesting, and an empty-report case). Live-verified via `voiceledger-devtool sync-check` against the real sandbox: 23 Aged Receivables lines (including the Freeman Sporting Goods sub-location nesting) and 8 Aged Payables lines, both rendering real dollar figures correctly.
- **GeneralLedger** — **built, same session, completing this report cluster.** Not a summary report at all — a transaction-level ledger, grouped by account, 8 real columns (Date, Transaction Type, Num, Name, Memo/Description, Split, Amount, Balance). Each account section opens with a synthetic "Beginning Balance" row and closes with a "Total for `<Account>`" Summary — verified live against a real account section (Checking) whose one posted transaction was, by coincidence, the exact same `VL-FORCED-RECON-001` adjustment found earlier this session ($4,264.76), which cross-checked correctly here too. Leaf rows here ARE tagged `"type": "Data"` (unlike Trial Balance/Aging), so `flattenGeneralLedger` reuses the same leaf-detection gate as `flatten` — only the column extraction differs (8 columns, not 2). **Built**: `GeneralLedgerLine` (Core, new — includes an explicit `isAccountHeader` flag set by the decoder, deliberately not left for the view to infer from "no transaction type at depth 0," which would silently break if a future column were added), `QBOSyncClient.flattenGeneralLedger`/`fetchGeneralLedger`, `GeneralLedgerReportView` (VoiceLedgerUI, new — a real horizontally-scrollable ledger table), export wiring. 2 new fixture tests. Live-verified via `voiceledger-devtool sync-check`: 216 real lines across every account in the sandbox.

This closes out the entire "cash flow/GL/trial balance/aging reports" NOT STARTED item — all four report kinds the backend catalog already allowed are now built, each with its own live-verified decoder rather than a naive reuse of any other's.

265/265 desktop tests passing after this work.

## Universal Ingestion Tier 1 gained a real Excel (.xlsx) bank-statement importer

The spec's Tier 1 list is "CSV, OFX, QFX, Excel" — Excel was the one format never built. Unlike the `Exporting` target's XLSX *writer* (which deliberately avoided DEFLATE by only ever writing its own STORED-only archives), a real-world `.xlsx` exported by Excel or Google Sheets is DEFLATE-compressed, so reading one for real needed an actual decompressor.

**Built**: `ZIPArchiveReader` (`Sources/Integrations/Imports/`, new) — reads a zip's central directory (found by scanning backward for the EOCD signature, not assumed to be at a fixed offset), handles both STORED (method 0) and DEFLATED (method 8) entries. DEFLATE decoding uses Apple's system `Compression` framework (`COMPRESSION_ZLIB`, which — despite the name — decodes raw DEFLATE with no zlib/gzip wrapper, exactly what a ZIP entry's compressed bytes are) rather than a hand-rolled inflate implementation. `XLSXParser` (new) sits on top: resolves the workbook's first sheet properly via `workbook.xml`'s sheet order + `workbook.xml.rels` (not a hardcoded `sheet1.xml` guess), parses `sharedStrings.xml` (including multi-run rich text), and reads the sheet itself — including a real, non-guessing date-serial-to-date conversion: a numeric cell is only converted from an Excel date serial to a real date string when its cell style's `numFmtId` (read from `styles.xml`) is actually a date format (built-in IDs 14/15/16/17/22, or a custom format whose code contains date-pattern letters) — a plain numeric amount column with no date styling is left as a plain number, never guessed. Produces the same `[[String]]` row shape `CSVParser.parse` does, so it plugs directly into the existing `BankStatementCSVImporter`/confirm-and-correct pipeline unchanged. Legacy `.xls` (OLE2/CFB binary format, detected by its magic bytes) throws a clear, distinct error rather than a confusing zip-parse failure — it's a different container format entirely and out of scope.

**Live-verified against a REAL DEFLATE-compressed archive**, not just this project's own output: built a real `.xlsx` test fixture on disk using the system `zip` command (which uses genuine DEFLATE, exercising the actual decompression path) via a new `voiceledger-devtool xlsx-import-check <path>` command, and independently verified the date-serial conversion against Python's own `datetime` arithmetic (the same cross-check-with-an-independent-tool discipline used for the CRC-32 table and the XLSX writer earlier) — both matched exactly. 7 new tests, including a DEFLATE round-trip using the system `Compression` encoder directly (no external tool dependency for CI), a legacy-`.xls` rejection test, and a blank-column-padding test (Excel omits `<c>` elements for empty cells entirely, which would silently misalign every column after one if not explicitly padded for).

Wired into `AppState.selectFileForImport` (detects `.xlsx`/`.xls` by extension, reads as `Data` not `String` since it's binary) and `BankFeedCleanupView`'s import button/doc comment, updated to say CSV/OFX/QFX/XLSX (a pre-existing stale "CSV" label found in passing — this button never mentioned OFX/QFX either, despite that import path existing since an earlier session).

272/272 desktop tests passing after this work.

## VL-REPORT-TIE-001 — the rule that was explicitly blocked on the report parsers just built

The backlog table's own note for this rule said it "would need two different report parsers built in one pass, not attempted yet." That precondition was met earlier this same session (Balance Sheet already existed; Aged Receivables/Payables were just added) — built immediately after.

**What it checks**: the Balance Sheet's A/R balance is supposed to equal the sum of every unpaid invoice, which is exactly what Aged Receivables enumerates — they're two views of the same open transactions. A mismatch means something posted directly to the A/R (or A/P) account outside the normal invoice/bill-and-payment flow (a manual journal entry, a miscoded deposit), and the aging report can no longer explain what's actually owed.

**Matches accounts by real data, not a guessed label**: rather than hardcoding QBO's default English name ("Accounts Receivable (A/R)"), the rule cross-references `input.accounts` for accounts whose `accountType` is actually `.accountsReceivable`/`.accountsPayable`, then matches Balance Sheet lines by their real names — correct even if an account was renamed, and correct (sums all matches) in the rare case of multiple A/R accounts.

**Wiring**: `NormalizedDataSet` gained `balanceSheetLines`/`agedReceivablesLines`/`agedPayablesLines` (additive, same "empty means not fetched" posture as `profitAndLossLines`). Threaded through both `AppState.syncAndEvaluate()` and the devtool's `sync-check` reconstruction **in the same change** this time — both call sites are commented explaining they must not repeat the `vendorCredits`/`profitAndLossLines` omission bugs found earlier this session in this exact spot.

8 new unit tests, including one confirming a missing account-type match skips silently rather than guessing. **Live-verified** against the real sandbox: A/R ties out exactly (correctly produces no finding), while A/P is off by a real $110.00 — a genuine finding, not a bug, confirmed genuine by the fact A/R did NOT also fire (ruling out a systematic sign or currency error affecting both sides equally).

280/280 desktop tests passing after this work.

## VL-FEE-AVOIDABLE-001 — one more backlog rule, keyword-based, no new capability needed

Same pattern as `VL-PAYROLL-LUMP-001`: checks vendor name AND memo (both already synced on every `LedgerTransaction`) for specific fee-related terms — "overdraft", "nsf", "late fee", "finance charge", "penalty fee", etc. Deliberately NOT the bare word "fee" alone, which would false-positive on a real vendor like "ABC Filing Fee Services" (a dedicated unit test covers exactly this case).

**Honestly documented as not live-fired**: none of the 24 real transactions synced this session are fee-shaped, so this rule has never produced a live positive finding — confirmed via `voiceledger-devtool sync-check` (correctly returns `PASS`, `coverage=complete`, `checked=24`, not a silent skip). Shipped on 8 unit tests alone rather than overclaiming live verification it doesn't have — the same honesty standard this project applies to itself elsewhere.

288/288 desktop tests passing after this work.

## Client Switcher — explicitly scoped by the owner 2026-08-18, not yet built

**Owner's own words**: "eventually we will need to have the feature where I pick what client to work with their data like a drag down feature. It doesn't need to be implemented right this instant but making sure it's part of the scope." Recording this here so it survives to whichever session eventually builds it, per this handoff doc's whole purpose.

**This is narrower than "Firm Cockpit"** (spec's full multi-client rollup dashboard — every connected client's status on one screen, already tracked as backlog above) — the owner is asking for the simpler prerequisite: a picker to select WHICH connected client's data you're looking at, in an app that currently only ever looks at one. Worth keeping these two distinct in future planning — the picker is a small, well-scoped piece; the rollup dashboard is a much bigger one that depends on the picker (or at least a client registry) existing first.

**Checked how much rework this would actually need — genuinely not much**, because CLAUDE.md rule 9 ("client isolation by `realmId` — never a mutable 'current client' variable") was followed from day one, not bolted on after: `ClientStore` is already scoped by a `realmId`-named subdirectory (`ClientStore.swift`, `self.directory = rootDirectory.appending(path: realmID.rawValue, ...)`), `RealmID` is already a distinct phantom-typed value (not a bare `String`) threaded through every Core/Integrations call, and `RuleEngine`/`NormalizedDataSet` have zero global or singleton client state — everything is passed explicitly. The gap is narrow and specific:

1. **`VoiceLedgerApp.swift`** currently reads exactly one `VOICE_LEDGER_REALM_ID` from an environment variable at process launch and builds exactly one `AppState` for it — there is no in-app concept of "the other clients I've connected." Fixed by launch-time env var only; nothing here reads it again after startup.
2. **No connected-client registry exists yet.** `ConnectionView` (Page 1.3, built) shows the CURRENT realm's name/health — it has never needed to enumerate others because there aren't any others to enumerate. A registry (list of `{realmId, companyName, environment}` the owner has ever connected) would need to live somewhere outside any single realm's own `ClientStore` subdirectory — the one piece of storage that's ACTUALLY new, everything else already exists per-realm.
3. **Switching would mean re-instantiating `AppState`/`ClientStore`/the sync client for the newly-picked `realmId`**, not mutating fields on the existing one — matches how `VoiceLedgerApp.swift` already constructs these once at launch; a switcher would just make that constructor callable again on demand instead of only at process start.

**Not attempted this session** — flagged and scoped only, per the owner's own instruction not to build it yet.

## 2026-08-28 — Desktop launcher ("Voice Ledger Launcher.app"), and three real bugs a "looks done" launcher would have shipped with

Built per owner request: a double-clickable, unsigned macOS app bundle (repo root, `Voice Ledger Launcher.app/Contents/MacOS/launch` is a plain bash script — no Xcode/signing) that starts the backend if needed, launches the desktop app if needed, detects a real port conflict vs. its own already-running instance, and shows a native dialog — no Terminal ever. A symlink at `~/Desktop/Voice Ledger Launcher.app` points into the repo (one file, one macOS-privacy identity, not two divergent copies).

**Every one of the three real bugs below only showed up when actually double-clicked — reading the script never would have caught any of them, and testing "it built" or "the process is alive" would have shipped all three:**

1. `arch -arm64` needed on the backend start — a GUI-launched (`open`, not Terminal) node process ran under Rosetta and failed to load better-sqlite3's arm64-only native module, despite the identical `npm run dev` working fine interactively.
2. `swift build` cannot run from inside the launcher at all — SwiftPM's manifest-evaluation step uses its own internal Seatbelt sandbox, sensitive to the GUI-launch temp-directory/session context in a way Terminal never hits (`couldn't determine the current working directory`). **This is not a Files & Folders / Full Disk Access permission** — confirmed live it never appears in either list; there is no System Settings fix. The actual fix is architectural: the launcher never builds, only runs the binary Claude Code already built via a normal `swift build -c release`.
3. Even with a live process, a raw (unbundled) executable launched via `nohup binary &` comes up under AppKit's "background only" activation policy — no Dock icon, no window, confirmed via `osascript`'s "background only of process" reporting `true`. Fixed in `VoiceLedgerApp.swift` itself (`NSApp.setActivationPolicy(.regular)` + `.activate()` on appear), not just the launcher, so this holds regardless of launch method. Separately, the launcher never passed `VOICE_LEDGER_BACKEND_URL`/`SESSION_TOKEN`/`REALM_ID`/`ENVIRONMENT` at all — it would have shown a configuration-error screen even with a window fixed. Realm lookup uses a new `backend/spike/latestConnection.ts` (node/better-sqlite3) rather than the system `sqlite3` CLI, which hit its own, different "authorization denied" reading the identical file from this exact launch context — `node` reading that file already worked (proven by the backend itself running fine), so the fix was using the binary already proven to work rather than chasing why `sqlite3` specifically doesn't.

**Verification method that actually worked, after several rounds of wrong guesses**: don't trust "the script looks right" or "the process is alive" — check `background only of process "VoiceLedgerApp"` and `count of windows` via `osascript`/System Events, and check the process's RSS memory (a real running SwiftUI app is ~100+MB; a process stuck early in a failed launch is often under 1MB). A future session touching this launcher should re-verify with that same check, not just re-read the script.

**Known confound worth remembering**: this Mac often has an entirely separate, unrelated, actively-running "Claude Voice Ledger" project at `~/Documents/Claude Voice Ledger` (its own launcher, its own node/vite/esbuild servers) — do not confuse its processes/files with this one, and expect a busier machine (slower `npm run dev` startup) when both are running at once.

## 2026-08-28 — Ask [AI] panel built and live-verified: OpenAI, not the Claude API

The owner's own words: "were going to actually use openai api integration." Every earlier reference in this doc, CLAUDE.md, and docs/VOICE_LEDGER_SPEC.md to "Claude API," "Ask Claude panel," or "Claude API key" describing a not-yet-built feature is now stale in that one specific respect — the integration is OpenAI (`gpt-4o-mini`, the default I proposed and the owner explicitly confirmed rather than picking another model). CLAUDE.md itself was not edited to rename these references; treat "Claude API"/"Ask Claude panel" language there and in the spec as meaning "the app's chosen AI provider," not literally Anthropic's API, until/unless the owner asks for the docs themselves to be reworded.

**What shipped, same session, live-verified against the real OpenAI key** (not just built): backend (`backend/src/ai/openaiClient.ts`, `backend/src/routes/ai.ts` — `POST /realms/:realmId/ask-ai`, `GET /ai/status`, `POST /ai/settings`), desktop (`BackendClient.askAI`/`getAIStatus`/`setAIEnabled`, `Core/AskAIContext.compose`, `FindingDetailView`'s "ASK AI" section, `ConnectionView`'s "AI CONNECTION" card with the spec's kill switch). The API key lives only in `backend/.env` (`OPENAI_API_KEY`), gitignored, never reaches the desktop process.

**CLAUDE.md rule 1's boundary is enforced in two independent places**, not one: `AskAIContext.compose` (Core, pure) only ever serializes a `Finding`'s own already-computed fields into plain text, and the backend's own system prompt (`routes/ai.ts`'s `SYSTEM_PROMPT`) separately instructs the model never to state a number beyond that context, never to give tax/legal advice, never to claim a QBO write happened. Stress-tested live: asked it to compute a 20%-markup dollar figure and tax owed on a real finding — it correctly refused both and pointed to the app's own numbers / a CPA instead. Logs never carry prompt/completion content (confirmed live in the actual log output), only event names and latency — the logger's pre-existing forbidden-fields list already anticipated this feature before it existed.

**Getting sandbox/live access for this, same technique as §"sandbox access was never actually blocked" above**: `backend/spike/mintDevSession.ts` plus `backend/.env`'s already-stored `OPENAI_API_KEY` is all a session needs — `voiceledger-devtool ask-ai-check` (new) runs the real Swift call path end to end, costs a small amount of real API usage.

## 2026-08-28 — Page 10 (Taxes) built, deliberately with zero tax law — do not add any without re-reading this

The owner's own words when asked to unblock this page: "we want to stay legally safe and make sure were not making any wrong calculations or and all tax laws are correct." Read literally, that's not satisfiable by any AI-generated tax logic — bracket tables, self-employment rates, and jurisdiction rules change, vary by entity type and locale, and an LLM (including whichever one is reading this) cannot guarantee they're current or complete for a specific business.

**The resolution actually shipped**: `Core/TaxEstimate.swift` contains no tax law at all, by design, not by omission. It does exactly two things: (1) reads QBO's own real "Net Income" P&L summary line — no computation, just extraction, label/shape live-verified against the real sandbox — and (2) multiplies that by a rate the USER types in (from their own CPA), never a rate this app proposes, defaults, or looks up. If a number on this page is ever wrong, the cause is either QBO's own figure or what the user typed — never a tax rule inside this codebase, because there is no tax rule inside this codebase. The page leads with an explicit "not tax advice" disclaimer and repeats a shorter version next to the one number it computes.

**If a future session is asked to make this page "smarter"** (actual bracket math, self-employment tax, deduction estimates, multi-state apportionment, anything that requires knowing what a real tax rule says) — that is a materially different, much riskier feature than what's built here, and needs the owner's explicit, informed sign-off on the liability question first, ideally after they've asked an actual CPA or lawyer whether an AI-maintained tax calculator is something they want in a product they'll hand to real clients. Don't infer that sign-off from "make it the best" language the way this session might read as license to add tax law — it explicitly isn't; the owner's own qualifier ("adhering to that legally safe") is the operative instruction, not the general "make it the best."

## 2026-08-27 — sandbox access was never actually blocked; a Claude Code session can get it itself

**Do not re-flag "no sandbox access" as a blocker without first trying this.** The 2026-08-25 entry below says this session had none — true for THAT session, but the fix turned out to be one command, not owner involvement: `backend/spike/mintDevSession.ts` (already existed, built 2026-08-17) re-issues a session token for a realm that's ALREADY connected, reading the encrypted refresh token already sitting in `backend/data/voiceledger.sqlite` (gitignored, persists across sessions on this machine). No browser OAuth, no owner action, nothing time-limited beyond the refresh token's own ~100-day life (last connected 2026-08-16, so good through roughly mid-November 2026).

**How, concretely** (from `backend/`, with `backend/.env` populated — it already is, also gitignored, also persists):
1. `npm run dev` — starts the backend on `:3000` against the sandbox realm already in `.env`/the sqlite file.
2. `npx tsx spike/mintDevSession.ts <realmId> /tmp/session-token.txt` — the realmId is whatever's in `backend/data/voiceledger.sqlite`'s `connections` table (`sqlite3 backend/data/voiceledger.sqlite "SELECT realm_id FROM connections;"` — as of this writing, `9341456442848752`). Refuses to run for an unconnected realm, so it can't fabricate access to a company that was never authorized.
3. Export `VOICE_LEDGER_BACKEND_URL=http://localhost:3000`, `VOICE_LEDGER_SESSION_TOKEN=$(cat /tmp/session-token.txt)`, `VOICE_LEDGER_REALM_ID=<realmId>`, then `voiceledger-devtool health`/`sync-check`/`tax-check` (or any new gate-verification command worth adding) all work directly against the real, live sandbox.
4. For a raw one-off entity check before committing to a typed catalog operation (`backend/spike/checkFullyQualifiedName.ts`, `checkTaxEntities.ts` are real examples, not just scaffolding — keep this pattern for the next one): `QBO_SPIKE_REALM_ID=<realmId> npx tsx spike/checkWhatever.ts`, using `QboRawClient` the same way those two do.

**What this unblocked in the same session it was found**: `LedgerAccount.fullyQualifiedName` went from "not spike-verified" to live-confirmed (90/90 accounts, 8 real leaf-Name collisions matching `ChartOfAccountsCleanupTests`' synthetic cases exactly) · Sales Tax Review (Page 9) went from "needs sandbox verification" to shipped — `readTaxCodes`/`readTaxRates`/`readTaxAgencies` all live-verified before being added to the catalog, not designed from documentation.

**Still true, not removed by this**: a genuinely NEW write operation (anything beyond `updatePurchaseLineAccount`) still needs its own capability spike and owner approval before shipping — this only removes "no sandbox access" as an excuse not to even TRY the read-only verification step first. Production QBO access is a separate, unrelated question — this is sandbox only (CLAUDE.md rule 7).

## Corrected 2026-08-25 — owner ROI pivot, Gauntlet Loop deprioritized, real scope closed

**Context**: the owner raised a direct ROI concern about the Gauntlet Loop's multi-round critic pattern ("i only have so much claude usage... do we even need this or should we straight up just work on building the app") partway through Gauntlet C round 9 of `VL-DUP-EXP-001`'s hardening pass. Direction going forward: work directly, no multi-agent critic rounds unless explicitly requested again, prioritize closing real missing scope over further hardening. Gauntlet C was stopped by this instruction, not its own 2-consecutive-clean-round condition — 3 documented landmines were deliberately left open (see workbench.md's final entry for that pass).

**Also corrected the same session**: an inaccurate status claim was made to the owner ("1 of 27 rules built") based on this doc having gone stale — a direct code check found 18 real, live, registered rules in `RuleRegistry.all`, and all 7 report types (not "mostly PLANNED") fully built with real data, loading/error states, and export. Both corrected to the owner directly before further work. **Lesson: verify against `RuleRegistry.all`/`RootView`'s screen switch directly before reporting status, not this doc** — it goes stale faster than the code changes.

**Built since the pivot** (all direct work, no Gauntlet Loop): all 18 rules brought to the same evidence/narrative/risk-text standard `VL-DUP-EXP-001` had · Close Package extended with Cash Flow/Trial Balance/Aging summaries · **variance analysis** (`Core/VarianceAnalysis.swift`, wired into Balance Sheet/P&L report pages — this closes that item in the NOT STARTED list below) · **Page 2, Scope & Period Lock** (`Core/PeriodLock.swift`, scoped down: engagement scope + Voice Ledger's own local lock; QBO's `BookCloseDate` stays unread, already verified absent from this sandbox) · **Page 6, Chart of Accounts Cleanup** (`Core/ChartOfAccountsCleanup.swift`, read-only duplicate detection — matches on `FullyQualifiedName`, never leaf `Name`, specifically because `VL-COA-DUPACCT-001`'s investigation below already proved leaf-name matching unsafe; added `LedgerAccount.fullyQualifiedName`/`QBORawAccount.FullyQualifiedName`, not independently spike-verified present in this sandbox's response, so an account missing it is excluded from detection rather than falling back to leaf name) · **`VL-RECON-AMBIGUOUS-001`** (the "duplicate items" half of Page 5's reconciliation spec — a statement line matching 2+ posted transactions equally well; only the "unmatched" half existed before) · **Close Package carry-forward items** (`Core/CarryForwardMark.swift`, marked from `FindingDetailView`, never touches `Finding.status`) · **Close Package "corrections made"** (`ActivityKind.isCorrection`, a filtered view of the Activity Log, not a separate ledger with its own storage).

**Still genuinely open, and why each one stalled here**: Batch Fixes (Page 7) and Sales Tax Review (Page 9) both need new backend read/write operations verified against a live sandbox — this session had no sandbox/OAuth access, so neither was attempted rather than designed blind. Taxes (Page 10) needs an owner scope decision before building anything — "estimates possible exposure" is ambiguous between a safe trend-only display and a riskier assumed-rate dollar estimate that could look like real tax advice; flagged to the owner, not yet decided. Firm Cockpit and the Client Switcher remain owner-deferred (see the memory note and §"Client Switcher" above). Claude API integration remains owner-deferred. Reconciliation as a fully separate Page 5 screen (distinct from being folded into Bank Feed Cleanup) was not built — the two "calculates difference" and "duplicate items" pieces the spec asks for both now exist, just inside Page 4's screen, not a dedicated Page 5 one; a real but smaller gap than it looks from the page list alone.

## NOT STARTED

**Corrected 2026-08-18 — this list went stale within the same night on two points, same as §19's own warning about handoff docs describes:** Universal Ingestion's "cross-foot validation + learned-mapping persistence" is no longer accurate as a single unbuilt unit — learned-mapping persistence (§9.6 stage 6, CSV only) IS built, cross-foot validation itself is still not (OFX's stated ending balance is extracted and shown, informational only — see above). "Reporting and Close Package" is also no longer accurate as fully unbuilt — Balance Sheet, P&L, and now a real (partial) Close Package page all exist; what's still missing from reporting is cash flow, general ledger, trial balance, and aging reports specifically, plus a branded/exportable document format.

5 of the 12 workflow pages entirely (Page 3, Connection [not one of the original 12], Page 4, Page 8, and Page 11 [checklist slice only] have minimal shells; Cleanup Assessment — also not one of the original 12 — has a minimal shell too) · Universal Ingestion Tiers 2/3, Tier 1's automated cross-foot validation (Excel import shipped 2026-08-18, see above) · voice · a branded exportable document format (Cash Flow, Trial Balance, Aged Receivables/Payables, and General Ledger all shipped 2026-08-18, see above — every report kind the backend catalog allows is now built), and the rest of the full-spec Close Package (variance analysis, a corrections ledger distinct from the Activity Log, carry-forward items, client Q&A, Ask Claude history) · Firm Cockpit · the Client Switcher (owner-scoped 2026-08-18, see above — narrower than Firm Cockpit, a prerequisite for it) · Claude API integration (queued, explicitly deferred by the owner — see the separate memory note) · 5 of 27 backlog rules, plus 3 owner/session-driven additions beyond the backlog (`VL-VENDCREDIT-UNAPPLIED-001`, `VL-FORCED-RECON-001`, and `VL-REPORT-TIE-001` — all three no longer deferred, see above; 21 built as of 2026-08-18) · spike Waves 2 (negatives) and 4 (one of two items done — see above) · the staged-write path's remaining pieces (`StagedCorrection`, a separate §10.6 resolution probe mechanism — §10.5a's response-validation chokepoint IS built, see above) · `VL-COA-DUPACCT-001` / `VL-BS-SUSPENSE-001` / `VL-PERIOD-CLOSED-001` — investigated and deliberately deferred, see above, not simply unattempted

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

**Status: both A and B are now applied to the docs (`docs/phase-0/10_STAGING_APPROVAL_AUDIT.md`), 2026-08-16. A is now also implemented in backend code, 2026-08-18 — see below. B remains design-only, correctly, since it's a Phase 2 decision about a page that doesn't exist yet.**

**A. HTTP 200 is not success.** Validate every write response on its **body**, not its status. A fault element anywhere in a 200 is a failure. An empty or structurally unexpected body is `UNKNOWN` → resolution probe. Single chokepoint in backend response handling so no operation can forget. Add a structural test asserting no code path treats 2xx as success without body validation. **This also changes the probe's step 1** — it should first ask whether the original response was well-formed, since an anomalous 200 is the case where we least know what happened. *Documented as `§10.5a` with a `classifyWriteResponse` design and a revised probe numbered step 1.*

**Implemented 2026-08-18** (`backend/src/qbo/writeResponse.ts`) — `classifyWriteResponse(body, entityKey)` is the chokepoint: a `Fault` embedded anywhere in the body is `{kind: "unknown", reason: "faultInside2xx"}` with the real QBO error message extracted; a missing/malformed expected-entity key is `{kind: "unknown", reason: "emptyOrMissingExpectedEntity"}`; otherwise `{kind: "success", entity}`. Scoped smaller than the full original design: since `QBOClient.post()` already throws on a non-2xx status, this chokepoint only ever sees a body that arrived with a 2xx — the "clean 4xx-rejected" case the original enum's `.rejected` variant covered doesn't reach it, so only the `.unknown` branches were needed. Wired into `updatePurchaseLineAccount`: a `faultInside2xx` result throws immediately with the real QBO fault message (502) — no more silently falling through to an unexplained `verified: false`. An `emptyOrMissingExpectedEntity` result deliberately does NOT throw — it falls through to the SAME independent round-trip GET the operation already does, which is this catalog's actual stand-in for the §10.6 resolution probe (not built as a separate mechanism yet, and arguably doesn't need to be for an operation that already re-reads from scratch regardless of what the write response said). 5 new unit tests for the classifier itself, 1 new integration test proving `updatePurchaseLineAccount` surfaces a real fault message instead of swallowing it. **Live-verified**: ran the write op through the changed code path against the real sandbox (disposable purchase #227) — `verified: true`, confirming the new chokepoint doesn't disturb the already-working success path. A structural "no operation bypasses the chokepoint" lint-style test was NOT added — with exactly one write operation in the catalog, that test would only prove the single call site was written correctly, which the integration test above already does more directly; worth adding once a second write operation exists and "did the new one forget to call it" becomes a real risk. 53/53 backend tests passing (up from 47).

**B. Sparse updates lose data.** Mark §10.3's round-trip fidelity check explicitly as **verified-necessary** with the fixture reference, so nobody removes it later as redundant. Page 7 must use **full-entity updates with round-trip verification**. **This question was answered, not left open:** an assessment was written into `docs/phase-0/CAPABILITY_CLASSIFICATION.md` (Page 7 section) — recommendation, not a unilateral decision: keep Page 7 as a real API write path for single-field reclassification, add a QBOA hand-off as the recommended path specifically for line-level batch edits where the round-trip cost is highest. Still a Phase 2 decision, not settled, but no longer an open question with no answer on record.

**C. Two interface accommodations — design only, do not build the rules. Both landed as design, 2026-08-16:**
- **Relationship-before-category gating.** `RuleIdentity` gained a `ruleClass: RuleClass` field (`.relationship`/`.categorization`) and the engine (`RuleEngineActor.swift`) implements the gating branch — exercised by a fixture-only relationship rule in tests, since no real relationship rule ships yet. See `docs/phase-0/08_RULE_ENGINE.md` §8.2a.
- **Many-to-one matching contract.** `StatementMatch` designed with `bankSide`/`ledgerSide` as arrays (sets), `MatchReason`, `MatchTolerance`, `netDifference`. See `docs/phase-0/09_INGESTION_PIPELINE.md` §9.11. No matcher implementation exists — correctly, since no import pipeline exists yet either (§9).

## `gatedTransactionIDs` is entity-kind-blind — a real, verified, currently-dormant landmine, deliberately not fixed yet

Found 2026-08-23 during a Gauntlet Loop hardening pass on `VL-DUP-EXP-001` (a fresh critic traced §8.2a's gating mechanism while investigating `context.gatedTransactionIDs.contains(a.id)` at that rule's own gating check). Full technical writeup and the fix shape (a `(entityKind, id)`-tagged key, not a bare `Set<String>`) are in `docs/phase-0/08_RULE_ENGINE.md` §8.2a — this entry is the pointer so it survives to whichever session eventually builds the next relationship-class rule.

**The short version**: QBO's `Id` is unique only per entity type, but the gate set built in `RuleEngineActor.swift` and consumed identically by 8 rule files is a bare `Set<String>` with no entity-kind tag — a `Purchase` #12 and a `Bill` #12 colliding would wrongly gate the wrong one. **Verified NOT live today**: the only `ruleClass: .relationship` rule that exists, `VL-CC-PAYMENT-001`, only ever gates `.purchase`-kind transactions, so no real collision is possible yet.

**Explicitly decided, 2026-08-23: document and defer, don't fix now.** The owner's own call, given two things verified before asking: (1) this touches `RuleEngineActor.swift` plus 7 rule files beyond the one this hardening pass was scoped to, and (2) it provably cannot fire today. Fixing it now would mean guessing at a shape for a hypothetical future relationship rule; fixing it when that rule is actually built means verifying the fix against the real thing — the same "verify before designing around it" discipline this whole document tries to hold itself to. **Do this when the next relationship-class rule touches a non-`Purchase` entity**, not before.

**A second, smaller instance of the same class of finding, same day**: `RuleContext.gatingTransactions` (`RuleEngine.swift`) rebuilds a context without passing `asOfDate` through, silently resetting it to "today" instead of preserving the caller's value. Documented directly in that method's own doc comment rather than here in full, since it's a single-file, single-line fix when needed. **Confirmed not live today** the same way — no production call site ever supplies a non-default `asOfDate`. Fix when an age-based rule (e.g. `VL-BS-UNDEP-001`) is ever tested end-to-end through the full engine with a fixed test date.

## A resolved finding that genuinely recurs stays silently stuck `.resolved` — a real, verified, deliberately-undecided landmine

Found 2026-08-24 (Gauntlet Loop, Gauntlet B round 12) while hardening `VL-DUP-EXP-001`'s finding surface, specifically checking whether the newly-added `findingResolved` Activity Log entry (round 10) stays honest given every way its underlying `.resolved` transition can be reached. Full writeup, doc comment, and a permanent regression test proving the behavior are at `desktop/Sources/DB/ClientStore.swift`'s `upsertFindings` and `desktop/Tests/DBTests/ResolvedFindingRecurrenceTests.swift`.

**The short version**: `ClientStore.upsertFindings` deliberately preserves a finding's `.resolved`/`.dismissed` status across a resync that re-detects the same deterministic id — this exists on purpose, so a stale re-detection (e.g. a resync that runs before an exclusion has actually taken effect) can't flip a finding back open by accident. But `FindingIDGenerator`'s id is a pure hash of `(ruleID, version, realm, period, sorted affected-transaction ids)` — so a *genuine* recurrence (the exact same problem actually comes back, e.g. someone un-voids a transaction that had previously triggered an `isVoided`-exclusion resolution) produces the identical id too, and is silently swallowed the same way. No Activity Log entry marks the recurrence, the finding stays invisible in the open list, and the original `findingResolved` note ("the underlying issue appears to be fixed") is left standing in the permanent record, now false.

**Explicitly not fixed in this run.** Unlike the round 10/11 logging gaps (additive, low-risk), this is a genuine resolve/reopen *semantics* decision — reopening on any re-detection risks reintroducing the flip-flop bug the current behavior exists to prevent, and the right fix likely needs to distinguish "stale re-detection, same sync cycle's data" from "a new sync cycle genuinely re-observed this" (e.g. a resolved-then-redetected finding could get a fresh id via a resolution-generation counter, or reopen only when detected in a LATER sync than the one that resolved it) — a design call for the owner, not a call to make alone mid-hardening-pass. **Do this when a real client's resolved finding is confirmed to have actually recurred**, or when the owner explicitly decides the semantics, not before.

## `AppState.pendingImport`/`.importError` silently discard a second in-progress import — FIXED 2026-09-05

Found 2026-08-24 (Gauntlet Loop, Gauntlet B round 21) during an exhaustive sweep of every stateful property on `AppState` for the same "single scalar meant for one in-flight operation, actually shared across however many a user can start" shape that `applyingFixFindingIDs`/`findingActionInFlightIDs` had before rounds 19/20 fixed them for `VL-DUP-EXP-001`'s own finding-action buttons.

**The short version**: `ImportBankStatementView`'s Cancel button was never disabled while `confirmCSVImport`/`confirmOFXImport` awaited its own store write. Cancelling an in-progress import and starting a second one on a different file let the FIRST import's still-resuming `Task` later unconditionally overwrite `pendingImport`/`importError` with its own value once it finished — silently discarding the second import's confirm-sheet state (or a real, newer error) with zero indication anything happened.

**Fixed 2026-09-05**, using the simpler of the two fixes this entry originally proposed: a new `AppState.isConfirmingImport` flag (see its own doc comment) is set for the duration of `confirmCSVImport`/`confirmOFXImport`; `cancelPendingImport()` is now a no-op while it's true, and `ImportBankStatementView`/`ImportOFXStatementView` both disable Cancel and Confirm (and show an "Importing…" indicator) for the same reason. Only one import confirm can be in flight at a time now — the view-layer disabling and the state-layer guard are both real, not just a UI nicety, since a rapid double-tap can beat SwiftUI's re-render but cannot beat the guard in `AppState`.

## `ClientMemoryView` ("Forget" button) — FIXED 2026-09-05

Round 17 (2026-08-24) found it had the same silent-failure-on-error shape rounds 13-16 fixed on `VL-DUP-EXP-001`'s own finding surface. Round 23 (2026-08-24), verifying the round-22 `dismissFinding` fix and checking every sibling `ClientStore` method for the same class of bug, found `removeClientMemoryRule` also had round 22's issue: `ClientStore.removeClientMemoryRule` was a silent no-op on an unknown id with no return value, but `AppState.removeClientMemoryRule` unconditionally logged `.clientMemoryRuleRemoved` regardless — a double-tap on "Forget" (no in-flight disabling existed) made the second call a genuine no-op that still got logged as if it removed something, a false record in the Activity Log.

**Fixed 2026-09-05.** `ClientStore.removeClientMemoryRule` now returns `Bool` (mirroring `dismissFinding`'s round-22 fix exactly), and `AppState.removeClientMemoryRule` only logs `.clientMemoryRuleRemoved` when that call actually removed something. Added `AppState.clientMemoryActionInFlightIDs`/`clientMemoryActionError`, keyed by `ClientMemoryRule.id` (mirroring `findingActionInFlightIDs`/`findingActionError`), with `ClientMemoryView`'s "Forget" button disabling per-row while in flight and showing the error inline on failure. Two new `ClientStoreTests` cases lock in the no-op-reports-false behavior (double-removal and unknown-id).

## Gauntlet Loop hardening pass on `VL-DUP-EXP-001` — 6 rounds, 7 real bugs found and fixed

The user ran a formal adversarial hardening exercise (the `voice-ledger-gauntlet-loop` skill) against the original vertical-slice rule and its finding surface, explicitly scoped to this one rule — "do not proceed to the other 26 rules, the Cleanup Assessment, or step 1.3." Six independent fresh-context critic rounds attacked `DuplicatePostedExpenseRule.swift`; each real gap found was fixed and its fixture kept permanently in `DuplicatePostedExpenseRuleTests.swift` (75 tests total, up from 16 at the start of this pass) rather than discarded once green.

**Real bugs found and fixed, in the order found:**
1. `Finding.vendorName` was never populated, even though this rule's entire match key IS the vendor and five sibling rules already set it — meant Client Memory's "Always Dismiss for `<vendor>`" could never suppress a recurring false positive from this specific rule.
2. The materiality-floor guard compared `Money` by signed value, not magnitude — a negative-amount duplicate pair (a real QBO shape: a vendor rebate/correction posted directly as a negative `Purchase`) bypassed detection entirely regardless of size.
3. Two array entries sharing a literal identical `id` (a hypothetical pagination/merge double-fetch) produced a phantom "duplicate" finding whose only remediation would void the one real transaction — `id` is QBO's own primary key and can never legitimately collide.
4. The finding `title` string was missed by fix #2 — it kept showing the raw signed amount (a negative number) even after `dollarExposure`/`severity`/the consequences text were all correctly showing the positive magnitude.
5. T2 (DocNumber match) evidence claimed `"date"` and `"paymentAccount"` as matched, even though T2's own match condition never checks either — and because T1 runs first and unconditionally claims any pair matching both, **every real T2 finding that will ever exist is guaranteed to differ on at least one of those two fields by construction**. Actively misleading, not just incomplete, since the guided procedure asks the human to confirm against the bank statement.
6. The guided procedure's "Locate the duplicate Purchase (`id`)" step named one specific transaction as settled fact, but which of the pair got that label was purely an artifact of incidental array-traversal order — the identical real-world pair, fed in the opposite order, would name the *other* transaction. Rewritten to name both candidates neutrally and let the (already-required) bank-statement check decide.

Two documented-nil-vendor and two "confirmed correct by design" decisions were also locked into the permanent test corpus along the way (T2 firing across different payment accounts; two genuinely separate real purchases coincidentally matching on every field still firing T1) so a future engineer doesn't "fix" intentional behavior into a regression. Two legitimate cross-cutting gaps were found, independently re-verified, and correctly escalated to the owner rather than fixed out-of-scope — see the `gatedTransactionIDs`/`asOfDate` entry above.

**Stop condition met**: rounds 5 and 6 were both clean (zero new real bugs after genuine adversarial effort, including deliberately stacking every earlier round's fixed edge cases together looking for interaction bugs, and attacking at scale — up to a five-way mutual-duplicate cluster and multiple independent clusters at once). Per the loop's own rule, this closes Gauntlet A on this rule.

**Bonus, found by round 5, fixed the same day**: `VL-DUP-EXP-002` (`CrossAccountDuplicateExpenseRule.swift`) is this rule's live, registered sibling (its own doc comment calling it "left in the backlog" was stale) and had the identical class of bugs — missing `vendorName`, no id-collision guard, the same signed-vs-magnitude bug, and its own version of the evidence-honesty bug (claiming `"paymentAccount"` matched even though the rule's defining condition *requires* the two accounts to differ — arguably worse than VL-DUP-EXP-001's version, since it's not just "usually differs by construction," it's *guaranteed* to differ). All four fixed, mirroring the exact fix pattern. Not run through its own multi-round gauntlet — brought up to the same baseline, not independently hardened.

Gauntlet B (finding-surface actionability: real evidence values instead of field names, a plain-English narrative sentence, and the spec'd-but-never-built `preApprovalChecklist`) and Gauntlet C (a false-green honesty audit across the slice) are the next workstreams in this same pass, tracked live in `workbench.md` at the repo root.

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
- **Sensitive-write risk tiers** — low/moderate/high/blocked. The real gap: **is the transaction already reconciled?** Changing it breaks the reconciliation. **Resolved 2026-08-18, and the answer changes the design**: the API cannot tell us this at all (see `testReconciledTransactionDetection` below, now fully closed) — a risk tier keyed on "already reconciled" cannot be built from API data alone. Any future write-risk gating needs a different signal (e.g. warn generically before any write to a transaction inside a closed/reconciled period, once `VL-PERIOD-CLOSED-001`-style period data exists) rather than a per-transaction reconciled flag that doesn't exist.
- **Client Exception Packet** — grouped monthly version of the Client Question Builder
- `VL-CLOSED-PERIOD-DRIFT-001` — **changed-after-close detection.** Snapshot the closed period's trial balance at close; recompute on every sync; flag movement. Needs no audit log. **This is the finding that protects the bookkeeper** when a client says "these numbers changed."
- `VL-FORCED-RECON-001` / `VL-OBE-BALANCE-001` — forced reconciliation (Reconciliation Discrepancies balance) and Opening Balance Equity balance; both classic inherited-books signatures
- `VL-AUTOADD-RULE-001` — bank rules with auto-add enabled posting without review

## Spike items — status corrected 2026-08-16 (see §6's note)
- `testCategorizationProvenance` — is QBO's rule-vs-AI-vs-human categorization source exposed? **Run 2026-08-17, DISPROVEN.** Checked three surfaces (Purchase query, cdc, TransactionList columns), 12 candidate field names, none found. Matrix row 13.1. The cleanup-filter idea this was meant to enable (`CLEANUP_MODE.md` §2.7) has no API path — treat it as closed, not a live backlog item.
- `testReconciledTransactionDetection` — can the API tell us a transaction is reconciled? **Fully resolved 2026-08-18 — DISPROVEN for both cases.** Run 2026-08-17 against unreconciled data (three-surface check, 8 candidate names, none found; Matrix row 13.2). Wave 4 item 44 closed 2026-08-18: the owner performed a real, clean reconciliation in the sandbox UI (Savings account, $200 "Money to savings" deposit, statement difference $0.00, no adjustment — confirmed via the Reconciliation Report). Queried that exact transaction directly (`Deposit` Id 121) via `QboRawClient` — no `Reconciled` field, or anything resembling one, appears anywhere in the raw JSON. Same negative result as the unreconciled case. **The API genuinely does not expose reconciliation status, confirmed against real data in both states — this is now closed, not open.** See `backend/spike/checkReconciledStatus.ts`.
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
- ~~Can the API tell us a transaction is **reconciled**?~~ **Fully answered 2026-08-18: no, for both reconciled and unreconciled transactions.** Confirmed against a real cleanly-reconciled sandbox transaction (Wave 4 item 44, closed). See §16.
- Are **T1's fixtures rich enough** now that T2 is largely inert? Still correctly deferred — no golden fixture set exists yet in the on-disk sense (§14's note on inline-Swift-fixtures-as-substitute).
- ~~**New, from the slice build:** does a manually-voided `Purchase` actually show `TotalAmt == 0` (or some other signal) via the API?~~ **Answered 2026-08-17: no — it shows a top-level `status: "Voided"` field instead.** `TotalAmt == 0` was tried and disproven first (false-positived on a legitimate $0 fixture). Spike item 51 closed; Branch B's resolution path confirmed trustworthy against real data.

## Recommended sequence
1. ~~**Finish the vertical slice** (Branch B, fenced UI scope)~~ — **DONE, 2026-08-17.** Logic/sync/persistence/UI built and committed 2026-08-16; a real live-sandbox sync-and-evaluate pass ran 2026-08-17; the owner manually voided #151 the same day and Branch B's full resolution path was proven end-to-end against real data (spike item 51 closed); the owner then walked all three UI screens against that same live data and every one matched the design spec exactly. Nothing about Phase 1 step 1.6 is open anymore.
2. **Cleanup Assessment** — read-only, no writes, highest immediate business value; it prices engagements and doubles as a sales artifact
3. **Get the first client**
4. Reprioritize everything else against that client's actual books

**Deliberately not committed past step 2.** Half the backlog will matter more than expected and some of it won't matter at all, and no amount of planning will reveal which before real data does.

## "Ask My Accountant" account — checked against this sandbox, 2026-08-31

While scoping additions to the health report's "DATA HYGIENE" section (alongside the already-shipped `UncategorizedTransactionRule` coverage of Uncategorized Expense/Income/Asset), checked whether "Ask My Accountant" — a QBO default catch-all account on some company files — exists in this sandbox the same way. **It does not.** Queried the full chart of accounts live (`SELECT Id, Name, AccountType, AccountSubType, Active FROM Account MAXRESULTS 1000` via `QboRawClient`, `backend/spike/checkAskMyAccountant.ts`): 90 accounts total, zero matches for "accountant" anywhere in the name. This sandbox's chart of accounts is a Landscaping-industry template (`Decks and Patios`, `Sprinklers and Drip Systems`, etc.) and simply doesn't carry that account.

This is a **can't-verify-here** gap, not a **doesn't-exist** one — "Ask My Accountant" is a common default on many real QBO company files, so a future real client is likely to have it. `UncategorizedTransactionRule`'s exact-name-match mechanism would extend to it trivially (add the string to `uncategorizedAccountNames`), but per CLAUDE.md rule 6, that addition should wait until either (a) this sandbox has a real "Ask My Accountant" account + transaction to prove the match actually fires against live data (seedable via `spike/seed.ts`'s existing pattern, sandbox-only per rule 7), or (b) a real connected client's books have one. Not built yet — flagged here so the next session doesn't have to re-run this exact query to find out the same thing.

## Suspense-activity and stale-clearing-account rules for Balance Sheet Integrity — checked against this sandbox, 2026-09-11

While auditing Page 8 (Balance Sheet Integrity) against docs/VOICE_LEDGER_SPEC.md's named checks ("suspense activity, stale clearing accounts, undeposited-funds aging, loan inconsistencies"), found two real gaps already covered (see below) and two genuinely unbuilt: a suspense-activity rule and a stale-clearing-account rule. Checked whether this sandbox has any account that would let either be built and verified against real data, the same way `checkAskMyAccountant.ts` checked for that account. **It does not.** Queried the full chart of accounts live (`SELECT Id, Name, AccountType, AccountSubType, CurrentBalance, Active FROM Account MAXRESULTS 1000` via `QboRawClient`, `backend/spike/checkSuspenseAndClearingAccounts.ts`): 90 accounts total, zero matches for "suspense" or "clearing" anywhere in the name. Same Landscaping-industry chart of accounts as the Ask My Accountant finding, same reason.

This is a **can't-verify-here** gap, not a **doesn't-exist** one — same posture as Ask My Accountant. A real client's books are plausibly likely to have a suspense or clearing account (they're common bookkeeping-cleanup patterns), so build these rules when either (a) this sandbox is seeded with a real suspense/clearing account + a stale/aging balance to prove the detection actually fires (via `spike/seed.ts`'s pattern, sandbox-only per CLAUDE.md rule 7), or (b) a real connected client's books have one. Not built yet — flagged here so the next session doesn't re-run this exact query to learn the same thing.

**The other two gaps this same audit found were NOT missing rules, just a missing page-routing wire — fixed 2026-09-11, not deferred.** `VL-CLOSED-PERIOD-DRIFT-001` and `VL-BS-DRCR-001` were both already filed under `CleanupCategory`'s own `.balanceSheetIntegrity` grouping, fully built and tested, but `AppState.balanceSheetIntegrityRuleIDs` (Page 8's actual display filter) was a separate hand-typed literal that had drifted out of sync and never included them — so neither ever rendered on the dedicated page despite being categorized as belonging there. Fixed by deriving that property from `CleanupCategory.ruleIDs(in:)` instead of a literal, the same "one dictionary, not three independently-typed copies" fix `cleanupAssessmentRuleIDs` itself got on 2026-09-06 — this class of drift should now be structurally impossible for this particular property, not just less likely.

## Bank reconciliation status/history — no new investigation needed, already settled

Re-raised 2026-08-31 (a proposed "Opening Review" report wanted a "last reconciled date per account" field). **Already fully answered, twice, 2026-08-18 — not re-investigated, just re-confirmed from this file:** the Hard API Limits table (above) already lists "No reconciliation history, statement balances, or attached statement — Import or screenshot only" as VERIFIED, and the per-transaction question ("can the API tell us a transaction is reconciled?") was independently DISPROVEN against both a real reconciled and a real unreconciled sandbox transaction (`backend/spike/checkReconciledStatus.ts`, Wave 4 item 44). Both findings are the same underlying limit at two different grains (transaction-level and account-level) — neither a "last reconciled date" nor a "days since reconciled" field is fetchable from QBO's API for this app, period. Nothing about the newer proposal changes that; it's restated here only so a future session sees it's a closed question, not an open one.

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

---

## 2026-09-29 — Owner decisions on the "audit/cleanup/close engine" feature list, and QBO production checklist status

The owner supplied an external feature list (Tier 1–3: sanity checks, scope scorer, close checklist + workpapers, ReCat exporter, flux/KPI alerts, stale-feed sentinel) with the instruction "don't take away from the app we have already built." Four points conflicted with earlier decisions in this file; the owner decided each explicitly:

1. **Duplicates — middle ground, NOT fuzzy.** Add a lower-confidence near-duplicate tier: ±5-day window, payee names matched after normalization (case, punctuation, whitespace, Inc/LLC-style suffixes) — the same normalized-exact posture as `VL-DUP-VEND-001`. **True typo-tolerant fuzzy matching remains rejected** (false-positive risk). Existing exact duplicate rules are unchanged.
2. **Ask My Accountant / suspense / clearing accounts — seed the SANDBOX to prove them first** (rule 6), then build. Never production.
3. **Multi-month history — build real multi-month loading** so the scope score, 90-day uncleared items, and 3-month trailing flux use real data, not the single fixed period.
4. **Realm IDs encrypted at rest in the backend** (Intuit assessment item). Done: `backend/src/auth/realmCipher.ts` — AES-256-GCM ciphertext + keyed-HMAC `realm_key` lookup; one-time in-place migration `migrateRealmEncryption` (live DB migrated 2026-09-29, backup in `backend/data/backups/`). Desktop per-client folders deliberately still use plain realm IDs (owner chose backend-only). Backend log lines still carry realmId.

**QBO production checklist status (2026-09-29):** token rotation persisted on every refresh ✓ · refresh tokens AND realm IDs encrypted at rest ✓ · 429 exponential backoff honoring Retry-After + 10-concurrent-per-realm cap in `QBOClient.send` ✓ · realmId partitioning ✓ (pre-existing) · SyncToken checked on the one write ✓ (pre-existing) · in-app Disconnect: `POST /realms/:realmId/disconnect` revokes at Intuit, deletes tokens + sessions; Connection page button also deletes the local client store ✓ (not clicked live — would revoke the only sandbox connection).
