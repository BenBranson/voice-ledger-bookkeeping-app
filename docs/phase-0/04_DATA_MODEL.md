# 4. Normalized Accounting Data Model

The internal shape that **both** QBO API data and imported-file data resolve
into. This contract is what makes Type B pages cheap instead of a parallel
codebase (spec, Universal Ingestion §After extraction), and it is the single
preparation required for a future Xero adapter.

Types below are illustrative Swift, written to be reviewed — not to compile as
shipped code. No application code has been written.

---

## 4.1 The contract in one sentence

**A rule written once must produce identical findings whether its input arrived
from the QBO API, a CSV export, or an OCR'd screenshot of the same data —
differing only in the provenance attached to the result.**

§12 makes this a test rather than an aspiration: the same seeded sandbox data is
fed through both paths and the finding sets must match.

---

## 4.2 Design decisions

**M1 — Money is integer minor units plus a currency, never `Double`.**
`Decimal` would also work, but a fixed integer representation makes equality,
hashing, and cross-foot arithmetic exact and makes serialization unambiguous.
Duplicate detection is an equality test on amounts; floating point would make it
subtly wrong.

**M2 — The model is a general ledger, not a QBO entity mirror.**
The normalized layer is double-entry postings with typed source metadata. QBO's
`Purchase` and a CSV row from a bank statement both become the same thing: a
`LedgerTransaction` with `Posting`s. This is what makes a Xero adapter one file.

**M3 — Source-specific data is preserved, not discarded.**
Normalization is lossy by nature, and the loss is dangerous when we later need to
write back (§2, row 7.1: unknown fields get cleared by full updates). Every
normalized record retains `sourceRepresentation` — the verbatim original — and
the write path uses *that*, not the normalized form. **Normalized data is for
reading and rule evaluation; the source representation is for writing.**

**M4 — Every record carries provenance and coverage; neither is optional.**
There is no way to construct a normalized record without stating where it came
from and whether the data set it belongs to is complete. This is what lets §8
refuse to render green on partial data.

**M5 — Two parallel worlds: `Ledger` (what QBO says) and `Statement` (what the
bank/document says).** They are *not* the same type. Page 5's entire job is
comparing them; collapsing them would erase the distinction reconciliation
depends on. They share the value types (`Money`, `AccountRef`) but not the
record types.

---

## 4.3 Value primitives

```swift
/// Exact money. Integer minor units; no floating point anywhere in the model.
struct Money: Hashable, Codable, Sendable {
    let minorUnits: Int64        // 48620 == $486.20 for a 2-decimal currency
    let currency: CurrencyCode   // ISO 4217
}

struct CurrencyCode: Hashable, Codable, Sendable, RawRepresentable {
    let rawValue: String         // "USD"
}

/// Calendar date with no time component and no time zone.
/// Accounting dates are dates, not instants; a TxnDate that shifts across a
/// time zone boundary is a period-assignment bug.
struct AccountingDate: Hashable, Comparable, Codable, Sendable {
    let year: Int, month: Int, day: Int
}

/// Half-open period [start, end]. Inclusive end matches accounting convention.
struct AccountingPeriod: Hashable, Codable, Sendable {
    let start: AccountingDate
    let end: AccountingDate
    let label: String            // "July 2026"
}

enum PostingSide: String, Codable, Sendable { case debit, credit }
```

**Why `AccountingDate` and not `Date`:** a `Date` is an instant. Every
period-boundary bug I would expect in this app comes from an instant being
interpreted in the wrong zone and landing in the adjacent month. Removing the
capability removes the bug class.

---

## 4.4 Identity

