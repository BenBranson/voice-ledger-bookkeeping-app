---
title: "Voice Ledger — Bookkeeper Command Center"
subtitle: "Complete Design Spec, v9 — Native Swift Build"
author: "Benjamin Branson Bookkeeping"
date: "August 2026"
---

# Operating Model

**Voice Ledger runs on one monitor. QuickBooks Online runs on the other. You work between them.**

This is the organizing principle of the whole app, and it changes what "the API can't do that" means. It's no longer a blocker — it's a defined handoff. The app never has to pretend it can do everything inside itself. What it must do is make sure **no step in your monthly client process is ever forgotten, unguided, or unrecorded**, whether the app performs it, prepares it, or hands it to you.

Three consequences that shape every design decision below:

1. **Every step in your process gets a page** — including steps the app cannot perform at all. A page whose only job is to tell you what to do in QBO, give you a checklist, and record that you did it is still a page worth having. Missing steps is the real risk for a new bookkeeper; an incomplete-but-honest page beats no page.
2. **Where the API can't reach, Universal Ingestion fills the gap.** If QBO's UI can export it — or even just display it on screen — Voice Ledger can ingest and analyze it: CSV, Excel, OFX/QFX, PDF, or a screenshot. This converts most "unavailable" items into "available with one download or one screen capture."
3. **Every page ends with an Ask Claude panel** — because options and recommendations sometimes still leave you unsure, and the moment of uncertainty is exactly when you need to be able to ask a question rather than guess.

## Guiding constraints

1. **QBO API + your own file imports are the only accounting data sources.** No third-party bookkeeping SaaS, no bank-data brokers. Document OCR runs on-device by default.
2. **Voice runs on open-source Whisper, locally.**
3. **Code detects and classifies. Claude explains.** Every finding, flag, and dollar figure comes from deterministic rules. Claude explains, drafts, and advises — it never decides what counts as a problem and never calculates an authoritative number.
4. **Detect, draft, review, push.** Nothing modifies a real QuickBooks file without explicit human review.
5. **No claim of automation without sandbox proof.** No feature is labeled "Automatic" because a similarly-named API field exists.

---

# Three Page Types

Every one of the 12 workflow pages is one of these. The type is stated on the page itself, so you always know what you're looking at.

## Type A — API-Driven
Voice Ledger pulls the data, runs the rules, presents findings, stages corrections, and (with approval) writes back to QBO. *Example: duplicate posted-expense detection.*

## Type B — Import-Driven
The API can't reach the data, but QBO (or your client's bank) can export it. You download the file, drop it into the page, and Voice Ledger analyzes it exactly as if it had API access. *Example: reconciliation against an imported bank statement.*

Every Type B page shows: precisely where in QBO to get the file, which format to choose, what the app will do with it once ingested, and when it was last imported (with a staleness warning if the file predates the period being worked).

## Type C — Guided Manual
The app cannot do the work, and cannot get the data. What it *can* do is tell you exactly what to do, in what order, what to watch out for, what "done" looks like — and then record your confirmation that it's complete, with any notes, so the close package and activity log stay whole. *Example: setting the official QBO closing date.*

A Type C page is not a failure. It's the difference between a checklist that covers your whole process and one with silent holes in it.

---

# Universal Ingestion

A first-class subsystem — it's what makes Type B pages work, and it's what converts most API gaps into solvable problems. **If you can get it out of QBO in any form, the app can use it.**

## What it accepts

| Format | Handling |
|---|---|
| CSV, OFX, QFX | Deterministic parser — no AI involved |
| Excel (.xlsx, .xls) | Deterministic parser |
| PDF (text-layer) | Direct text extraction, then structure parsing |
| PDF (scanned/image) | On-device OCR, then structure parsing |
| Screenshots (PNG, JPEG, HEIC, TIFF) | On-device OCR, then structure parsing |

Screenshots matter more than they first appear: plenty of QBO screens have no export button at all, and a screenshot is the only way to get that data out. Reconciliation history, Books Review findings, bank-feed suggestions, the For Review queue — all API-unavailable, all screenshot-able.

## The three-tier extraction pipeline

