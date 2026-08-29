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

**Known landmine, found and verified 2026-08-23 (Gauntlet Loop hardening
pass on `VL-DUP-EXP-001`), not yet fixed — documented here rather than
fixed speculatively, per this doc's own discipline of not guessing ahead
of real need.** The actually-shipped gating set (`RuleEngineActor.swift`'s
`gatedTransactionIDs`, and `RuleContext.gatedTransactionIDs`) is a bare
`Set<String>` of raw QBO `Id` values, with **no entity-kind tag** — a
simplification from this section's illustrative `Set<RuleID>`-per-rule
sketch above, made when the first (and so far only) relationship rule,
`VL-CC-PAYMENT-001`, was actually built. QBO's `Id` is unique only *within
one entity type* (a `Purchase` #12 and a `Bill` #12 can both legitimately
exist), so once a SECOND relationship-class rule is added that gates a
non-`Purchase` entity kind, a categorization rule for a *different* entity
kind with a numerically-colliding `Id` would be wrongly gated — a silent
false negative, with a misleading `GatingOutcome` audit entry attributing
the exclusion to the wrong entity.

**Confirmed NOT live today**: `VL-CC-PAYMENT-001`
(`CreditCardPaymentMiscodedRule.swift`) is the only `ruleClass:
.relationship` rule that exists, and its own `evaluate()` filters strictly
to `entityKind == .purchase` — it can only ever insert genuine `Purchase`
IDs into the gate set, and QBO guarantees those are unique among
themselves. Every one of the 8 current consumers
(`DuplicatePostedExpenseRule`, `CrossAccountDuplicateExpenseRule`,
`DuplicateBillRule`, `DuplicateInvoiceRule`, `DuplicatePaymentRule`,
`VendorDescriptionMismatchRule`, `UncategorizedTransactionRule`,
`PayrollLumpSumRule`) does the identical entity-kind-blind
`gatedTransactionIDs.contains(id)` check — all verified live during this
pass, not assumed.