```swift
/// The QBO company identifier. The isolation key for everything (§7).
struct RealmID: Hashable, Codable, Sendable, RawRepresentable {
    let rawValue: String
}

/// Identity of a record in whatever system produced it.
enum SourceIdentity: Hashable, Codable, Sendable {
    /// QBO entity: type + Id + the SyncToken observed at read time.
    case qbo(entity: QBOEntityKind, id: String, syncToken: String)
    /// A row in an imported document, addressed for provenance display.
    case imported(documentID: ImportedDocumentID, rowIndex: Int)
    /// Something you entered by hand in Voice Ledger.
    case manual(entryID: UUID)
}

/// Stable internal identity, independent of source.
/// Deterministic so that re-syncing the same QBO entity yields the same
/// LedgerTransactionID rather than duplicating it.
struct LedgerTransactionID: Hashable, Codable, Sendable {
    let rawValue: String   // derived: realmID + source kind + source id
}
```

**Why `syncToken` lives inside `SourceIdentity`:** it is a property of *this
observation*, not of the transaction. Placing it here makes it structurally
obvious that a `LedgerTransaction` read an hour ago carries a possibly-stale
token, which is precisely what the §10 preflight re-checks.

---

## 4.5 Provenance and coverage — mandatory on every record

```swift
struct Provenance: Hashable, Codable, Sendable {
    let dataSource: DataSource
    let extractionMethod: ExtractionMethod
    let extractionConfidence: ExtractionConfidence?   // nil for API data
    let coverage: Coverage
    let observedAt: Date                              // when we obtained it
    let sourceDocument: ImportedDocumentRef?          // nil for API data
    let crossFootResult: CrossFootResult?             // nil for API data
    let minorVersion: Int?                            // QBO minor version, API only
}

enum DataSource: String, Codable, Sendable {
    case qboAPI, importedFile, screenshot, manualEntry
}

enum ExtractionMethod: String, Codable, Sendable {
    case none            // API
    case deterministic   // Tier 1 parser
    case ocrLocal        // Tier 2 Apple Vision
    case claudeVision    // Tier 3 — off-device, consented
}

/// 0.0…1.0 per-field extraction confidence, aggregated at the record level.
struct ExtractionConfidence: Hashable, Codable, Sendable {
    let value: Double
    let lowestFieldValue: Double
    let lowConfidenceFields: [String]
}

enum Coverage: String, Codable, Sendable {
    case complete
    case partial     // screenshots default here (spec); also failed pagination checksums
    case unknown
}

enum CrossFootResult: Hashable, Codable, Sendable {
    case notApplicable                   // document has no internal arithmetic
    case passed(checks: [String])
    case failed(discrepancies: [CrossFootDiscrepancy])
    case notAttempted
}
```

**Coverage defaults matter.** Per spec: screenshot-sourced data defaults to
`.partial` unless the document states a total the extracted rows reconcile
against. A `.partial` data set can never produce a green page — §8 turns that
into `.cannotEvaluate` at the rule level, so it is not something a UI author can
forget.

`Coverage` also carries the pagination-checksum result from §2.6: an API sweep
that fails its count check is `.partial`, not `.complete`. That is the mechanism
that converts a silent skipped-row bug into an honest gray page.

---

## 4.6 Chart of accounts

```swift
struct LedgerAccount: Hashable, Codable, Sendable {
    let id: AccountID                 // internal, stable
    let sourceIdentity: SourceIdentity
    let number: String?               // AcctNum — often absent
    let name: String
    let fullyQualifiedName: String    // "Utilities:Electric"
    let parent: AccountID?
    let classification: AccountClassification
    let type: AccountType
    let subType: String?              // source-specific; kept verbatim
    let currency: CurrencyCode
    let isActive: Bool
    let provenance: Provenance
    let sourceRepresentation: SourceRepresentation   // M3
}

enum AccountClassification: String, Codable, Sendable {
    case asset, liability, equity, revenue, expense
}

enum AccountType: String, Codable, Sendable {
    case bank, accountsReceivable, otherCurrentAsset, fixedAsset, otherAsset
    case accountsPayable, creditCard, otherCurrentLiability, longTermLiability
    case equity
    case income, otherIncome
    case expense, otherExpense, costOfGoodsSold
}
```