**Tier 1 — Deterministic parsers (CSV, OFX, QFX, Excel).** No AI. Column mapping with a confirm-and-correct step, never a silent guess. The preferred path whenever a real export exists.

**Tier 2 — Apple Vision on-device OCR (PDFs, screenshots).** macOS's Vision framework does text recognition on the Neural Engine, understands document layout (tables, columns, headers, reading order), and handles handwriting reasonably well. Two properties make it the right default: it's free, and **the document never leaves your Mac** — preserving the privacy advantage of the import path. macOS 15+ `RecognizeDocumentsRequest` returns structured document data rather than a flat line dump.

**Tier 3 — Claude vision (escalation only).** For documents Tier 2 can't structure confidently: unusual layouts, ambiguous column semantics, messy handwriting, or cases where understanding *what a field means* takes judgment rather than just reading it. **This tier sends the document off-device**, so it requires explicit per-file consent and the UI must say so plainly rather than escalating silently. Claude's job here is structuring what was read — "this column is transaction dates, this one is amounts, negatives are debits" — not deciding what the numbers mean for the books.

## Extraction is not computation — the guardrail

This is the one place the "code computes, Claude explains" rule needs a careful extension. Extraction isn't calculation, but **a misread number becomes an authoritative number** the moment it enters the rules engine. A `$486.20` OCR'd as `$48.620` propagates silently into every downstream finding.

So every extracted field carries an `extraction_confidence` score and a link back to its source region in the original document, and:

- **Extracted financial data is never auto-approved into a finding that leads to a QBO write.** It goes to a verification step first.
- The verification screen shows the extracted table **side by side with the source image**, so you check against the original rather than trusting a transcription.
- Low-confidence fields are highlighted for attention rather than buried among correct ones.
- Any field you correct becomes a mapping hint for that document type from that source — the same layout shouldn't need the same correction every month.

## Cross-foot validation — the deterministic quality check

Financial documents have internal arithmetic, which means extraction quality can be verified *deterministically* rather than by trusting a confidence score:

- Do the extracted line items sum to the extracted subtotals and ending balance?
- Does beginning balance + credits − debits = ending balance?
- Does the extracted transaction count match a stated count, where the document gives one?
- Do all dates fall inside the stated statement period?

**If a document fails cross-foot, extraction is flagged unreliable and the page cannot go green on it.** This is a far stronger guarantee than an OCR confidence score and costs nothing but arithmetic. Every ingested financial document should be cross-footed before its data is allowed to produce findings.

## Screenshots carry a specific risk worth naming

A screenshot is by nature **partial** — it captures one scroll position of a longer list. A screenshot of the first 20 rows of a 340-row reconciliation report looks complete and isn't.

Screenshot-sourced data therefore defaults to **coverage: partial** unless the document states a total the extracted rows reconcile against. A page fed only by screenshots shows *"Coverage incomplete — screenshot source"*, never green. Multi-screenshot stitching (several captures of one scrolling list) is supported, with overlap detection to catch both gaps and double-counted rows.

## Common sources and what they unlock

| Source | Typical format | Fills the gap for |
|---|---|---|
| Bank / credit-card statements | CSV, OFX, QFX, PDF | Bank feed review, reconciliation |
| QBO Audit Log export | CSV *or* PDF — accepts either | Who-changed-what history the API can't provide |
| Any QBO report | Excel, CSV, PDF | Cross-checks, historical comparison |
| Reconciliation history / reports | PDF, screenshot | Reconciliation history the API won't return |
| Books Review findings | Screenshot | QBO's own flags, otherwise API-invisible |
| For Review queue | Screenshot | The bank-feed queue, otherwise API-invisible |
| Bank rules export | QBO's own format | Rule review, bad-rule damage tracing |
| Chart of accounts | Excel, CSV | COA cleanup, duplicate-account detection |
| Customer / vendor lists | Excel, CSV | Duplicate vendor detection |
| Prior-period workpapers | CSV, Excel, PDF | Opening balance verification |

*Note: QBO's main "Export Data" function silently omits the audit log, attachments, recurring templates, and bank rules — each needs its own export from its own screen. Sources disagree on whether the audit log exports as CSV or PDF-only, which is exactly why the ingestion layer accepts both and doesn't care.*

