# 9. Ingestion Pipeline Design

Three tiers, cross-foot validation, the extraction verification UI, and how
provenance tracks through to findings.

Scheduled early in the Build Order (§4) on purpose: it unblocks Pages 4 and 5 —
the two most limited by the API — and it proves the normalization contract (§4.1)
holds across every source. If normalization only ever sees API data, we won't
find out it's leaky until the first import.

**Tier 1 (CSV) — IMPLEMENTED 2026-08-17**, `desktop/Sources/Integrations/Imports/`
(`CSVParser.swift`, `BankStatementCSVImporter.swift`) plus the Core types this
section specifies (`ImportedDocument`, `ColumnMapping`/`MappedField`/
`MappingOrigin`, `NormalizationDefect`) — a new `QBOEntityKind
.importedBankStatementLine` case lets an imported line normalize into the same
`LedgerTransaction` shape the QBO API path produces (§9.8's contract, proven
against a second real source for the first time). 15 new tests
(`Tests/IntegrationsImportsTests/`), all offline — deterministic CSV parsing
needs no live sandbox.

**The confirm-and-correct UI (§9.4) is now real too**, wired end-to-end the
same day: `ImportBankStatementView` (a `Picker` per CSV column, every column
defaulting to `.unmapped` — never a pre-selected guess), `.fileImporter` on
`BankFeedCleanupView`, and `ClientStore.upsertImportedStatementLines`/
`loadImportedStatementLines` so an imported statement survives an app
relaunch and is re-merged into every subsequent `syncAndEvaluate()`, not just
evaluated once at import time. `VL-RECON-MISSING-001` can now actually fire
against a real imported file, not just prove its own logic in isolation.
**OFX/QFX also implemented, same day** (`OFXParser.swift`,
`OFXBankStatementImporter.swift`) — the spec's own "highest-fidelity source
available for bank data." Targets OFX 1.x's SGML-style format (most banks
still export this, not true XML) — leaf tags frequently have no closing tag
at all (`<TRNAMT>-486.20`, newline as the only terminator), which a strict
XML parser would reject outright; this parser tolerates both forms. No
column-mapping confirm step needed (tags are self-describing) and no date
ambiguity (`YYYYMMDD` is unambiguous) — `ImportOFXStatementView` only asks
which QBO account the statement is for. OFX's own `FITID` is used as the
produced `LedgerTransaction.id` when present, a better identity than the CSV
importer's synthesized `doc-rowN`.