`AccountType` is a closed enum drawn from the concepts every double-entry system
shares. `subType` is deliberately an untyped string holding the source's own
value — QBO's detail types are numerous, locale-dependent, and not worth
enumerating in `/core`. Rules that need detail-type precision read `subType` and
declare their source dependency explicitly.

---

## 4.7 Transactions and postings — the center of the model

```swift
struct LedgerTransaction: Hashable, Codable, Sendable {
    let id: LedgerTransactionID
    let realmID: RealmID
    let sourceIdentity: SourceIdentity

    let date: AccountingDate
    let kind: TransactionKind
    let counterparty: CounterpartyRef?
    let documentNumber: String?          // DocNumber / check number / reference
    let memo: String?
    let total: Money                     // signed per kind's convention
    let postings: [Posting]

    let paymentAccount: AccountID?       // bank/CC the money moved through
    let clearedStatus: ClearedStatus     // .unknown for most API reads (§2, 5.1)
    let isVoided: Bool
    let linkedTransactions: [LedgerTransactionID]   // §2 row 7.1 constraint 3

    let provenance: Provenance
    let sourceRepresentation: SourceRepresentation
}

struct Posting: Hashable, Codable, Sendable {
    let lineID: String?                  // source line identity, needed for writes
    let account: AccountID
    let side: PostingSide
    let amount: Money                    // always positive; direction is `side`
    let memo: String?
    let classRef: DimensionRef?          // QBO Plus+ only (§2 row 7.3)
    let departmentRef: DimensionRef?
    let taxTreatment: TaxTreatment?
}

enum TransactionKind: String, Codable, Sendable {
    case expense, bill, billPayment, check, creditCardCharge, creditCardCredit
    case deposit, transfer, journalEntry, invoice, payment, salesReceipt
    case creditMemo, refund, vendorCredit, other
}

enum ClearedStatus: String, Codable, Sendable {
    case unknown        // the honest default — QBO rarely tells us
    case uncleared, cleared, reconciled, voided, deposited, notDeposited
}
```

**Why postings and not just lines:** an expense with three expense lines has four
postings (three debits, one credit to the payment account). Modelling it as
postings makes balance-sheet rules, trial-balance ties, and abnormal-balance
detection fall out naturally rather than requiring per-`TransactionKind` special
cases. It also makes the Xero adapter easy — Xero's shapes differ, its double
entry does not.

**Invariant, enforced at construction:** `postings` must balance —
Σ debits == Σ credits, per currency. A transaction that cannot be balanced from
its source is not silently accepted; it is a `NormalizationDefect` (§4.10) and
its data set becomes `Coverage.partial`.

**`clearedStatus` defaults to `.unknown`, deliberately.** Given §2 row 5.1's
uncertainty, most API-sourced transactions will legitimately have no known
cleared state, and `.unknown` must not be treated as `.uncleared` anywhere.

---

## 4.8 Statement world — separate on purpose (M5)

```swift
struct ImportedStatement: Hashable, Codable, Sendable {
    let id: ImportedDocumentID
    let realmID: RealmID
    let account: AccountID?              // mapped during the confirm step
    let periodStart: AccountingDate?
    let periodEnd: AccountingDate?
    let beginningBalance: Money?         // API cannot supply this (§2 row 5.2)
    let endingBalance: Money?
    let statedLineCount: Int?            // for cross-foot, when present
    let lines: [StatementLine]
    let provenance: Provenance
}

struct StatementLine: Hashable, Codable, Sendable {
    let id: StatementLineID
    let date: AccountingDate
    let description: String
    let amount: Money                    // signed: negative == money out
    let runningBalance: Money?
    let referenceNumber: String?
    let fieldConfidences: [String: Double]   // per-field, for the verify UI
    let sourceRegion: SourceRegion?          // link back to the image region
}
```

`sourceRegion` is what makes the verification screen able to show the extracted
table **side by side with the source image** and highlight the region a given
number came from (spec). It is captured at extraction time or it is not
recoverable, so it is part of the model rather than a UI concern.