## After extraction

However data arrived — API, deterministic parse, on-device OCR, or Claude vision — it normalizes into **the same internal shape**, so `/core` rules run identically regardless of source. That single decision is what keeps Type B pages from becoming a parallel codebase.

Every finding carries its provenance: `source: QBO API, synced [timestamp]` · `source: imported file, [filename], [date], extraction: deterministic` · `source: screenshot, [filename], [date], extraction: on-device OCR, coverage: partial`. When you're deciding how much to trust a finding, where its data came from is part of the answer.

---

# The Ask Claude Panel

At the bottom of every page, below options and recommendations.

**Context it receives automatically:** the current client and period, that page's findings and their evidence, what data source fed them (API or import), what's already been resolved, and the page's own subject matter. You should never have to re-explain the situation to ask a question about it.

**What it's for:** "Why is option 2 safer than option 1 here?" · "What happens to the reconciliation if I void this instead of deleting it?" · "I don't understand why this is flagged as medium confidence." · "What would a more experienced bookkeeper check before approving this?"

**Guardrails, non-negotiable:**
- The chat can read the page's data and explain it. **It cannot execute writes, approve findings, or change state** — it's an advisor, not a second control surface.
- Answers are visibly labeled as guidance, not authoritative accounting determinations.
- If a question asks for a number, Claude cites the deterministic value the rules engine already computed rather than calculating its own.
- Conversations are saved to the client-period record — the questions you asked while closing a month are part of the workpaper, and re-reading them later is genuinely useful when the same situation recurs.

**Model strategy:** use **Claude Opus 5** for the Ask Claude panel and for complex multi-finding explanations, where judgment quality matters most. Routine per-finding narration (a one-line plain-English restatement of an already-decided finding) can run on a cheaper, faster model — that's the highest-volume, lowest-judgment call in the app, and paying Opus rates for it is waste. Make the model per-task configurable rather than hardcoded.

---

# Architecture

## Security: a thin backend is required

Intuit's OAuth is designed around a server-side exchange; embedding a permanent QBO client secret or Claude API key in a distributed desktop binary makes them extractable. One small backend, owned by you, that: stores refresh tokens encrypted · issues authenticated app sessions · exchanges and refreshes OAuth tokens · proxies and tightly authorizes QBO writes (the desktop client should never invoke arbitrary QBO endpoints) · enforces which entity operations are permitted · rate-limits · logs access with financial payloads and tokens excluded · sends Claude only approved, minimized fact packets.

Stated precisely: **the backend does not persist accounting payloads, but QBO and Claude requests transit it, and it may process selected data in memory while proxying authorized requests.** That's the honest version — "never touches accounting data" would be false.

Imported files stay **local to the desktop app** and never transit the backend — including OCR, which runs on-device via Apple's Vision framework. The one exception is Tier 3 Claude vision escalation, which requires explicit per-file consent precisely because it breaks that property (see Universal Ingestion).

## QBO has no read-only mode — the app enforces it

There is one accounting scope (`com.intuit.quickbooks.accounting`) and it grants read *and* write together. Self-enforcement is therefore the entire safety story:

- Every new client connection starts in **Voice Ledger Read-Only Mode**
- Write endpoints stay disabled until explicitly enabled per client; can be re-disabled without disconnecting
- Every proposed write is staged locally first; the entity is freshly re-read immediately before writing
- The current `SyncToken` must match the staged version or the write is rejected
- Every write carries an idempotency record; a timed-out POST is never blindly retried
- Closed-period writes are blocked client-side before reaching QBO
- Production and sandbox connections are visually unmistakable from each other

## Core layers

```
/core            platform-agnostic logic: metrics, rules engine, finding
                  detection, severity/confidence classification
/integrations
  /quickbooks     QBO API calls (via the thin backend), normalization
  /imports        parsers, on-device OCR, extraction verification →
                  the same normalized shape as API data
  /xero           (future) same contract, different adapter
/staging          local, diffable record of every proposed correction
/voice            whisper.cpp, local intent parser, optional LLM fallback
/db               findings, activity log, imports, dismissal/memory rules
/ui               SwiftUI screens
```

