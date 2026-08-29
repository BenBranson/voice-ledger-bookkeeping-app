import Foundation

/// docs/phase-0/08_RULE_ENGINE.md. Stable forever once assigned — see §8.8's
/// backlog table.
public struct RuleID: Hashable, Codable, Sendable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }
}

/// docs/phase-0/08_RULE_ENGINE.md §8.4.
public struct RuleVersion: Hashable, Codable, Comparable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public static func < (lhs: RuleVersion, rhs: RuleVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

/// docs/phase-0/08_RULE_ENGINE.md §8.2a. Which prior question a rule
/// answers — see that section for the full gating design. Only
/// `.categorization` rules are registered in this phase; no
/// `.relationship` rule exists yet (Part 3 of `NEXT_INSTRUCTION.md` was
/// design-only).
public enum RuleClass: String, Hashable, Codable, Sendable {
    case relationship
    case categorization
}

/// docs/VOICE_LEDGER_SPEC.md's 12-page workflow. Only the pages actually
/// built are modeled. `cleanupAssessment` isn't one of the 12 — it's the
/// backlog page from `docs/backlog/CLEANUP_MODE.md`, built ahead of the
/// remaining 11 per the handoff doc's own recommended sequence (§19:
/// "Cleanup Assessment... highest immediate business value").
public enum WorkflowPage: String, Hashable, Codable, Sendable {
    case page3Transactions
    case cleanupAssessment
    /// docs/VOICE_LEDGER_SPEC.md Page 4, Type B — needs an imported
    /// statement (Universal Ingestion Tier 1) to compare against posted
    /// QBO activity; there is no API substitute (spec: "Cannot see the
    /// 'For Review' queue... none of it is API-exposed").
    case bankFeedCleanup
}

public enum FindingCategory: String, Hashable, Codable, Sendable {
    case duplicateExpense
    /// `VL-CC-PAYMENT-001`, docs/backlog/CLEANUP_MODE.md §2.1.
    case creditCardPaymentMiscoded
    /// `VL-PAYROLL-LUMP-001`, docs/backlog/CLEANUP_MODE.md §2.2.
    case payrollLumpSum
    /// `VL-OBE-BALANCE-001`, docs/backlog/REDDIT_FEEDBACK_ASSESSMENT.md item B.
    case openingBalanceEquity
    /// `VL-BS-NEGBAL-001`, docs/phase-0/08_RULE_ENGINE.md §8.8 (page 8) —
    /// also explicitly listed in docs/backlog/CLEANUP_MODE.md §1's own
    /// Cleanup Assessment scope ("Balance sheet: ... are there negative assets").
    case negativeAssetOrLiabilityBalance
    /// `VL-DUP-VEND-001`, docs/phase-0/08_RULE_ENGINE.md §8.8 (page 3).
    case duplicateVendor
    /// `VL-CAT-UNCAT-001`, docs/phase-0/08_RULE_ENGINE.md §8.8 (page 3).
    case uncategorizedTransaction
    /// `VL-DUP-INV-001`, docs/phase-0/08_RULE_ENGINE.md §8.8. Distinct from
    /// `duplicateExpense`: a duplicate Invoice overstates revenue and
    /// accounts receivable, not expense.
    case duplicateInvoice
    /// `VL-DUP-PAY-001`, docs/phase-0/08_RULE_ENGINE.md §8.8.
    case duplicatePayment
    /// `VL-RECON-MISSING-001`, docs/phase-0/08_RULE_ENGINE.md §8.8 (pages 4, 5).
    case statementLineMissingPosting
    /// `VL-RECON-AMBIGUOUS-001` — Page 5's "identifies... duplicate items"
    /// half, distinct from `duplicateExpense` (which compares posted
    /// transactions to each other): this compares one imported statement
    /// line to the posted ledger and flags when it matches 2+ posted
    /// transactions equally well, so reconciliation can't tell which one
    /// it actually clears — a real ambiguity, not necessarily a real
    /// duplicate posting.
    case statementLineAmbiguousMatch
    /// `VL-VENDOR-MISMATCH-001`, docs/phase-0/08_RULE_ENGINE.md §8.8 (page 3).
    case vendorDescriptionMismatch
    /// `VL-BS-UNDEP-001`, docs/phase-0/08_RULE_ENGINE.md §8.8 (page 8).
    case agedUndepositedFunds
    /// `VL-VENDCREDIT-UNAPPLIED-001` — the vendor-refunds/vendor-credits
    /// cleanup workflow, added by explicit owner request 2026-08-17. Not
    /// in the original 27-rule backlog table; tracked directly here.
    case unappliedVendorCredit
    /// `VL-FORCED-RECON-001` — live-verified 2026-08-18 against a real
    /// forced reconciliation the owner performed in the sandbox UI.
    case forcedReconciliation
    /// `VL-REPORT-TIE-001` — Balance Sheet A/R or A/P not tying to Aged
    /// Receivables/Payables. Built 2026-08-18 once all four report parsers
    /// existed in the same session.
    case reportTieOut
    /// `VL-FEE-AVOIDABLE-001` — a keyword-matched late fee, overdraft, or
    /// finance charge.
    case avoidableFee
    /// `VL-PERIOD-CLOSED-001`, docs/phase-0/08_RULE_ENGINE.md §8.8's
    /// backlog table. A non-voided transaction dated on or before the
    /// period Voice Ledger's own local `PeriodLock` (Page 2) has been set
    /// through — never QBO's `BookCloseDate` (unread; see
    /// `MonthEndChecklist.swift`'s note).
    case transactionInLockedPeriod
    /// `VL-PERSONAL-001`, docs/phase-0/08_RULE_ENGINE.md §8.8's backlog
    /// table.
    case personalExpenseOrOwnerDraw
    /// `VL-VEND-ANOMALY-001`, docs/phase-0/08_RULE_ENGINE.md §8.8's backlog
    /// table. Scoped to same-period, same-vendor amount outliers — see
    /// `VendorAnomalyRule`'s doc comment for what's deliberately NOT
    /// covered ("unusual timing," "unusual name").
    case vendorAmountAnomaly
    /// `VL-CLOSED-PERIOD-DRIFT-001`, docs/phase-0/08_RULE_ENGINE.md §8.8's
    /// backlog table.
    case closedPeriodDrift
    /// `VL-VEND-PRICE-001`, docs/phase-0/08_RULE_ENGINE.md §8.8's backlog
    /// table. Also covers `VL-SUB-INCREASE-001` — see
    /// `VendorPriceIncreaseRule`'s doc comment for why that's one rule, not
    /// two.
    case vendorPriceIncrease
}

/// docs/phase-0/04_DATA_MODEL.md §4.12 — declares a rule's QBO-specific
/// data needs so the engine's requirement check (§8.5 step 1) is mechanical.
public struct SourceDependency: Hashable, Codable, Sendable {
    public let entity: QBOEntityKind
    public init(entity: QBOEntityKind) { self.entity = entity }
}

public struct RuleIdentity: Hashable, Codable, Sendable {
    public let id: RuleID
    public let version: RuleVersion
    public let title: String
    public let category: FindingCategory
    public let ruleClass: RuleClass
    public let page: WorkflowPage
    public let accountingPrinciple: String
    public let sourceDependencies: Set<SourceDependency>

    public init(
        id: RuleID,
        version: RuleVersion,
        title: String,
        category: FindingCategory,
        ruleClass: RuleClass,
        page: WorkflowPage,
        accountingPrinciple: String,
        sourceDependencies: Set<SourceDependency>
    ) {
        self.id = id
        self.version = version
        self.title = title
        self.category = category
        self.ruleClass = ruleClass
        self.page = page
        self.accountingPrinciple = accountingPrinciple
        self.sourceDependencies = sourceDependencies
    }
}

public struct DataRequirements: Sendable {
    public let entities: Set<QBOEntityKind>
    public let requiredCoverage: Coverage

    public init(entities: Set<QBOEntityKind>, requiredCoverage: Coverage) {
        self.entities = entities
        self.requiredCoverage = requiredCoverage
    }
}

/// docs/phase-0/08_RULE_ENGINE.md §8.1. Not exhaustive — only the reasons
/// this slice's paths can actually produce.
public enum MissingRequirement: Hashable, Sendable {
    case partialCoverage(reason: String)
}

/// docs/phase-0/08_RULE_ENGINE.md §8.1, decision D1. The three-outcome type
/// that makes "nothing found" and "couldn't check" impossible to collapse.
public enum RuleOutcome: Sendable {
    case pass(coverage: Coverage, checkedCount: Int)
    case findings([Finding])
    case cannotEvaluate(MissingRequirement)
}

extension RuleOutcome {
    var isNonEmptyFindings: Bool {
        if case .findings(let f) = self { return !f.isEmpty }
        return false
    }
}

/// docs/phase-0/08_RULE_ENGINE.md §8.6. Deterministic code determines
/// materiality — never Claude.
public struct MaterialityPolicy: Hashable, Codable, Sendable {
    public let absoluteFloor: Money

    public init(absoluteFloor: Money) {
        self.absoluteFloor = absoluteFloor
    }

    /// docs/phase-0/08_RULE_ENGINE.md §8.6 — owner decision 2026-08.
    public static let defaultPolicy = MaterialityPolicy(absoluteFloor: Money(minorUnits: 2_500, currency: .usd))
}

/// docs/phase-0/08_RULE_ENGINE.md §8.2: "context carries no I/O." Holds only
/// values, never handles — a rule physically cannot call the network or
/// read the clock through it, which is what makes `evaluate` reproducible.
public struct RuleContext: Sendable {
    public let period: AccountingPeriod
    public let materiality: MaterialityPolicy
    public let companyFacts: CompanyFacts
    public let dismissedFindingIDs: Set<String>
    /// §8.2a's relationship-before-category gating, per transaction (see
    /// `RuleEngineActor.swift`'s doc comment on why this is scoped to
    /// individual transactions rather than whole rules). A categorization
    /// rule checks `gatedTransactionIDs.contains(transaction.id)` and skips
    /// that transaction — it does not skip itself entirely. Empty for
    /// relationship-class rules, which always see the ungated context.
    public let gatedTransactionIDs: Set<String>
    /// "Today," for a rule that needs to measure age (e.g.
    /// `VL-BS-UNDEP-001`'s days-since-payment check) rather than compare
    /// two stored dates. Defaults to the real current date — passed
    /// explicitly by test callers so aging math stays deterministic and
    /// testable rather than depending on when the test happens to run.
    public let asOfDate: AccountingDate
    /// docs/VOICE_LEDGER_SPEC.md Page 2 — Voice Ledger's own local period
    /// lock (`Core/PeriodLock.swift`), not QBO data. `nil` when the
    /// bookkeeper has never set one for this realm. `VL-PERIOD-CLOSED-001`
    /// is the only rule that reads this; every other rule ignores it.
    public let periodLock: PeriodLock?
    /// Trial Balance snapshot captured the moment `periodLock` was set
    /// (`Core/PeriodLock.swift`'s `PeriodLockSnapshot`) — `nil` when no lock
    /// has been set, or when the lock predates this feature (an old lock
    /// with no snapshot on disk). `VL-CLOSED-PERIOD-DRIFT-001` is the only
    /// rule that reads this.
    public let periodLockSnapshot: PeriodLockSnapshot?

    public init(
        period: AccountingPeriod,
        materiality: MaterialityPolicy,
        companyFacts: CompanyFacts,
        dismissedFindingIDs: Set<String> = [],
        gatedTransactionIDs: Set<String> = [],
        asOfDate: AccountingDate = AccountingDate(date: Date()),
        periodLock: PeriodLock? = nil,
        periodLockSnapshot: PeriodLockSnapshot? = nil
    ) {
        self.period = period
        self.materiality = materiality
        self.companyFacts = companyFacts
        self.dismissedFindingIDs = dismissedFindingIDs
        self.gatedTransactionIDs = gatedTransactionIDs
        self.asOfDate = asOfDate
        self.periodLock = periodLock
        self.periodLockSnapshot = periodLockSnapshot
    }

    /// Returns a copy with `gatedTransactionIDs` replaced — used by
    /// `RuleEngine.evaluate` to hand categorization rules the set collected
    /// from relationship-rule findings, without relationship rules ever
    /// seeing it themselves.
    ///
    /// **Known gap, found and verified 2026-08-23 (Gauntlet Loop hardening
    /// pass on `VL-DUP-EXP-001`), documented rather than fixed here — this
    /// method touches shared engine code used by every rule, outside that
    /// pass's scope.** This constructor call does not pass `asOfDate:`
    /// through, so it silently resets to the initializer's default
    /// ("today," via `Date()`) instead of preserving whatever the caller
    /// originally supplied. **Confirmed NOT live today**: no production call
    /// site (`AppState.syncAndEvaluate()`, the devtool) ever supplies a
    /// non-default `asOfDate` — only tests do, and rule-level tests call a
    /// `Rule.evaluate` directly, never through `RuleEngine.evaluate`'s
    /// gating path that calls this method. Would matter the moment an
    /// age-based categorization rule (e.g. `VL-BS-UNDEP-001`, which reads
    /// `context.asOfDate`) is ever tested end-to-end through the full engine
    /// with a fixed test date. Fix, when needed: add `asOfDate: asOfDate` to
    /// the constructor call below.
    public func gatingTransactions(_ ids: Set<String>) -> RuleContext {
        RuleContext(
            period: period,
            materiality: materiality,
            companyFacts: companyFacts,
            dismissedFindingIDs: dismissedFindingIDs,
            gatedTransactionIDs: ids
        )
    }
}

/// docs/phase-0/08_RULE_ENGINE.md §8.2b. A detection tier within a rule.
public struct RuleTier: Hashable, Codable, Sendable {
    public let id: String
    public let label: String
    public let confidence: Confidence

    public init(id: String, label: String, confidence: Confidence) {
        self.id = id
        self.label = label
        self.confidence = confidence
    }
}

public struct TierStatus: Hashable, Codable, Sendable {
    public let tier: RuleTier
    public let active: Bool
    public let reason: String

    public init(tier: RuleTier, active: Bool, reason: String) {
        self.tier = tier
        self.active = active
        self.reason = reason
    }
}

/// docs/phase-0/08_RULE_ENGINE.md §8.2. Implementation note: the spec sketches
/// `evaluate` as an instance method on an `associatedtype`-generic protocol.
/// This slice implements it as static functions on a type instead — same
/// purity contract (no I/O, no clock, no randomness; same input, same
/// output, forever), simpler to register and call from a homogeneous
/// `[any Rule.Type]` registry without existential associated-type gymnastics.
/// Revisit if a later rule genuinely needs per-instance state.
public protocol Rule: Sendable {
    static var identity: RuleIdentity { get }
    static var requirements: DataRequirements { get }
    static func evaluate(_ input: NormalizedDataSet, context: RuleContext) -> RuleOutcome
}

/// docs/phase-0/08_RULE_ENGINE.md §8.2b. General capability — any rule with
/// more than one detection tier conforms. Read by Training Mode (not built
/// this phase) and by the engine's fixture tests; never consulted by the
/// engine when deciding evaluability (informational only, per the owner's
/// explicit instruction).
public protocol MultiTierRule: Rule {
    static func tierApplicability(context: RuleContext) -> [TierStatus]
}