**A real correctness gap was caught and fixed the same day**: the CSV
import UI (previous day's commit) never actually passed `statementAccountID`
through — every imported line got `paymentAccountID: nil`, which can never
equal a posted transaction's real account ID, so `VL-RECON-MISSING-001`
would have silently flagged every import as "missing" regardless of truth.
Fixed by adding an account-selection step to both confirm screens
(`AppState.accounts`, populated from the last sync) — required before
Import is enabled, never inferred or defaulted.

**Still not built:** cross-foot validation (§9.5 — needs a stated statement
total/ending balance neither importer accepts as input yet), learned-mapping
persistence (stage 6), Excel within Tier 1, and Tier 2 (on-device Vision) /
Tier 3 (Claude vision) entirely.

---

## 9.1 Pipeline stages

```
  File dropped
      │
  ┌───▼──────────────┐
  │ 0. Classify      │  format, document kind, source hint, content hash
  └───┬──────────────┘
      │
  ┌───▼──────────────┐
  │ 1. Extract       │  Tier 1 parser │ Tier 2 Vision │ Tier 3 Claude (consented)
  └───┬──────────────┘
      │  RawExtraction: cells + per-field confidence + source regions
  ┌───▼──────────────┐
  │ 2. Map columns   │  confirm-and-correct — NEVER a silent guess
  └───┬──────────────┘
      │
  ┌───▼──────────────┐
  │ 3. Cross-foot    │  deterministic arithmetic. Gate, not advisory.
  └───┬──────────────┘
      │
  ┌───▼──────────────┐
  │ 4. Verify (human)│  side-by-side with source image; low confidence highlighted
  └───┬──────────────┘
      │
  ┌───▼──────────────┐
  │ 5. Normalize     │  → §4's shape, with Provenance attached
  └───┬──────────────┘
      │
  ┌───▼──────────────┐
  │ 6. Learn mapping │  corrections become hints for this doc type + source
  └──────────────────┘
```

**Stage 3 gates stage 5.** A document that fails cross-foot does not reach
normalization as trustworthy data. Per spec: *if a document fails cross-foot,
extraction is flagged unreliable and the page cannot go green on it.*

**Stage 4 is mandatory for any document that will feed a finding leading to a QBO
write** (`CLAUDE.md` rule 8). Not configurable, not skippable.

---

## 9.2 Stage 0 — classification

```swift
struct ImportedDocument: Identifiable, Sendable {
    let id: ImportedDocumentID
    let realmID: RealmID
    let filename: String
    let contentHash: Digest        // identity — reimporting the same file is detected
    let format: DocumentFormat
    let declaredKind: DocumentKind // you state what it is; we don't guess
    let importedAt: Date
    let importedBy: String
    let storageURL: URL            // inside the client's directory (§7.1)
}

enum DocumentFormat: Sendable {
    case csv, ofx, qfx, excel
    case pdfWithTextLayer, pdfScanned
    case image(ImageFormat)        // png, jpeg, heic, tiff
}

enum DocumentKind: String, Codable, Sendable {
    case bankStatement, creditCardStatement
    case qboAuditLogExport, qboReport, reconciliationReport
    case booksReviewScreenshot, forReviewQueueScreenshot
    case bankRulesExport, chartOfAccounts, vendorList, customerList
    case priorPeriodWorkpaper, other
}
```

**`declaredKind` is stated by you, not inferred.** Format detection is
deterministic and safe; *semantic* kind detection is a guess, and a bank statement
misclassified as a reconciliation report produces confidently wrong findings. The
UI can suggest a kind from filename and content, but you confirm it. Type B pages
already know what they need ("import your bank statement here"), so in practice
the kind is usually pre-selected by context.

**`contentHash` gives idempotent import.** Dropping the same file twice is
recognized, not duplicated. Dropping a *different* file for the same
account+period is `importSuperseded` (§6.4) and invalidates dependent pages.

---

## 9.3 Stage 1 — the three tiers

### Tier 1 — deterministic parsers · CSV, OFX, QFX, Excel
No AI. The preferred path whenever a real export exists.

- OFX/QFX are structured and largely self-describing: account, date, amount,
  type, FITID. Highest-fidelity source available for bank data.
- CSV and Excel need column mapping (stage 2).
- `extractionConfidence` is `nil` — not 1.0. A deterministic parse either
  succeeded or produced a `NormalizationDefect`; a confidence score would imply a
  probabilistic process that didn't happen.
- **Date format ambiguity is a defect, not a guess.** `03/04/2026` is
  unresolvable without evidence. The parser looks for a disambiguating row (a day
  > 12); absent one, it raises `DefectKind.ambiguousDateFormat` and asks. Silently
  choosing US format is how transactions land in the wrong month.

### Tier 2 — Apple Vision, on-device · PDFs and screenshots
The default for anything without a text layer. Two properties make it right:
it's free, and **the document never leaves your Mac** (spec).

- macOS 15+ `RecognizeDocumentsRequest` returns structured document data —
  tables, columns, headers, reading order — rather than a flat line dump. Table
  structure is what makes financial documents extractable at all; a flat line
  dump of a statement loses column association, which is the whole content.
- Per-field confidence and bounding boxes are captured and retained as
  `SourceRegion` (§4.8) — required for the side-by-side verification UI, and not
  recoverable later if not captured now.
- **macOS version dependency is a real constraint.** If we must support macOS 14,
  the fallback is `VNRecognizeTextRequest` plus our own column-clustering from
  bounding boxes — noticeably worse on tables. *Open question for you: what is
  the minimum macOS version?* (`OPEN_QUESTIONS.md` Q4.)

### Tier 3 — Claude vision · escalation only
For documents Tier 2 cannot structure confidently: unusual layouts, ambiguous
column semantics, messy handwriting, or where understanding *what a field means*
takes judgment (spec).

**This tier sends the document off-device.** Requirements, all non-negotiable:

1. **Explicit per-file consent.** Not a global setting, not a remembered
   preference. A dialog naming the file, stating it will be transmitted, per file.
2. **The UI says so plainly.** No silent escalation. Ever.
3. **Claude structures; it does not interpret.** "This column is transaction
   dates, this one is amounts, negatives are debits." It does not decide what the
   numbers mean for the books.
4. **Output goes through cross-foot and verification like every other tier.**
   Tier 3 is not a trusted shortcut past stages 3 and 4 — if anything it is the
   tier most in need of them.
5. **Disabled entirely by the AI kill switch.** With AI off, Tier 3 is
   unavailable and documents that need it are honestly unprocessable rather than
   silently degraded.

---

## 9.4 Stage 2 — column mapping, confirm-and-correct

Per spec: *column mapping with a confirm-and-correct step, never a silent guess.*

```swift
struct ColumnMapping: Hashable, Codable, Sendable {
    let sourceColumn: Int
    let sourceHeader: String?
    let target: MappedField
    let origin: MappingOrigin
    let confirmed: Bool          // no mapping is used unconfirmed on first sight
}

enum MappingOrigin: Hashable, Codable, Sendable {
    case learned(hintID: MappingHintID, timesUsed: Int)   // stage 6
    case suggested(confidence: Double)
    case userSpecified
}

enum MappedField: Hashable, Codable, Sendable {
    case date, description, amount, debit, credit, runningBalance
    case referenceNumber, checkNumber, transactionType
    case ignored
    case unmapped                // explicit — an unmapped column is visible, not dropped
}
```

**`unmapped` is a distinct case from `ignored`.** A column you consciously
excluded and a column nobody looked at are different situations. Silently
dropping an unrecognized column is how a fee column goes missing from a
statement.

**Learned mappings still get confirmed the first time** they apply to a new
document, then apply silently once established. The spec's requirement — *any
field you correct becomes a mapping hint for that document type from that source*
— is about not repeating the same correction monthly, not about skipping
confirmation entirely.

---

## 9.5 Stage 3 — cross-foot validation

The deterministic quality check. Far stronger than a confidence score, and it
costs nothing but arithmetic.

```swift
enum CrossFootCheck: Hashable, Codable, Sendable {
    /// Σ line items == stated subtotal / total
    case lineItemsSumToTotal(extracted: Money, stated: Money)
    /// beginning + credits − debits == ending
    case balanceRollForward(beginning: Money, credits: Money, debits: Money, ending: Money)
    /// extracted row count == stated count
    case transactionCount(extracted: Int, stated: Int)
    /// every date within the stated statement period
    case datesWithinPeriod(outOfRange: [StatementLineID])
    /// running balance column is internally consistent row to row
    case runningBalanceContinuity(breaks: [StatementLineID])
    /// multi-screenshot stitching: no gaps, no double-counted rows
    case stitchIntegrity(gaps: [Int], overlaps: [Int])
}
```

**Rules:**
- Every ingested financial document is cross-footed before its data may produce
  findings (spec).
- A check whose inputs are absent is `notApplicable`, **not** passed. A statement
  with no stated ending balance cannot pass `balanceRollForward`; it doesn't have
  the evidence. `notApplicable` on a required check keeps coverage below
  `.complete`.
- **A failed cross-foot blocks green** on any page consuming the document, via
  `MissingRequirement.crossFootFailed` (§8.1). Not a warning banner.
- Discrepancies are shown **with the specific rows implicated**, so you can go
  look at the source region rather than re-reading the whole document.

**Why this is the strongest control in the ingestion pipeline:** an OCR
confidence score is the model's opinion about its own reading. Cross-footing is
arithmetic on the extracted values, checked against numbers the document itself
states. `$486.20` misread as `$48.620` fails the roll-forward by $48,133.80. The
spec's example is exactly the failure this catches, and it catches it without
trusting anything.

---

## 9.6 Stage 4 — the extraction verification UI

Required by `CLAUDE.md` rule 8 whenever extracted data could lead to a QBO write.

```
┌─────────────────────────────┬─────────────────────────────┐
│  SOURCE                     │  EXTRACTED                  │
│  (original image / PDF)     │  (editable table)           │
│                             │                             │
│  ┌───────────────────┐      │  Date       Desc      Amt   │
│  │ 07/14  PERMIAN    │◀─────┼─ 07/14  PERMIAN…  486.20    │
│  │        SUPPLY     │      │  07/14  PERMIAN…  486.20    │
│  │        486.20     │      │  07/15  ODESSA…  ⚠ 48.620   │ ← low conf
│  └───────────────────┘      │                             │
│  region highlighted on      │  ⚠ 3 fields below threshold │
│  row selection              │  ⚠ Cross-foot FAILED:       │
│                             │     ending balance off by   │
│                             │     $48,133.80              │
└─────────────────────────────┴─────────────────────────────┘
      Coverage: PARTIAL (screenshot source)   [Confirm] [Correct] [Reject]
```

Requirements from the spec, each with its implementation consequence:

| Requirement | Consequence |
|---|---|
| Side by side with the source image | `SourceRegion` must be captured at stage 1 |
| Low-confidence fields highlighted, not buried | Per-field confidence retained, not just an aggregate |
| Corrections become mapping hints | Stage 6 |
| Extracted financial data never auto-approved into a write-leading finding | Verification is a gate, not a review screen you can skip |

**Cross-foot results are shown here, prominently.** The verification screen is
where a human decides whether to trust the extraction, and "the arithmetic
doesn't work" is the most decision-relevant fact available.

---

## 9.7 Screenshots and partial coverage

Per spec, a screenshot is by nature **partial** — one scroll position of a longer
list, and a screenshot of the first 20 rows of a 340-row report looks complete.

```swift
enum CoverageDetermination: Sendable {
    case complete(evidence: CoverageEvidence)
    case partial(reason: PartialReason)
}

enum CoverageEvidence: Sendable {
    case documentStatesTotal(stated: Money, extractedSum: Money)  // and they match
    case documentStatesCount(stated: Int, extracted: Int)
    case stitchedSetCoversStatedRange(from: Int, to: Int, of: Int)
}

enum PartialReason: Sendable {
    case screenshotSourceWithNoStatedTotal      // the default for screenshots
    case stitchGapDetected([Int])
    case userMarkedIncomplete
}
```

**Screenshot data defaults to `.partial` and is only promoted to `.complete` by
positive evidence** — a stated total the extracted rows reconcile against, or a
stated count they match. A page fed only by screenshots shows *"Coverage
incomplete — screenshot source"*, never green.

**Multi-screenshot stitching** is supported, with **overlap detection to catch
both gaps and double-counted rows** (spec). Both directions matter: a gap loses
transactions, an overlap double-counts them into false duplicates. The stitcher
matches on row content across captures and reports both, feeding
`CrossFootCheck.stitchIntegrity`.

---

## 9.8 Stage 5 — normalization and provenance propagation

Output is `LedgerTransaction`, `ImportedStatement`, `LedgerAccount`, or
`NormalizedReport` (§4) — the same types the API path produces. `/core` rules
cannot tell the difference, which is the whole design.

Provenance travels intact:

```
Document → RawExtraction → Normalized record → NormalizedDataSet → Rule → Finding
   │            │                 │                    │              │
   └── contentHash, format, kind, extractionMethod, confidence,
       coverage, crossFootResult, sourceRegion ────────────────────────┘
```

A finding therefore renders its origin exactly as the spec specifies:

> `source: imported file, chase-july-2026.csv, 2026-08-03, extraction: deterministic`
> `source: screenshot, for-review-queue.png, 2026-08-03, extraction: on-device OCR, coverage: partial`

**Provenance is not summarized on the way through.** From a finding you can reach
the specific document, the specific row, and the highlighted region of the source
image. When you're deciding how much to trust a finding, where its data came from
is part of the answer (spec) — and "part of the answer" means reachable, not
merely labeled.

---

## 9.9 Stage 6 — mapping memory

```swift
struct MappingHint: Identifiable, Codable, Sendable {
    let id: MappingHintID
    let realmID: RealmID            // per client — §7
    let documentKind: DocumentKind
    let sourceSignature: SourceSignature   // header row shape / layout fingerprint
    let mappings: [ColumnMapping]
    let dateFormat: DateFormatSpec
    let learnedAt: Date
    var timesApplied: Int
    var timesCorrectedAfterApplying: Int    // quality signal
}
```

Consistent with the spec's Client Memory principle — learns, but **never
silently**. A learned mapping's first application is confirmed. `timesCorrected`
tracks hints that keep being wrong; a hint corrected repeatedly is proposed for
deletion rather than left to keep mis-mapping.

Hints are per-`realmID` and live in the client's store. A hint learned from one
client's Chase statement does not apply to another client's — different account
structures, possibly different export settings, and cross-client inference is
exactly what §7 exists to prevent.

---

## 9.10 Import staleness

Every Type B page shows when the file was last imported, **with a staleness
warning if the file predates the period being worked** (spec).

```swift
enum ImportFreshness: Sendable {
    case current(coversPeriod: AccountingPeriod)
    case predatesPeriod(importedFor: AccountingPeriod, working: AccountingPeriod)
    case partiallyCovers(gap: DateInterval)
    case superseded(by: ImportedDocumentID)
}
```

Only `.current` permits a page to go green, and it feeds §6's watermark via
`importDigests` — so replacing an import automatically invalidates the pages that
consumed the old one, with no manual step.

---

## 9.11 Matching contract — sets on both sides (interface only, no matcher implementations beyond the slice)

Owner instruction, 2026-08-16, independently converged on by
`docs/backlog/REDDIT_FEEDBACK_ASSESSMENT.md` item 2: a one-to-one matcher
reports a client's normal Stripe settlement as a missing transaction every
month, because a real statement-to-ledger match is routinely **many QBO
records to one bank line, one bank line to many QBO records, or net of fees**
— never reliably one-to-one. Required shapes, from that document:

- Several QBO payments → one bank deposit (this is what Undeposited Funds *is*)
- One statement withdrawal → several QBO lines (a split transaction)
- Settlement deposits net of processing fees (Stripe, PayPal, Square)
- Refunds and chargebacks
- Transaction date vs. cleared date differences
- Amount tolerances for fees and rounding
- Outstanding checks and deposits in transit

**A one-to-one matcher cannot express any of these without hacks** — mapping a
`(statementLine, ledgerTransaction)` pair forces every real settlement into a
false "missing transaction," which is precisely what makes a matching page get
ignored. This is a correctness requirement on the interface, not a feature to
add later: **adopted now as the shape of the matching contract itself. No
matcher beyond what §11's slice needs is implemented in this phase** — the
slice's Branch B needs no statement matching at all (§11.2), so this section
lands with zero conforming matchers, on purpose.

```swift
/// A match is a relation between two SETS of records, never a pair. This is
/// the whole fix: `bankSide`/`ledgerSide` can each hold 1..N members, which is
/// what lets the same type express 1:1, N:1, 1:N, and N:N shapes without a
/// special case per shape.
struct StatementMatch: Identifiable, Sendable {
    let id: StatementMatchID
    let bankSide: [StatementLineID]        // 1 or more statement lines
    let ledgerSide: [LedgerTransactionID]  // 1 or more QBO-sourced transactions
    let reason: MatchReason
    let tolerance: MatchTolerance
    let netDifference: Money               // bankSide total − ledgerSide total;
                                            // zero for an exact match, non-zero
                                            // and EXPLAINED for a fee-net match
}

enum MatchReason: Hashable, Codable, Sendable {
    case exactAmountAndDate
    case exactAmountNearDate(daysApart: Int)
    case sumOfLedgerEqualsBankAmount            // N:1 — grouped deposit
    case sumOfBankEqualsLedgerAmount            // 1:N — split transaction
    case settlementNetOfFees(feeAccount: AccountID, feeAmount: Money)
    case refundOrChargeback(originalMatchID: StatementMatchID)
    case clearedDateDiffersFromTransactionDate(days: Int)
    case outstandingAtStatementEnd              // check/deposit in transit — no
                                                 // ledger-side match expected yet
    case userConfirmed                          // manual override, always allowed
}

struct MatchTolerance: Hashable, Codable, Sendable {
    let amount: Money        // e.g. $0.02 for rounding
    let dateWindow: Int       // days
}
```

**Why `netDifference` is a required field, not optional:** a fee-net match
(`settlementNetOfFees`) is only trustworthy if the gap between the two sides is
itself explained — a Stripe deposit that's $4.87 short of the sum of its
payments is correct *only if* $4.87 is accounted for as a fee somewhere. A
match type that hides the residual is indistinguishable from a match that's
silently wrong by the fee amount.

**Where this plugs in:** Pages 4 and 5 (the two pages this doc's intro already
names as most API-limited) are the intended consumers, once built — not in
this phase. `StatementMatch` doesn't replace `CrossFootCheck` (§9.5) or
`Provenance` (§9.8); a matched set still carries its members' individual
provenance, and cross-foot still runs on the statement independently of
matching.