`/core` never imports from `/integrations` directly. Critically, **API data and imported-file data normalize into the same shape**, so a rule written once works on either — that's what makes Type B pages cheap to build rather than a parallel codebase.

## Multi-client reality

No documented endpoint returns an accountant's full QBOA client list. The Firm Cockpit shows **Voice Ledger's own connected-company registry**: connect each client company individually through Intuit's authorization screen, verify via CompanyInfo, record the `realmId` locally, repeat. Page 1 accordingly confirms the company name, `realmId`, and connection health — and separately asks *you* to attest that proper QBOA access exists, since the API can't verify that.

## Sync architecture

Webhook signals a change → CDC fetches only changed entities → local normalized data updates → only dependent rules rerun → reports refresh only when a relevant ledger change affects them → full validation scan at close → periodic checksum catches missed events. CDC only looks back 30 days, so it isn't a permanent history feed. Intuit is migrating webhooks toward CloudEvents — build for that, not just the legacy envelope.

Most read operations are metered "CorePlus" calls under Intuit's usage-based pricing, with a large free monthly allowance. Cache locally, use CDC over full syncs, paginate (~1,000 records/page cap), batch carefully (30 payloads max), exponential backoff on 429s.

---

# Universal Finding Record

```
Finding
  client_id                   accounting_period
  rule_id + rule_version       title / category
  severity                    confidence
  dollar_exposure              affected_transactions
  evidence                    explanation
  recommended_actions          risk_if_ignored
  detection_capability          automatic | assisted | import_required | unavailable
  resolution_capability         automatic_api | staged_api | manual_qbo | unsupported
  data_source                  qbo_api | imported_file | screenshot | manual_entry
  extraction_method             none | deterministic | ocr_local | claude_vision
  extraction_confidence         coverage (complete | partial)
  source_file / import_date     cross_foot_result
  status                       assigned_to
  client_question              resolution
  resolved_by / resolved_at
  qbo_before_snapshot          qbo_after_snapshot
```

Detection and resolution are **separate axes** — finding a problem and being able to fix it via API are different questions:

| Example | Detection | Resolution |
|---|---|---|
| Duplicate posted expense | automatic | staged_api |
| Unmatched bank-feed line | import_required | manual_qbo |
| Account merge candidate | automatic | manual_qbo |

## Color, severity, confidence, status

**Green must never mean merely "no problem was detected."** Green means: required data was available, the check completed, the result is current, and no exception was found. Otherwise missing data produces a falsely reassuring green screen — the worst failure mode this app could have.

| Color + Icon | Meaning |
|---|---|
| Green + checkmark | Checked and passed |
| Yellow + magnifier | Human review needed |
| Red + alert triangle | Urgent or material risk |
| Blue + info icon | Recommendation or opportunity |
| Purple + speech bubble | Waiting on client |
| Gray + clock | Not checked, stale, or unavailable |
| **Outlined gray** | **Requires import or manual QBO step — not yet actionable** |

