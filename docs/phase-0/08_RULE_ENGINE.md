# 8. Deterministic Rule Engine Interface

How a rule is defined, registered, versioned, and tested.

`CLAUDE.md` rule 1: *code computes and classifies; Claude explains.* This document
is where that rule is made mechanical. Every dollar figure, severity, confidence
score, and pass/fail decision originates here, in `/core`, which imports nothing
from `/integrations`.

---

## 8.1 The three-outcome decision (D1)

The single most important design choice in the engine:

```swift
enum RuleOutcome: Sendable {
    /// The check ran on complete, current data and found no exception.
    /// The ONLY outcome that can produce green.
    case pass(coverage: Coverage, checkedCount: Int)

    /// The check ran and found exceptions.
    case findings([Finding])

    /// The check could NOT run. Not the same as finding nothing.
    case cannotEvaluate(MissingRequirement)
}

enum MissingRequirement: Hashable, Sendable {
    case noData(QBOEntityKind)
    case partialCoverage(Coverage, reason: String)
    case importRequired(what: String, whereInQBO: String)
    case importStale(ImportedDocumentID, importedAt: Date)
    case crossFootFailed(ImportedDocumentID, [CrossFootDiscrepancy])
    case featureNotEnabled(String)                    // Class tracking, AST, etc.
    case capabilityUnverified(matrixRowID: String)    // CLAUDE.md #6
    case connectionUnhealthy(RealmID)
    case dependencyPageIncomplete(WorkflowPage)
    case reportColumnMissing(ReportKind, ColumnKey)
}
```

A two-case outcome (`pass` / `findings`) makes "zero findings" and "couldn't
check" the same value, and that collapse is precisely how a missing import
becomes a green checkmark. With three cases, the compiler forces every consumer
to handle "couldn't check" separately, and §5.7's color derivation has nowhere to
route it except gray.

**Additionally: `.pass` cannot be *recorded* when coverage isn't complete.** The
engine validates the returned outcome:

```
if case .pass(let coverage, _) = outcome, coverage != .complete {
    // Rule bug. Downgrade to .cannotEvaluate(.partialCoverage(...)) and
    // record an engine defect. Fail loudly in debug.
}
```

So a rule author who forgets cannot produce a false green. This is defense
against our own future carelessness, which is the carelessness most worth
defending against.

---

## 8.2 A rule

```swift
protocol Rule: Sendable {
    associatedtype Input: RuleInput

    static var identity: RuleIdentity { get }
    static var requirements: DataRequirements { get }

    /// Pure. No I/O, no network, no clock, no randomness.
    /// Same input ⇒ same output, forever. This is what makes findings
    /// reproducible and testable, and it is not negotiable.
    func evaluate(_ input: Input, context: RuleContext) -> RuleOutcome
}

struct RuleIdentity: Hashable, Codable, Sendable {
    let id: RuleID                       // "VL-DUP-EXP-001" — stable forever
    let version: RuleVersion             // semantic; see §8.4
    let title: String
    let category: FindingCategory
    let ruleClass: RuleClass             // §8.2a — relationship vs. categorization
    let page: WorkflowPage
    let accountingPrinciple: String      // Training Mode: *why*, not just *what*
    let sourceDependencies: Set<SourceDependency>   // §4.12 — declares QBO-specific needs
}

/// §8.2a. Which prior question this rule answers. Relationship rules answer
/// "is this the right kind of transaction" (match/transfer/split/refund/
/// owner movement); categorization rules answer "is the category correct."
/// The distinction exists so the engine can gate one class on the other —
/// see §8.2a and §8.5 step 1a.
enum RuleClass: String, Hashable, Codable, Sendable {
    case relationship
    case categorization
}

struct DataRequirements: Sendable {
    let entities: Set<QBOEntityKind>
    let reports: Set<ReportKind>
    let imports: Set<ImportKind>
    let requiredCoverage: Coverage       // almost always .complete
    let capabilityRows: Set<String>      // §2 matrix rows this rule depends on
    let featureFlags: Set<CompanyFeature>  // .classTracking, .automatedSalesTax, …
}
```

**`accountingPrinciple` is a required field, not documentation.** Per spec's
Training Mode: every flag answers "why was this flagged?" with the underlying
accounting principle, not just the rule. Making it required means a rule cannot
be added without articulating its justification — which is also a decent filter
against rules nobody can justify.