**Fix, when needed** (not built now): change the gate set's element type
to carry entity kind alongside the raw id (e.g. a `Hashable` key of
`(entityKind: QBOEntityKind, id: String)`), update the 8 consumer call
sites to check the tagged key instead of the bare string, and add a
regression test to `RuleEngineGatingTests.swift` proving two different
entity kinds with numerically-identical ids don't collide. Do this
**when the next relationship-class rule touching a non-`Purchase` entity
is actually built** — fixing it now, against a hypothetical shape, risks
guessing wrong about what that rule will actually need; fixing it then
means verifying against the real thing, matching this whole document's
own stated preference throughout.

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
| `VL-DUP-EXP-002` | **IMPLEMENTED 2026-08-17** (`desktop/Sources/Core/CrossAccountDuplicateExpenseRule.swift`) — cross-account duplicate candidate: same vendor/amount, different payment account, within 3 days. Single tier, `.medium` confidence always (never reaches `.high` — cross-account matches are more often coincidence than VL-DUP-EXP-001's same-account case). Required a `PaymentType` fix in the seed harness (`spike/seed.ts`): posting a Purchase against a Credit Card-type `AccountRef` with `PaymentType: "Check"` fails outright with QBO fault 6430 ("Invalid account type used") — needs `PaymentType: "CreditCard"` to match the account type. Live-verified against a real seeded pair (Purchase #217 from Checking, #218 from the Amex card, both $315.00, 2 days apart). | 3 | **Built** |
| `VL-DUP-BILL-001` | **IMPLEMENTED 2026-08-17** (`desktop/Sources/Core/DuplicateBillRule.swift`) — duplicate bills, single exact-match tier (vendor + date + amount), deliberately narrower than `VL-DUP-EXP-001` (no DocNumber tier — Bill's DocNumber-uniqueness behavior unverified; no near-date tier — not added speculatively). Required the second new backend catalog operation this session (`readBills`, matrix row 13.5). `Bill` normalizes into the same `LedgerTransaction` shape as `Purchase`. Live-verified against a real seeded duplicate-bill pair. | Cleanup Assessment | **Built** |
| `VL-DUP-INV-001` | **IMPLEMENTED 2026-08-17** (`desktop/Sources/Core/DuplicateInvoiceRule.swift`) — the sales-side counterpart to `VL-DUP-BILL-001`: same customer/date/amount, single exact-match tier, no DocNumber or near-date tier (same unverified-assumption caution as Bill). Required a **third new backend catalog operation** (`readInvoices`, matrix row 13.6) plus a new `QBOEntityKind.invoice` case (`LedgerTransaction.vendorName` reused for the customer name — see its doc comment). `spike/seed.ts` gained `ensureCustomer`/`ensureItem` (both look up EXISTING sandbox records only — Voice Ledger has no customer/item creation path) and `ensureInvoice`; fixed a live-found bug along the way (QBO's query language needs a literal single quote doubled, not left bare — broke looking up "Amy's Bird Sanctuary" until fixed). Live-verified against a real seeded duplicate-invoice pair (#220/#221, $500.00 each). | Cleanup Assessment | **Built** |
| `VL-DUP-PAY-001` | **IMPLEMENTED 2026-08-17** (`desktop/Sources/Core/DuplicatePaymentRule.swift`) — the customer-payment counterpart to `VL-DUP-INV-001`: same customer/date/amount, single exact-match tier. Required a **fourth new backend catalog operation** (`readPayments`, matrix row 13.7) and a new `QBOEntityKind.payment` case. `.medium` confidence, not `.high` like the other exact-match duplicate rules — Payment has no `DocNumber` field to fall back on and no verified void signal (checked live: no `status` field observed on any real Payment, unlike Purchase/Bill/Invoice). `spike/seed.ts` gained `ensurePayment` — idempotent via manifest tracking alone, since Payment has no `PrivateNote` field to query against either (verified live, not assumed). Live-verified against a real seeded duplicate-payment pair (#222/#223, $400.00 each). | Cleanup Assessment | **Built** |
| `VL-DUP-VEND-001` | **IMPLEMENTED 2026-08-17** (`desktop/Sources/Core/DuplicateVendorRule.swift`) — duplicate vendor records, matched by normalized-EXACT name (case/punctuation/whitespace/common-suffix stripped), deliberately not fuzzy — see the rule's own doc comment for why, after `VL-COA-DUPACCT-001`'s false-positive finding (below in this same table). Required adding the first new backend catalog operation since Phase 1 step 1.2 (`readVendors`, matrix row 13.4). Live-verified against a real seeded near-duplicate pair. | Cleanup Assessment | **Built** |
| `VL-RECON-DIFF-001` | Bank/CC reconciliation differences. **Built 2026-08-28** (`desktop/Sources/Core/BankReconciliationDriftRule.swift`) — compares an imported OFX statement's stated `<LEDGERBAL>` ending balance against QBO's `Account.CurrentBalance` for the same account, flagging a gap that clears BOTH a flat $25 floor and a 2% relative threshold (a small gap on a large balance is plausibly just between-dates activity, not a real problem). No new capability needed: `currentBalance` was already fetched every sync, and the statement's ending balance was already being extracted by `OFXBankStatementImporter` — it was just shown to the user and discarded on confirm, never persisted or compared. `AppState.confirmOFXImport` now saves a `BankStatementReconciliationSnapshot` per account. Known, disclosed imprecision: `currentBalance` is as-of-now, the statement is as-of-its-own-date, so some drift can be genuine later activity, not an error — the rule's own guided procedure says so rather than overclaiming precision. | 5 | **Built** |
| `VL-RECON-MISSING-001` | **IMPLEMENTED 2026-08-17** (`desktop/Sources/Core/BankFeedMissingPostingRule.swift`) — the first rule to consume Universal Ingestion Tier 1's output: an imported statement line (`entityKind == .importedBankStatementLine`) with no matching posted `Purchase`/`Bill` on the same account (amount exact, within a 5-day window) is flagged, never auto-created (spec's own safety rule for this exact page — a bank-feed item could get added twice). Two honest states: zero statement lines at all (no import happened) is `.cannotEvaluate`, never a silent `.pass`. `BankStatementCSVImporter` gained a `statementAccountID` parameter so an imported line's `paymentAccountID` is comparable to a posted transaction's. **The import UI shipped the same day**: `.fileImporter` + `ImportBankStatementView`'s confirm-and-correct column mapping (docs/phase-0/09_INGESTION_PIPELINE.md §9.4) + `ClientStore` persistence, so this rule can now actually fire against a real file, not just prove its own logic. Not visually verified (no macOS-window screenshot tool available in this session) — verified by 139/139 tests passing and the app launching cleanly with the new UI wired in. | 4, 5 | **Built** |
| `VL-CAT-UNCAT-001` | **IMPLEMENTED 2026-08-17** (`desktop/Sources/Core/UncategorizedTransactionRule.swift`) — Purchase/Bill line-coded to QBO's own default catch-all account ("Uncategorized Expense"/"Uncategorized Income"/"Uncategorized Asset", confirmed live present in this sandbox as Ids 31/30/32). Matches on exact account `Name` — deliberately safe here (unlike `VL-COA-DUPACCT-001`'s naive name-matching, these are QBO's own reserved system names, not user-chosen data) since none of the three accounts' `AccountSubType`s (`OtherMiscellaneousServiceCost` / `ServiceFeeIncome` / `OtherCurrentAssets`) is exclusive enough to use as the structural signal the way `OpeningBalanceEquity` is. Live-verified against a real seeded Purchase (#219, $120.00). | 3 | **Built** |
| `VL-CAT-MISCODE-001` | Probable miscoding vs. vendor history | 3 | 3 |
| `VL-VEND-ANOMALY-001` | Unusual vendor name, amount, or timing | 3 | 3 |
| `VL-BS-NEGBAL-001` | **IMPLEMENTED 2026-08-17** (`desktop/Sources/Core/NegativeBalanceRule.swift`) — negative CurrentBalance on an Asset or Liability-classified account. Live-verified: 6 real accounts in the sandbox currently trip it. | 8 | **Built** |
| `VL-BS-CLEARING-001` | Stale or abnormal clearing accounts. Not attempted 2026-08-17 — needs per-account last-activity-date, which isn't on the Account entity itself; would need transaction-level cross-referencing across entity types not yet in the catalog. | 8 | 2 |
| `VL-BS-UNDEP-001` | **IMPLEMENTED 2026-08-17, later the same day** (`desktop/Sources/Core/UndepositedFundsAgingRule.swift`) — the "not attempted" note above went stale within the same day once `readPayments` shipped for `VL-DUP-PAY-001`. Required a **fifth new catalog operation** (`readDeposits`, matrix row TBD) specifically to avoid the false-positive risk the original note worried about: `Deposit.Line[].LinkedTxn[]` (`TxnType == "Payment"`) is checked FIRST to exclude any Payment already swept into a real deposit, no matter how old its own `TxnDate`. Live-verified this exclusion against real data — Payment #116 (Jan 21) sits 204+ days old but was swept by Deposit #121 (Jan 25) and correctly does NOT appear in the findings, while Payments #128/#120 (also January, genuinely never deposited) do. Also live-verified the positive case: Payments #222/#223 ($400 each, seeded 2026-07-27 for `VL-DUP-PAY-001`, never deposited) flagged at 21 days aged. Required a new `RuleContext.asOfDate` field (defaults to real "now," explicit in tests) since this is the first rule that measures age against today rather than comparing two stored dates. | 8 | **Built** |
| `VL-BS-SUSPENSE-001` | Suspense account activity. **Checked live 2026-08-17, not buildable as safely as `VL-OBE-BALANCE-001`:** unlike Opening Balance Equity, QBO has no system `AccountSubType` for a "suspense" account — detection would mean matching on account *name* alone, which the `VL-COA-DUPACCT-001` investigation below just proved unreliable in this exact sandbox. No suspense-named account exists here to test against either way. Left as backlog rather than shipped on an unverified heuristic. | 8 | 2 |
| `VL-BS-LOAN-001` | Loan balance inconsistencies | 8 | 3 |
| `VL-BS-EQUITY-001` | Equity postings needing review | 8 | 3 |
| `VL-BS-DRCR-001` | Debit/credit pattern vs. account expectation | 8 | 3 |
| `VL-SUB-INCREASE-001` | Recurring subscription increased. **Covered by `VL-VEND-PRICE-001`, not built as a separate rule — see that rule's own doc comment.** Both describe the same computable fact (a vendor charging more per transaction at a stable count than last period); shipping two `Rule` types for one fact would mean two rule IDs on the same evidence, which is worse than one. | 3 | **Covered by VL-VEND-PRICE-001** |
| `VL-SUB-UNUSED-001` | Recurring subscription appears unused. **Investigated 2026-08-28, not built.** "Unused" is a usage-data question (is the service actually being logged into/consumed) that QBO's Purchase data has no signal for at all — only that the vendor is still being charged, which is the normal state of an active subscription, not evidence of anything wrong. No honest detection exists from financial postings alone. Left as backlog, same posture as `VL-BS-SUSPENSE-001`/`VL-COA-DUPACCT-001`. | 3 | 2 |
| `VL-FEE-AVOIDABLE-001` | Late fees, overdrafts, avoidable interest. **Built 2026-08-18** (`desktop/Sources/Core/AvoidableFeeRule.swift`) — same keyword-matching pattern as `VL-PAYROLL-LUMP-001`, checking vendor name AND memo (both already synced, no new capability needed) for specific fee terms ("overdraft", "nsf", "late fee", "finance charge", etc. — deliberately not the bare word "fee" alone, which would false-positive on a legitimate vendor like "ABC Filing Fee Services"). **No live positive example exists in this sandbox** (checked against the real July data — none of the 24 transactions are fee-shaped); shipped on unit tests alone, honestly documented as such rather than claimed live-verified. | 3 | **Built** |
| `VL-VEND-PRICE-001` | Vendor price increases. **Built 2026-08-28** (`desktop/Sources/Core/VendorPriceIncreaseRule.swift`) — for a vendor with the SAME transaction count this period as last (a stable cadence, ruling out "we just bought more"), flags a per-transaction average amount increase of 15%+. Needed a new independent-fetch capability, `QBOSyncClient.fetchPurchases(realmID:period:)` (Purchases-only, one period, reusing the already-verified `readPurchases` operation against last month's date range — no new backend catalog operation). Also covers `VL-SUB-INCREASE-001` under this one rule ID — see the rule's own doc comment for why. | 3 | **Built** |
| `VL-VEND-DUPSVC-001` | Possible duplicate services | 3 | 3 |
| `VL-PERSONAL-001` | Possible personal expense or owner draw | 3 | 3 |
| `VL-COA-DUPACCT-001` | Duplicate account candidates. **Investigated live 2026-08-17, not built.** Naive matching on account `Name` alone produces systematic false positives: this sandbox has 8 pairs of identically-named accounts (`Decks and Patios`, `Job Materials`, `Equipment Rental`, etc.) that are QBO's own industry-template pattern — the same leaf name legitimately used for both an Income and a matching COGS/Expense sub-account under different parents, for job costing. A safe version needs to match on `FullyQualifiedName` (or genuine near-duplicate fuzzy matching), not leaf `Name` — and this sandbox has zero real duplicate-account examples under that stricter, correct definition, so there's no live positive case to verify against yet either. Left as backlog with the false-positive risk documented rather than shipped on the naive approach. | 6 | 2 |
| `VL-PERIOD-CLOSED-001` | Transactions dated in a closed period | 2 | 2 |
| `VL-REPORT-TIE-001` | Report tie-out mismatch. **Built and live-verified 2026-08-18** (`desktop/Sources/Core/ReportTieOutRule.swift`), once Balance Sheet, Aged Receivables, and Aged Payables were all available in the same `NormalizedDataSet` in the same session. Checks Balance Sheet A/R against Aged Receivables' grand total, and A/P against Aged Payables', independently — matched by real account data (`accountType == .accountsReceivable`/`.accountsPayable`), not a guessed literal label, so a renamed account still matches correctly. Live-verified against the real sandbox: A/R ties out exactly (`.pass`), A/P is off by a real $110.00 (a genuine finding, not a bug — confirmed by A/R NOT also firing, ruling out a systematic sign/currency error). | 12 | **Built** |
| `VL-VENDCREDIT-UNAPPLIED-001` | **IMPLEMENTED 2026-08-17**, by explicit owner request ("knock out the vendor-refunds workflow") — not part of the original 27-rule backlog, added here directly (`desktop/Sources/Core/UnappliedVendorCreditRule.swift`). Flags a `VendorCredit` whose `Balance` (QBO's own "still unapplied" field, verified live against a real created VendorCredit before this was built) is nonzero more than 30 days after its own date — a credit sitting unused, easy to forget since QBO surfaces no reminder on its own. Required a **sixth new catalog operation** (`readVendorCredits`) and a new `LedgerVendorCredit` Core type (distinct from `LedgerTransaction` — needs `balance` alongside `totalAmount`, a distinction no other entity needs). Reuses `RuleContext.asOfDate` from `VL-BS-UNDEP-001`. Live-verified: a real seeded VendorCredit (#225, $75.00, dated 2026-06-01) flags at 77 days aged. | Cleanup Assessment | **Built** |

Twenty-seven backlog rules, plus one owner-requested addition beyond the
original list. Phase 1 shipped one, proven end to end (§11). Three more
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
| `VL-CC-PAYMENT-001` | **IMPLEMENTED 2026-08-17** (`desktop/Sources/Core/CreditCardPaymentMiscodedRule.swift`). Credit-card payment coded to an expense account instead of the card's balance-sheet liability account. Built as `RuleClass.relationship` — the first real (non-fixture) conformer to §8.2a's gating. `.high` confidence when the vendor name structurally matches a real Credit-Card-type account in the client's chart of accounts, `.medium` on keyword match alone. Live-verified against the sandbox. **The first (and so far only) rule to close the full detect -> draft -> review -> push loop**: for the `.high`-confidence structural-match case with exactly one line and a resolvable `SyncToken`, `resolution` is `.stagedAPI` with `apiWriteDetails` populated, and `FindingDetailView`'s "Apply Fix" button calls `updatePurchaseLineAccount` end to end. Live-verified: real seeded finding (purchase #211) applied and QBO-confirmed `verified: true`, finding resolves to `PASS` on resync. The keyword-match and multi-line/no-SyncToken cases still fall back to `.manualQBO` — never a guessed target account. | Cleanup Assessment | **Built** |
| `VL-PAYROLL-LUMP-001` | **IMPLEMENTED 2026-08-17** (`desktop/Sources/Core/PayrollLumpSumRule.swift`). Payment to a known payroll processor (ADP, Gusto, Paychex, Rippling, QuickBooks Payroll, Justworks, TriNet) coded entirely to one expense account. Resolution is guided-manual (needs the payroll register — cannot compute the correct split without it). Live-verified. | Cleanup Assessment | **Built** |
| `VL-VENDOR-MISMATCH-001` | **IMPLEMENTED 2026-08-17, live-verified 2026-08-17/18** (`desktop/Sources/Core/VendorDescriptionMismatchRule.swift`) — the "not buildable without the Import Bridge" note was stale; Universal Ingestion Tier 1 now exists. Reuses `VL-RECON-MISSING-001`'s exact statement-to-posted matching (same account/amount/near-date), but for the opposite case: a statement line WITH a match, where the raw bank description and QBO's vendor name share zero normalized word in common. Deliberately conservative — a single shared word (even "amex" in "AMEX EPAYMENT 8827" vs "VL Spike Amex") stays silent, same lesson as `VL-DUP-VEND-001`/`VL-COA-DUPACCT-001`'s false-positive finding about fuzzy matching. `.medium` confidence, guided-manual review only (never auto-corrects the vendor). **Live-verified** by adding a new `voiceledger-devtool csv-import-check` command that runs the REAL `CSVParser` -> `BankStatementCSVImporter` -> `ClientStore` -> `RuleEngine` pipeline (the exact code path `AppState.confirmCSVImport` uses) against a real one-line CSV ("ACH DEBIT ONLINE XFER 4471", $315.00, 07/23/2026) matched to real posted purchase #217 ("VL Spike Permian Supply, Inc.", $315.00, 2026-07-22, same account) — the rule correctly fired at `.medium` confidence, and `VL-RECON-MISSING-001` correctly stayed `PASS` on the same data (a match WAS found, just a suspicious one). | 3 | **Built** |
| `VL-PREPAID-PERIOD-001` | Large payment where an attached document's service period extends past the transaction date (needs OCR on the attachment). Not buildable without the Import Bridge. | 3 | Backlog |
| `VL-OPENING-BAL-001` | **DISPROVEN as originally scoped, 2026-08-17.** Was going to read a non-zero opening-balance entry plus a nearby equity contribution. Checked against the live sandbox first: `Account.OpeningBalance`/`OpeningBalanceDate` are write-only on create — QBO never returns them on any subsequent read, so there is no field to detect this from. See `VL-OBE-BALANCE-001` below for the buildable alternative that replaced this plan. | 6 | Disproven, not building as scoped |
| `VL-CLOSED-PERIOD-DRIFT-001` | A closed period's stored trial-balance snapshot/hash no longer matches on resync — someone (client, prior bookkeeper, QBO auto-categorization) edited a closed-period transaction. No audit-log dependency; needs no API QBO doesn't already expose. | 2 | Backlog |
| `VL-FORCED-RECON-001` | Non-zero balance in Reconciliation Discrepancies — someone forced a reconciliation to close rather than finding the cause. **Built and live-verified 2026-08-18.** The owner performed a real forced reconciliation in the sandbox UI (Checking, statement ending balance deliberately set to $1.00, "Add adjustment and finish" taken over a $4,264.76 difference). Two detection paths were tried against the live API and disproven first: `Account.CurrentBalance` on the resulting "Reconciliation Discrepancies" account read `0` (not meaningful for Expense-classified accounts), and no `JournalEntry` was created for the adjustment. **The only place the API surfaces it is the Profit & Loss report** — an "Other Expenses" line literally named "Reconciliation Discrepancies" carrying the real amount. The rule reads exactly that (`ForcedReconciliationRule.swift`); `NormalizedDataSet` gained a `profitAndLossLines` field and `QBOEntityKind` a `.report` case to support it. Confirmed firing correctly (`$4,264.76`, high confidence) via `voiceledger-devtool sync-check` against the real sandbox. | 5 | Shipped |
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