Severity (how damaging), confidence (how sure), and status (what's happening now) stay three separate axes.

---

# Every Page's Structure

1. **Page type badge** — API-Driven / Import-Driven / Guided Manual
2. What was checked · what passed · what needs review
3. Why each item was flagged, with evidence
4. Recommended solutions and the consequences of each
5. Approve / edit / dismiss / ask the client
6. **For Type B:** import status and the "get this file from QBO here" instructions
7. **For Type C:** the step-by-step QBO procedure, pitfalls, and done-criteria
8. Re-run checks · mark section complete
9. **Ask Claude panel**

Sections cannot be marked complete on missing data — a Type B page with no import shows *"Coverage incomplete"*, not green.

## Sample finding

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

---

# Connection Pages

Two dedicated pages, outside the 12-page client workflow, because connection health is a precondition for everything else. Both use the same color semantics as the rest of the app: **green means verified working right now — not merely "configured."** A saved API key that hasn't been successfully used is gray, not green.

## QuickBooks Online Connection

Because QBO authorization is per-company, this page lists every connected client company with its own status row.

**Per-company status:**

| State | Meaning |
|---|---|
| **Green** | Connected, token valid, last health check succeeded |
| **Yellow** | Connected but degraded — refresh token nearing expiry, sync stale, or rate-limited |
| **Red** | Auth failed, token revoked, or health check failing |
| **Gray** | Not connected / never authorized |

**Each row shows:** company legal and display name · `realmId` · **environment badge (SANDBOX / PRODUCTION — visually unmistakable, different background treatment, not just a text label)** · access-mode state (Read-Only Mode vs. Write-Enabled) · last successful sync · last health check · token expiry countdown.

**Token lifecycle, surfaced proactively:** QBO access tokens expire after ~1 hour (refreshed silently), but **refresh tokens expire after ~100 days**. A client you haven't opened in over three months will need full re-authorization. The page should warn well before that deadline rather than surfacing it as a failure the morning you sit down to close their books — a countdown at 30 days out, escalating to yellow at 14.

**Actions:** connect a new company (launches Intuit's authorization flow) · run health check (non-destructive CompanyInfo read) · re-authorize · toggle Write-Enabled for this client · disconnect.

**Health check must be a real request, not a cached assumption.** Green requires a successful live call, timestamped. A token that looks structurally valid but was revoked on Intuit's side is exactly the failure this page exists to catch.

## Claude API Connection

One app-level connection, unlike QBO's per-company model.

**Status:** green when a live test call succeeded · yellow when rate-limited or responding slowly · red on auth failure · gray when unconfigured or intentionally disabled.

**Shows:** connection state and last successful call · **model assignment per task** (Ask Claude panel · finding narration · report commentary · document extraction escalation) · usage and spend tracking, ideally per client so the cost of a close is attributable · current rate-limit state.

**The API key is held in the thin backend and never displayed in the desktop app** — the page shows whether a key is configured and working, not the key itself.

**Kill switch:** a single toggle that disables all AI features app-wide. Every deterministic rule, every finding, every calculation, and every report still works with it off — that's the design guarantee from constraint #3, and this toggle is what proves it's real rather than aspirational. Worth testing regularly for exactly that reason.

## Global connection status

Both connections surface as persistent indicators in the app's status bar, alongside the pinned active company and period. Discovering a dead connection mid-close, three pages deep, is a bad experience — and worse, a stale-data risk if a page renders findings from a sync that silently stopped working.

**No workflow page may render green while the connection that fed it is red.** A page's status can never be better than the health of the data behind it.

---

# The 12-Page Workflow

Each page below states its type, what the app does, and where you take over.

## 1. Access & Evidence Pack — *Type A + C*
**App:** reads CompanyInfo, accounts, and baseline reports; verifies company identity and `realmId`; generates the Baseline Evidence Pack. **You:** attest QBOA accountant access (unverifiable via API). **Note:** the export is evidence of the starting state, not a restorable backup — hence the name.

## 2. Scope & Period Lock — *Type A + C*
**App:** stores engagement scope; reads QBO's `BookCloseDate` from Preferences where available; enforces its own stricter lock; warns on transactions dated in closed periods; catches QBO error codes 6200/6210. **You:** set the official QBO closing date, and confirm filing status — neither is API-settable or API-verifiable.

## 3. File Health Scan — *Type A*
**App:** analyzes accounts, posted transactions, balance sheet, P&L, trial balance, general ledger, transaction reports. **Cannot:** call QBO's own Books Review or import its findings — no API entity exists for Books Review, Books Close, Transaction Review anomalies, or close progress. Named **Voice Ledger Health Scan**, modeled on the same checks, not claiming to be QBO's tool.

## 4. Bank Feed Cleanup — *Type B*
**App:** analyzes posted QBO activity and compares it against your imported CSV/OFX/QFX statement; detects duplicates and missing postings. **Cannot:** see the "For Review" queue, QBO's suggested matches or categories, bank rules, excluded items, or QBO's confidence — none of it is API-exposed (and no paid provider is required; that's optional, not mandatory).

**Safety rule:** if the statement shows a $500 expense missing from posted QBO activity, the app *could* create that Purchase via API — but if the same item later appears in the bank feed, it may sit unmatched or get added twice. Missing statement items default to **import-required detection → manual QBO bank-feed action**, never silent creation.

## 5. Reconciliation — *Type B + C*
**App:** compares imported statement lines against the posted ledger; identifies unmatched and duplicate items; inspects some cleared/uncleared activity via TransactionList. **Cannot:** obtain statement ending/beginning balance, reconciliation completion date, saved history, the attached statement, or execute Finish/Undo Reconciliation.

**Two honest states:**
- *No statement imported:* "Coverage incomplete. Import a statement or complete reconciliation in QBO."
- *Statement imported:* "Compared 114 statement lines against 111 posted transactions. Two items missing, one probable duplicate, calculated difference $486.20. Resolve these, then complete reconciliation in QBO."

**Never turns green without statement evidence or explicit confirmation that you completed it in QBO.**

## 6. Chart of Accounts Cleanup — *Type A + C*
**App:** reads, creates, renames, edits, deactivates accounts; detects duplicate-account candidates; prepares a merge plan and preserves reconciliation reports first. **You:** perform the merge in QBO. Merges are permanent, can silently lose reconciliation history, require matching account/detail types, and cannot be undone — this stays manual on purpose, not because of an API gap.

## 7. Batch Fixes — *Type A*
**App:** updates supported entities directly (`AccountRef`, `ClassRef`, `DepartmentRef`, vendor, line detail) with sparse updates and small batches. **Cannot:** invoke QBOA's actual Reclassify Transactions tool — no API equivalent exists; it remains a manual alternative you may prefer for large jobs.

**Before any batch runs, the preview shows:** transactions affected · total dollars · old and new category · tax-period consequences · before/after report impact · reversal plan.

**Constraints:** `Id` + `SyncToken` required per update; stale tokens fail; sparse updates aren't universal; full updates can clear omitted fields; linked transactions complicate edits; closed periods reject writes; payroll entries usually need Payroll APIs or manual correction; hard deletes are permanent.

## 8. Balance Sheet Integrity — *Type A*
**Strongest API coverage.** Balance Sheet, Trial Balance, General Ledger, Account List, Transaction List, journal entries, bills/payments/deposits/purchases/transfers, attachments. Reliably computes negative asset/liability balances, suspense activity, stale clearing accounts, undeposited-funds aging, loan inconsistencies, equity postings needing review, unexpected balance changes, and debit/credit patterns that don't fit account expectations. Journal entries are supported but Intuit recommends using them sparingly — prefer the native transaction type where practical.

## 9. Sales Tax Review — *Type A + C, skippable per client*
**App:** reads tax codes, rates, agencies, taxable treatment, transaction-level detail, liability balances. **You:** confirm filing jurisdiction, frequency, return period, whether return and payment were submitted, Tax Center adjustments, and outstanding notices — none of which the public API confirms.

## 10. Taxes — *Type A*
**App:** locally estimates trends and possible exposure from QBO financial data. **Cannot:** determine actual liability, deductions, basis, outside income, or filed-return status. Always labeled an estimate, never filing guidance.

## 11. Month-End Close — *Type A + C*
**App:** maintains the checklist, dependencies, approvals, and carry-forward items; reads the QBO close date where available; runs a full validation scan. **You:** set the official QBO closing date and complete QBO's Books Close. Year-end mode adds: no unsupported adjusting entries.

## 12. Reporting — *Type A*
**App:** P&L, balance sheet, cash flow, general ledger, trial balance, transaction and aging reports; generates the branded client PDF and the Close Package. Report responses need normalization and won't be pixel-identical to QBO's rendered reports.

**Dependency-aware staleness runs across all pages:** change an upstream transaction after a later page was completed, and everything downstream is automatically marked for revalidation rather than holding a false checkmark.

---

# Features Beyond the Workflow

**Firm Cockpit** — every connected client on one screen: period, close readiness %, urgent findings, client-blocked items, reconciliation status, pending imports, last sync, deadlines. **Next Best Action** — the app says where to start. **Client Memory, With Approval** — learns categories and patterns, but never silently: *"Always categorize future Odessa Water transactions as Utilities?"* **Client Question Builder** — turns an uncertain finding into a ready-to-send client question, answer attached permanently to the finding. **Close Package** — reports, variance, warnings, completed checklist, corrections made, carry-forward items, client Q&A, Ask Claude history, and who closed it when. **Training Mode** — every flag answers "why was this flagged?" with the underlying accounting principle, not just the rule. **Voice Guardrails** — voice navigates, filters, searches, reads, and drafts, but never finalizes a QBO write without visible on-screen confirmation. **Wrong-Client Protection** — active company and period pinned to every screen; all data, queues, caches, and logs segregated by `realmId`.

## Voice Ledger Activity & Correction Log
Not "Audit Log" — QBO's real audit log has no API access at all. **Can prove:** what Voice Ledger detected, proposed, and submitted; what you approved; QBO's response; before/after entity snapshots; which user initiated it; every file you imported and when. **Cannot prove:** who changed something directly in QBO outside the app, or history predating the connection. *(An imported QBO Audit Log export — CSV or PDF — partially closes that gap, which is much of why Universal Ingestion matters.)*

---

# Rules Engine vs. Claude

**Deterministic code:** calculates amounts, detects duplicates, determines materiality, compares periods, identifies abnormal balances, calculates ratios, assesses available reconciliation coverage, ranks risk, decides pass/fail.

**Claude:** explains findings in plain English, describes possible causes, explains proposed choices and their consequences, drafts client questions, writes report commentary, answers Ask Claude questions, converts accounting language to owner-friendly language.

Claude receives compact pre-selected facts — never a raw company-file dump. Schema-controlled JSON for structured output, versioned prompts, all output visibly labeled as draft or guidance.

---

# Build Order

1. **Capability spike** — sandbox-verify every endpoint before designing against it
2. **Authentication & client isolation** — OAuth via thin backend, per-company authorization, sandbox/production separation, Read-Only Mode default. Build both Connection Pages here, not later: they are how you diagnose everything that follows
3. **Read-only sync** — accounts, vendors, transactions, reports; pagination; CDC
4. **Universal Ingestion** — early, deliberately: it unblocks pages 4 and 5, the two most limited by the API, and proves the normalization contract holds across every source. Build in tier order — deterministic parsers, then on-device OCR, then Claude vision escalation — and build cross-foot validation alongside tier 1, not after tier 3
5. **One complete vertical slice** — duplicate detection end to end: evidence → explanation → solution → approval → sandbox write → activity log
6. **Universal findings inbox**
7. **Ask Claude panel** — once one page has real findings to ask about
8. **Period workflow engine** — dependencies, completion criteria, staleness
9. **File health and balance-sheet rules**
10. **Reporting and close package**
11. **Remaining correction workflows and Type C guided pages**
12. **Voice layer last**, so a voice bug never blocks anything else

## Capability Spike checklist — per feature, before UI work

QBO entity or report endpoint · read verified in sandbox · write verified in sandbox · required minor version · required subscription/locale · pagination behavior · CDC support · webhook support · sparse vs. full update behavior · `SyncToken` behavior · closed-period behavior · delete/void/reversal behavior · required manual QBO step · **available UI export or screen-capture fallback** · sandbox request · sanitized response · test fixture · detection + resolution classification · last verification date.

**No feature is labeled "Automatic" on the strength of a similarly-named field or SDK class existing.**

---

# Explicitly Out of Scope

- **Full AR/AP workflows** — not part of the services offered
- **Payroll, inventory, multicurrency, custom fields, sales-form configuration** — one-time QBO admin tasks, not recurring monthly work
- **A separate "Stop & Ask Client" subsystem** — client-blocked items are a tagged finding

---

# Reference Findings Library

Detection categories for the rules engine, mapped mainly to pages 3, 4, and 8: duplicate expenses, bills, invoices, and payments · bank/credit-card reconciliation differences · uncategorized or miscoded transactions · unusual vendor names, amounts, or timing · negative balances and abnormal clearing accounts · recurring subscriptions that increased or appear unused · late fees, overdraft fees, and avoidable interest · vendor price increases and possible duplicate services · possible personal expenses or owner draws in business accounts.