**`capabilityRows` is how `CLAUDE.md` rule 6 reaches the engine.** Before
evaluation, the engine checks each referenced matrix row's status. Any row still
`ASSUMED` for a *resolution* the rule proposes → the finding's actions carry
`ResolutionConstraint.capabilityUnverified` (§5.2) and render unavailable. The
rule still *detects*; it just cannot offer an unproven fix.

**`context` carries no I/O.** `RuleContext` holds the period, materiality
thresholds, the company's feature flags, client memory rules, and previously
dismissed findings — all values, no handles. A rule physically cannot call the
network or read the clock, which is what makes `evaluate` reproducible.

---

## 8.2a Relationship-before-category ordering (interface only — design accommodation, no relationship rules yet)

Owner instruction, 2026-08-16: the engine currently only asks "is the category
correct?" There's a prior question — "is this the right *kind* of transaction?"
(matched to an existing bill/invoice/payment, a credit-card payment, a
transfer, part of a grouped deposit, a split, a refund, an owner contribution
or distribution) — and every catastrophic error lives in that first set. A
wrong category is off by one P&L line; a "categorize" that should have been a
"match" duplicates the transaction outright.

This section adds the **interface accommodation** — ordering with gating — so
the cost of retrofitting it after rules exist is paid once, now, instead of
after 26 rules. **No relationship-class rule is implemented in this phase.**

```swift
extension RuleEngine {
    /// Relationship-class rules evaluate first, in `RuleClass.relationship`
    /// order, for a given transaction. If one FIRES (produces a finding),
    /// every categorization-class rule scoped to the same transaction is
    /// gated — it does not run, and its absence is not silent.
    struct GatingOutcome: Sendable {
        let suppressedRuleIDs: Set<RuleID>
        let gatingFindingID: FindingID   // the relationship finding that caused it
        let reason: String               // rendered on the categorization rule's
                                          // would-be finding: "not evaluated — see <gatingFindingID>"
    }
}
```

**Why gating, not just ordering.** Running both classes and showing both
findings would let a categorization suggestion sit next to a relationship
finding that already explains the transaction — visually implying two separate
problems where there's one. Gating collapses that to one finding with a clear
cause, and the suppressed categorization rule is *recorded as gated*, not
silently skipped — matching §8.5 step 6's rule that suppression must stay
visible.

**Placed as engine step 1a** (see revised §8.5): after the requirement check,
before data assembly, relationship-class rules for a transaction's scope run
first; a fired relationship rule adds its `RuleID`s to that transaction's gate
set before categorization-class rules are considered for it.

---

## 8.2b Per-tier rule introspection (general capability, not a `VL-DUP-EXP-001` special case)

Owner instruction, 2026-08-16, in response to the T2 (`UseCustomTxnNumbers`)
conditional-applicability finding in §11.2: *"this needs per-tier introspection
on `Rule`, which is a real interface change... make it a general capability, not
a special case for this rule: any rule with multiple detection tiers should be
able to report which tiers are active for this client and why."*

```swift
/// A detection tier within a single rule — e.g. VL-DUP-EXP-001's T1 (exact
/// match), T2 (reference/DocNumber match), T3 (near-date match).
struct RuleTier: Hashable, Codable, Sendable {
    let id: String                 // stable within the rule, e.g. "T1", "T2", "T3"
    let label: String              // "Exact match", "Reference number match", …
    let confidence: Confidence     // what this tier can award if it matches
}

/// Optional — only rules with more than one detection tier conform.
/// A rule with a single tier has nothing to report and doesn't need it.
protocol MultiTierRule: Rule {
    /// Pure, same contract as `evaluate` — no I/O, no clock. Given the
    /// client's feature flags and company facts (via `RuleContext`), report
    /// which of this rule's tiers are active and why.
    static func tierApplicability(context: RuleContext) -> [TierStatus]
}

struct TierStatus: Hashable, Codable, Sendable {
    let tier: RuleTier
    let active: Bool
    let reason: String   // "Custom Transaction Numbers is off in this client's
                          //  QBO vendor/purchases settings" — always populated,
                          // for both active and inactive, so Training Mode can
                          // show *why* a tier is or isn't in play.
}
```

**Informational, not a coverage gate — non-negotiable.** An inactive tier must
never push `RuleOutcome` toward `.cannotEvaluate`. As long as at least one tier
is active, the rule is fully evaluable; `tierApplicability` is read-only
metadata layered on top of a `RuleOutcome` that's computed exactly as before.
The engine does not consult `tierApplicability` when deciding evaluability —
only Training Mode and the finding's evidence rendering do.