---

## 4.9 Reports — a third, distinct class (decision D6)

Reports are not entities and must not pretend to be.

```swift
struct NormalizedReport: Hashable, Codable, Sendable {
    let kind: ReportKind
    let realmID: RealmID
    let period: AccountingPeriod
    let parameters: ReportParameters      // accounting method, date basis, etc.
    let rows: [ReportRow]
    let generatedAt: Date
    let provenance: Provenance
}

indirect enum ReportRow: Hashable, Codable, Sendable {
    case section(title: String, children: [ReportRow], subtotal: [ReportCell])
    case data(label: String, account: AccountID?, cells: [ReportCell])
    case summary(label: String, cells: [ReportCell])
}

struct ReportCell: Hashable, Codable, Sendable {
    let columnKey: ColumnKey    // bound by title/type metadata — NEVER by index
    let value: ReportValue
}
```

**`ColumnKey`, never an index.** §2's `RPT` profile: report column composition
varies by minor version, locale, and company preferences. Positional indexing is
the defect that produces confidently wrong numbers, which is the worst failure
mode this app has. The normalizer binds columns by their declared title/type and
**fails loudly** if an expected column is absent — producing `.cannotEvaluate`,
not a zero.

`parameters` is retained because a P&L on cash basis and one on accrual basis are
different documents, and a tie-out mismatch's first suspect is a parameter
difference (§2 row 12.5).

---

## 4.10 Normalization defects — failures are data

```swift
struct NormalizationDefect: Hashable, Codable, Sendable {
    let kind: DefectKind
    let sourceIdentity: SourceIdentity
    let detail: String
    let severity: DefectSeverity   // .degrades → coverage partial; .rejects → drop record
}

enum DefectKind: String, Codable, Sendable {
    case unbalancedPostings          // §4.7 invariant violated
    case unmappableAccount
    case missingRequiredField
    case ambiguousDateFormat
    case unknownTransactionKind
    case reportColumnMissing         // §4.9
    case currencyMismatch
    case paginationChecksumFailed    // §2.6
}
```

Normalization never throws away a problem silently. A defect either **degrades
coverage** (data set becomes `.partial`, rules downgrade to `.cannotEvaluate`) or
**rejects the record** and degrades coverage. Both outcomes are visible on the
page. There is no third option where the record quietly disappears — that is the
mechanism by which a missing transaction becomes a false green.

---

## 4.11 The data set — the unit rules actually consume

```swift
/// What a rule receives. Never a bare array — an array cannot tell you
/// whether it is complete.
struct NormalizedDataSet<Element>: Sendable {
    let realmID: RealmID
    let period: AccountingPeriod
    let elements: [Element]
    let coverage: Coverage
    let provenance: [Provenance]         // one per contributing source
    let defects: [NormalizationDefect]
    let watermark: EvidenceWatermark     // §6 — what "current" means for this set
}
```

**This type is the enforcement point for `CLAUDE.md` rule 5.** A rule cannot
receive data without also receiving its coverage. §8's rule protocol takes a
`NormalizedDataSet`, and the engine refuses to record a `.pass` when coverage is
not `.complete`. Green becomes structurally unreachable on incomplete data rather
than depending on every rule author remembering.

---

## 4.12 What Xero would require

Stated to check M2 actually holds:

- A `/integrations/xero` adapter producing `LedgerAccount`, `LedgerTransaction`,
  `NormalizedReport`, and `Provenance`.
- New cases in `SourceIdentity` and `QBOEntityKind`'s sibling.
- A new operation catalog in the backend (§3.4).
- **Zero changes to `/core`** — no rule, no finding type, no severity logic.

Where it would leak, honestly: `subType` (§4.6) is source-specific by design, so
rules keying on QBO detail types are QBO-specific. That is acceptable and should
be *declared* — §8's `Rule.sourceDependencies` makes a rule state when it
requires a particular source, so the Xero adapter's gaps are enumerable rather
than discovered at runtime.
