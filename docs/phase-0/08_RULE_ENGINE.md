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
    let page: WorkflowPage
    let accountingPrinciple: String      // Training Mode: *why*, not just *what*
    let sourceDependencies: Set<SourceDependency>   // §4.12 — declares QBO-specific needs
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
| `VL-DUP-BILL-001` | Duplicate bills | 3 | 2 |
| `VL-DUP-INV-001` | Duplicate invoices | 3 | 2 |
| `VL-DUP-PAY-001` | Duplicate payments | 3 | 2 |
| `VL-DUP-VEND-001` | Duplicate vendor records | 3 | 2 |
| `VL-RECON-DIFF-001` | Bank/CC reconciliation differences | 5 | 2 |
| `VL-RECON-MISSING-001` | Statement line with no posting | 4, 5 | 2 |
| `VL-CAT-UNCAT-001` | Uncategorized transactions | 3 | 2 |
| `VL-CAT-MISCODE-001` | Probable miscoding vs. vendor history | 3 | 3 |
| `VL-VEND-ANOMALY-001` | Unusual vendor name, amount, or timing | 3 | 3 |
| `VL-BS-NEGBAL-001` | Negative asset/liability balances | 8 | 2 |
| `VL-BS-CLEARING-001` | Stale or abnormal clearing accounts | 8 | 2 |
| `VL-BS-UNDEP-001` | Undeposited funds aging | 8 | 2 |
| `VL-BS-SUSPENSE-001` | Suspense account activity | 8 | 2 |
| `VL-BS-LOAN-001` | Loan balance inconsistencies | 8 | 3 |
| `VL-BS-EQUITY-001` | Equity postings needing review | 8 | 3 |
| `VL-BS-DRCR-001` | Debit/credit pattern vs. account expectation | 8 | 3 |
| `VL-SUB-INCREASE-001` | Recurring subscription increased | 3 | 3 |
| `VL-SUB-UNUSED-001` | Recurring subscription appears unused | 3 | 3 |
| `VL-FEE-AVOIDABLE-001` | Late fees, overdrafts, avoidable interest | 3 | 3 |
| `VL-VEND-PRICE-001` | Vendor price increases | 3 | 3 |
| `VL-VEND-DUPSVC-001` | Possible duplicate services | 3 | 3 |
| `VL-PERSONAL-001` | Possible personal expense or owner draw | 3 | 3 |
| `VL-COA-DUPACCT-001` | Duplicate account candidates | 6 | 2 |
| `VL-PERIOD-CLOSED-001` | Transactions dated in a closed period | 2 | 2 |
| `VL-REPORT-TIE-001` | Report tie-out mismatch | 12 | 3 |

Twenty-seven rules. Phase 1 ships exactly one, proven end to end.

**Note on `VL-DUP-EXP-002` and the slice (Q8, owner decision 2026-08):**
`VL-DUP-EXP-001` stays scoped to same-payment-account matches, deliberately
narrower than "any duplicate," because the value of the first slice is in being
narrow (§11). The cross-account case is real — paying the same bill from
checking and then again from a card happens — but it has a different
false-positive profile and belongs in its own rule, its own fixtures, and its
own tuning pass, not folded into the slice.