**Where it surfaces:**
- Training Mode reads `tierApplicability` for the rule and states which tiers
  are live for this client and why, per the owner's explicit requirement.
- A finding produced by a specific tier can drop irrelevant evidence fields
  for tiers that didn't fire (§11.4's worked example drops `docNumber` from the
  highlight set when only T1 matched).

`VL-DUP-EXP-001` is the first (and, in this phase, only) conformer — see
§11.2's `.customTxnNumbersForPurchases` company feature flag, populated from
`VendorAndPurchasesPrefs.UseCustomTxnNumbers` and cached with other company
facts read into `RuleContext`.

---

## 8.3 Registration

```swift
enum RuleRegistry {
    /// Compile-time registration. Adding a rule means editing this list, which
    /// means it appears in a diff and gets reviewed. No runtime discovery,
    /// no reflection, no plugin loading.
    static let all: [AnyRule] = [
        AnyRule(DuplicatePostedExpenseRule()),   // VL-DUP-EXP-001
        // …
    ]

    static func rules(for page: WorkflowPage) -> [AnyRule]
    static func rules(requiring: QBOEntityKind) -> [AnyRule]
    static func rule(id: RuleID, version: RuleVersion) -> AnyRule?   // for replay
}
```

**Why not dynamic registration:** a rule that silently fails to register produces
a page that passes because nothing ran — the exact false-green failure mode. A
static array cannot fail to register, and a missing entry is visible in review.

`rule(id:version:)` resolving *historical* versions matters for the activity log:
explaining why a finding was raised three months ago requires the rule as it was
then, not as it is now.

---

## 8.4 Versioning

```swift
struct RuleVersion: Hashable, Codable, Comparable, Sendable {
    let major: Int    // detection semantics changed — prior findings not comparable
    let minor: Int    // thresholds/scope changed — prior findings may differ
    let patch: Int    // no semantic change (wording, performance, refactor)
}
```

| Change | Bump | Effect on existing findings |
|---|---|---|
| Match criteria changed | **major** | `.needsRevalidation`; not auto-resolved |
| Severity assignment changed | **major** | `.needsRevalidation` |
| Threshold tuned | **minor** | `.needsRevalidation` |
| Scope narrowed/widened | **minor** | `.needsRevalidation` |
| Message wording | patch | none |
| Refactor, no behavior change | patch | none — **proven by golden fixtures** |

**A major or minor bump propagates through §6's watermark** (`ruleVersions` is a
watermark component), so pages completed under the old version go
`stale(cause: .ruleVersionBumped(...))` automatically. No manual invalidation
sweep, and no possibility of forgetting.

**A patch bump asserting "no behavior change" is verified, not claimed.** The
golden fixture suite must produce byte-identical output. If it doesn't, the bump
was wrong and CI says so.

---

## 8.5 Evaluation

```swift
actor RuleEngine {
    func evaluate(page: WorkflowPage, in scope: ClientScope, period: AccountingPeriod)
        async -> PageEvaluation
}

struct PageEvaluation: Sendable {
    let results: [RuleID: CheckResult]
    let watermark: EvidenceWatermark     // §6 — computed here, from what was read
    let engineDefects: [EngineDefect]    // rule bugs caught by §8.1's validation
}
```

Sequence per rule:

1. **Requirement check.** Any requirement unmet → `.cannotEvaluate` with the
   specific reason. The rule never runs. Cheap, and it means rules don't each
   reimplement "is my data here."
1a. **Relationship gating (§8.2a — interface only, no relationship rules
   registered yet).** `RuleClass.relationship` rules scoped to a transaction
   evaluate before `RuleClass.categorization` rules scoped to the same
   transaction. A fired relationship rule adds the transaction to that rule's
   `GatingOutcome.suppressedRuleIDs`; gated categorization rules do not run for
   that transaction, and the gate is recorded, not silent — Coverage/Findings
   views can list "N categorization checks gated by relationship finding
   `<id>`." With zero relationship rules registered, this step is a no-op in
   practice, but the branch exists and is exercised in engine tests via a
   fixture relationship rule.
2. **Data assembly.** `NormalizedDataSet` (§4.11) built from the client store,
   carrying coverage and defects.
3. **Coverage gate.** `dataSet.coverage < requirements.requiredCoverage` →
   `.cannotEvaluate(.partialCoverage)`. The rule never runs.
4. **Evaluate.** Pure function call.
5. **Outcome validation.** §8.1's `.pass`-with-incomplete-coverage check.
6. **Suppression.** Client memory rules and prior dismissals applied *after*
   detection, never before — so a suppressed finding is still counted and still
   visible under "suppressed," rather than vanishing. Suppression that hides the
   fact of suppression is indistinguishable from a bug.
7. **Record.** Findings persisted with `ruleID`, `ruleVersion`, provenance,
   watermark.

**Determinism requirement:** re-running step 4 on the same `NormalizedDataSet`
must produce identical output including finding IDs. Finding IDs are therefore
**derived** — a digest over `(ruleID, ruleVersion, realmID, period, sorted
affected source identities)` — not random UUIDs. Re-detection of the same problem
produces the same ID, which is what makes "this finding is unchanged since last
sync" answerable, and prevents duplicate findings accumulating on every sync.

---

## 8.6 Materiality and thresholds

Deterministic code determines materiality (spec, Rules Engine vs. Claude).

```swift
struct MaterialityPolicy: Hashable, Codable, Sendable {
    let absoluteFloor: Money                       // ignore below this
    let percentOfRevenue: Decimal?
    let percentOfTotalAssets: Decimal?
    let accountOverrides: [AccountID: Money]       // cash and clearing accounts are tighter
}
```

Per client, versioned, and **part of the evidence watermark** — changing
materiality changes findings, so pages completed under the old policy go stale.
It is stored on the client record, editable by you, and every change is recorded
in the activity log. A silently-changed materiality threshold would alter
conclusions without any trace, which would undermine the close package.

### Default policy (owner decision, 2026-08)

```swift
static let defaultPolicy = MaterialityPolicy(
    absoluteFloor: Money(minorUnits: 2500, currency: .usd),   // $25 flat
    percentOfRevenue: nil,                                     // none by default
    percentOfTotalAssets: nil,
    accountOverrides: [:]                                      // set per client
)
```

**Deliberately no percentage-of-revenue component.** This is bookkeeping cleanup,
not audit — a duplicate expense is an error regardless of size, and a revenue-
scaled floor would suppress small duplicates on larger clients, backwards from
what the tool is for. The floor starts low and is raised per client once
transaction volume is known, never the other way around.

**Cash and clearing accounts get a tighter override.** A small unexplained
difference there usually signals a structural problem, not a rounding artifact —
`accountOverrides` should default new clients' bank and clearing accounts to a
floor near zero (e.g. $1) rather than inheriting the flat $25. The UI for editing
this per client is in scope for Phase 1, not deferred.

---

## 8.7 Testing a rule

Four layers. All of layer 1 and 2 run without network access.

### Layer 1 — golden fixtures (the primary mechanism)
```
Tests/Rules/VL-DUP-EXP-001/
  case-01-exact-duplicate/{input.json, expected.json, README.md}
  case-02-same-day-different-vendor/…
  case-03-legitimate-recurring/…
  case-04-partial-coverage/…            → expects .cannotEvaluate
  case-05-closed-period/…               → expects ResolutionConstraint.closedPeriod
```

`input.json` is a serialized `NormalizedDataSet`; `expected.json` is the
serialized `RuleOutcome`. The `README.md` states, in accounting terms, what the
case represents and why the expectation is right — so a failing test is
diagnosable by a bookkeeper, not only by whoever wrote the rule.

**Every fixture set must include at least one `.cannotEvaluate` case.** A rule
without one has probably not thought about missing data, which is the failure
mode `CLAUDE.md` rule 5 exists to prevent.

### Layer 2 — property tests
Invariants that must hold across generated inputs:
- **Idempotence:** evaluating twice yields identical output, IDs included.
- **Symmetry** (matching rules): if A matches B, B matches A.
- **Coverage monotonicity:** a rule never returns `.pass` on `.partial` coverage.
- **Suppression neutrality:** suppression changes visibility, never detection count.
- **Source equivalence:** the same data via API and via CSV yields the same
  findings modulo provenance. This is §4.1's contract, tested.

### Layer 3 — sandbox integration
Seeded sandbox → real sync → rule → assert expected findings. Tagged, run on
demand, not on every commit. Catches normalization drift that fixtures cannot,
because fixtures are frozen at the shape we *thought* the API returned.

### Layer 4 — regression corpus
Every false positive found in real use becomes a fixture case with the correct
expectation, permanently. `DismissalReason.ruleFalsePositive` (§5.6) is the feed:
dismissals with that reason surface as candidate fixtures. This is how rule
quality compounds instead of oscillating.

---

## 8.8 The rule backlog

Seeded from the spec's Reference Findings Library. IDs assigned now so they are
stable; only the first is scoped in this phase (§11).

| Rule ID | Detection | Page | Phase |
|---|---|---|---|
| `VL-DUP-EXP-001` | Duplicate posted expenses (same payment account) | 3 | **1 — the vertical slice** |
| `VL-DUP-EXP-002` | Cross-account duplicate candidate — same vendor/amount/near-date, **different** payment account, `.medium` confidence at best | 3 | 2 |
| `VL-DUP-BILL-001` | **IMPLEMENTED 2026-08-17** (`desktop/Sources/Core/DuplicateBillRule.swift`) — duplicate bills, single exact-match tier (vendor + date + amount), deliberately narrower than `VL-DUP-EXP-001` (no DocNumber tier — Bill's DocNumber-uniqueness behavior unverified; no near-date tier — not added speculatively). Required the second new backend catalog operation this session (`readBills`, matrix row 13.5). `Bill` normalizes into the same `LedgerTransaction` shape as `Purchase`. Live-verified against a real seeded duplicate-bill pair. | Cleanup Assessment | **Built** |
| `VL-DUP-INV-001` | Duplicate invoices | 3 | 2 |
| `VL-DUP-PAY-001` | Duplicate payments | 3 | 2 |
| `VL-DUP-VEND-001` | **IMPLEMENTED 2026-08-17** (`desktop/Sources/Core/DuplicateVendorRule.swift`) — duplicate vendor records, matched by normalized-EXACT name (case/punctuation/whitespace/common-suffix stripped), deliberately not fuzzy — see the rule's own doc comment for why, after `VL-COA-DUPACCT-001`'s false-positive finding (below in this same table). Required adding the first new backend catalog operation since Phase 1 step 1.2 (`readVendors`, matrix row 13.4). Live-verified against a real seeded near-duplicate pair. | Cleanup Assessment | **Built** |
| `VL-RECON-DIFF-001` | Bank/CC reconciliation differences | 5 | 2 |
| `VL-RECON-MISSING-001` | Statement line with no posting | 4, 5 | 2 |
| `VL-CAT-UNCAT-001` | Uncategorized transactions | 3 | 2 |
| `VL-CAT-MISCODE-001` | Probable miscoding vs. vendor history | 3 | 3 |
| `VL-VEND-ANOMALY-001` | Unusual vendor name, amount, or timing | 3 | 3 |
| `VL-BS-NEGBAL-001` | **IMPLEMENTED 2026-08-17** (`desktop/Sources/Core/NegativeBalanceRule.swift`) — negative CurrentBalance on an Asset or Liability-classified account. Live-verified: 6 real accounts in the sandbox currently trip it. | 8 | **Built** |
| `VL-BS-CLEARING-001` | Stale or abnormal clearing accounts. Not attempted 2026-08-17 — needs per-account last-activity-date, which isn't on the Account entity itself; would need transaction-level cross-referencing across entity types not yet in the catalog. | 8 | 2 |
| `VL-BS-UNDEP-001` | Undeposited funds aging. Not attempted 2026-08-17 — "aging" needs per-transaction dates for what's sitting in Undeposited Funds (Payment/Deposit entity reads, not in the catalog); a balance-only check would just flag normal short-term UF activity as noise. | 8 | 2 |
| `VL-BS-SUSPENSE-001` | Suspense account activity. **Checked live 2026-08-17, not buildable as safely as `VL-OBE-BALANCE-001`:** unlike Opening Balance Equity, QBO has no system `AccountSubType` for a "suspense" account — detection would mean matching on account *name* alone, which the `VL-COA-DUPACCT-001` investigation below just proved unreliable in this exact sandbox. No suspense-named account exists here to test against either way. Left as backlog rather than shipped on an unverified heuristic. | 8 | 2 |
| `VL-BS-LOAN-001` | Loan balance inconsistencies | 8 | 3 |
| `VL-BS-EQUITY-001` | Equity postings needing review | 8 | 3 |
| `VL-BS-DRCR-001` | Debit/credit pattern vs. account expectation | 8 | 3 |
| `VL-SUB-INCREASE-001` | Recurring subscription increased | 3 | 3 |
| `VL-SUB-UNUSED-001` | Recurring subscription appears unused | 3 | 3 |
| `VL-FEE-AVOIDABLE-001` | Late fees, overdrafts, avoidable interest | 3 | 3 |
| `VL-VEND-PRICE-001` | Vendor price increases | 3 | 3 |
| `VL-VEND-DUPSVC-001` | Possible duplicate services | 3 | 3 |
| `VL-PERSONAL-001` | Possible personal expense or owner draw | 3 | 3 |
| `VL-COA-DUPACCT-001` | Duplicate account candidates. **Investigated live 2026-08-17, not built.** Naive matching on account `Name` alone produces systematic false positives: this sandbox has 8 pairs of identically-named accounts (`Decks and Patios`, `Job Materials`, `Equipment Rental`, etc.) that are QBO's own industry-template pattern — the same leaf name legitimately used for both an Income and a matching COGS/Expense sub-account under different parents, for job costing. A safe version needs to match on `FullyQualifiedName` (or genuine near-duplicate fuzzy matching), not leaf `Name` — and this sandbox has zero real duplicate-account examples under that stricter, correct definition, so there's no live positive case to verify against yet either. Left as backlog with the false-positive risk documented rather than shipped on the naive approach. | 6 | 2 |
| `VL-PERIOD-CLOSED-001` | Transactions dated in a closed period | 2 | 2 |
| `VL-REPORT-TIE-001` | Report tie-out mismatch | 12 | 3 |

Twenty-seven rules. Phase 1 shipped one, proven end to end (§11). Three more
shipped 2026-08-17 as the Cleanup Assessment's first pass (below) — see
`docs/VOICE_LEDGER_HANDOFF.md` for the live-verification record.

### Backlog additions from `docs/backlog/` (2026-08-16; four built 2026-08-17)

IDs reserved per the owner's Part 4 instruction so they're stable once the
source documents are implemented. Source: `docs/backlog/CLEANUP_MODE.md` and
`docs/backlog/REDDIT_FEEDBACK_ASSESSMENT.md` — both filed in full (not
summarized) under `docs/backlog/`; the detection column below is a one-line
compression, not the complete design. **Four rows below are now IMPLEMENTED,
not backlog — built and live-verified 2026-08-17 per the owner's instruction
to continue building the Cleanup Assessment autonomously. The rest remain
backlog; do not implement them without separate approval.**

| Rule ID | Detection (one-line — see source doc for the real design) | Page | Status |
|---|---|---|---|
| `VL-RELATIONSHIP-001`…`-006` | Transaction Relationship Guard — one rule per branch of the "is this even the right kind of transaction" decision tree (match-to-existing / credit-card-payment / transfer / grouped-deposit / split / refund-or-owner-movement), evaluated before any categorization rule on the same transaction. **`-002` (credit-card-payment branch) is now built as `VL-CC-PAYMENT-001` — see that row; the overlap is resolved, not just flagged, by implementing `VL-CC-PAYMENT-001` itself as `RuleClass.relationship`.** The other five branches remain backlog. | 3 | Backlog (5 of 6 branches) |
| `VL-CC-PAYMENT-001` | **IMPLEMENTED 2026-08-17** (`desktop/Sources/Core/CreditCardPaymentMiscodedRule.swift`). Credit-card payment coded to an expense account instead of the card's balance-sheet liability account. Built as `RuleClass.relationship` — the first real (non-fixture) conformer to §8.2a's gating. `.high` confidence when the vendor name structurally matches a real Credit-Card-type account in the client's chart of accounts, `.medium` on keyword match alone. Live-verified against the sandbox. | Cleanup Assessment | **Built** |
| `VL-PAYROLL-LUMP-001` | **IMPLEMENTED 2026-08-17** (`desktop/Sources/Core/PayrollLumpSumRule.swift`). Payment to a known payroll processor (ADP, Gusto, Paychex, Rippling, QuickBooks Payroll, Justworks, TriNet) coded entirely to one expense account. Resolution is guided-manual (needs the payroll register — cannot compute the correct split without it). Live-verified. | Cleanup Assessment | **Built** |
| `VL-VENDOR-MISMATCH-001` | Statement's original bank description diverges from QBO's cleaned-up vendor name (Import Bridge: match on date+amount, compare descriptions). Not buildable without the Import Bridge (§9), which doesn't exist yet. | 3 | Backlog |
| `VL-PREPAID-PERIOD-001` | Large payment where an attached document's service period extends past the transaction date (needs OCR on the attachment). Not buildable without the Import Bridge. | 3 | Backlog |
| `VL-OPENING-BAL-001` | **DISPROVEN as originally scoped, 2026-08-17.** Was going to read a non-zero opening-balance entry plus a nearby equity contribution. Checked against the live sandbox first: `Account.OpeningBalance`/`OpeningBalanceDate` are write-only on create — QBO never returns them on any subsequent read, so there is no field to detect this from. See `VL-OBE-BALANCE-001` below for the buildable alternative that replaced this plan. | 6 | Disproven, not building as scoped |
| `VL-CLOSED-PERIOD-DRIFT-001` | A closed period's stored trial-balance snapshot/hash no longer matches on resync — someone (client, prior bookkeeper, QBO auto-categorization) edited a closed-period transaction. No audit-log dependency; needs no API QBO doesn't already expose. | 2 | Backlog |
| `VL-FORCED-RECON-001` | Non-zero balance in Reconciliation Discrepancies — someone forced a reconciliation to close rather than finding the cause. **Checked live 2026-08-17, not buildable right now:** no "Reconciliation Discrepancies" account exists in this sandbox — nothing has ever forced a reconciliation here, and creating that test data means actually performing a forced reconciliation in the QBO UI, which needs the owner's call, not an autonomous one. A guessed `AccountSubType` of `'DiscrepancyAccount'` was also rejected outright by QBO's query engine as invalid, so even the query predicate isn't confirmed. | 5 | Backlog |
| `VL-OBE-BALANCE-001` | **IMPLEMENTED 2026-08-17** (`desktop/Sources/Core/OpeningBalanceEquityRule.swift`). Non-zero balance in the account with `AccountSubType == "OpeningBalanceEquity"` — verified live as the reliable structural signal (this sandbox's own Opening Balance Equity account carries a real nonzero balance). Replaces the disproven `VL-OPENING-BAL-001` plan above. | Cleanup Assessment | **Built** |
| `VL-AUTOADD-RULE-001` | Imported bank-rules export shows a rule with auto-add enabled, broad matching condition, whose category doesn't match how similar transactions were historically coded. Not buildable without the Import Bridge. | 4 | Backlog |

**Not rule IDs — filed as page/interface designs in the backlog docs, not
detection rules:** many-to-one/one-to-many statement matching (Part 3 already
covers the matching *interface*; the reddit doc's version is the same
requirement, not a separate rule), Account-Month Control Grid, Client
Accounting Control Profile (a `MaterialityPolicy`-style watermark component,
not a rule), Balance-Sheet Evidence Workpapers, Sensitive-Write Preflight risk
tiers (extends §10.3's five checks with a reconciled-transaction check — see
`testReconciledTransactionDetection` in `SPIKE_QUEUE.md`), Client Exception
Packet, the hours-estimate/price-band formula (`docs/backlog/CLEANUP_MODE.md`
§1 calls for one; `CleanupAssessmentView.swift` deliberately doesn't show one
yet — it needs account-months-unreconciled and uncategorized-transaction
count, neither of which exists, and a formula built from only the three
rules that do exist would be unearned precision).

**Cleanup Assessment page itself (Type A, no writes) — a minimal version is
now IMPLEMENTED**, 2026-08-17 (`desktop/Sources/VoiceLedgerUI/CleanupAssessmentView.swift`):
total dollar exposure and per-rule finding counts/lists for the three rules
above, reusing the existing design system. Not the full page CLEANUP_MODE.md
describes (no hours estimate, no reconciliation gap map, no paper-client
handling) — those need capabilities that don't exist yet (see above).

**Note on `VL-DUP-EXP-002` and the slice (Q8, owner decision 2026-08):**
`VL-DUP-EXP-001` stays scoped to same-payment-account matches, deliberately
narrower than "any duplicate," because the value of the first slice is in being
narrow (§11). The cross-account case is real — paying the same bill from
checking and then again from a card happens — but it has a different
false-positive profile and belongs in its own rule, its own fixtures, and its
own tuning pass, not folded into the slice.
