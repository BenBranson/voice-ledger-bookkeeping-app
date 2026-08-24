import Foundation
import CryptoKit

/// docs/phase-0/05_FINDING_SCHEMA.md. How sure a rule is that its match
/// criteria fired — independent of `Severity` (§8.6: severity is a function
/// of dollar exposure, confidence is a function of match tier).
public enum Confidence: String, Hashable, Codable, Sendable, Comparable {
    case low, medium, high

    private var rank: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }

    public static func < (lhs: Confidence, rhs: Confidence) -> Bool { lhs.rank < rhs.rank }
}

/// docs/phase-0/05_FINDING_SCHEMA.md, §5.7's color derivation, §8.6.
public enum Severity: String, Hashable, Codable, Sendable, Comparable {
    case low, high

    private var rank: Int {
        switch self {
        case .low: return 0
        case .high: return 1
        }
    }

    public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rank < rhs.rank }

    /// docs/phase-0/08_RULE_ENGINE.md §8.6: deterministic code determines
    /// materiality, never Claude (`CLAUDE.md` rule 1). Simplified to a
    /// single floor comparison for this slice's one rule — the doc's
    /// `.medium` banding (percent-of-revenue, account overrides) is real
    /// but not yet exercised by any rule in Phase 1, so it is not modeled
    /// here rather than guessed at.
    public static func derive(dollarExposure: Money, materiality: MaterialityPolicy) -> Severity {
        dollarExposure >= materiality.absoluteFloor ? .high : .low
    }
}

public struct EvidenceItem: Hashable, Codable, Sendable {
    public let transactionID: String
    public let highlightedFields: [String]
    /// Gauntlet Loop, Gauntlet B (2026-08-23): the ACTUAL value for each
    /// name in `highlightedFields`, captured by the rule at detection time
    /// — "amount, date, paymentAccount" tells a bookkeeper which fields
    /// matched but not what they matched to, forcing a trip to QBO just to
    /// see the numbers. Deliberately captured here rather than looked up
    /// live by the view: `Finding` is persisted to `findings.json` and
    /// reloaded after an app restart with no live transaction data around
    /// (`AppState` keeps no queryable transaction cache after sync), so a
    /// live-lookup-based UI would silently show blank evidence for any
    /// finding loaded outside the sync that produced it. Additive with an
    /// empty default — every existing `EvidenceItem(...)` call site across
    /// the other 16 rules is unaffected and simply renders field names only
    /// until each is given the same treatment.
    public let fieldValues: [String: String]

    public init(transactionID: String, highlightedFields: [String], fieldValues: [String: String] = [:]) {
        self.transactionID = transactionID
        self.highlightedFields = highlightedFields
        self.fieldValues = fieldValues
    }
}

/// docs/phase-0/10_STAGING_APPROVAL_AUDIT.md §10.2's `ApprovalRecord`
/// eventually attaches here; this slice only needs the resolution-kind tag,
/// since Branch B (docs/phase-0/11_VERTICAL_SLICE.md §11.1) never stages an
/// API write.
public enum ResolutionKind: String, Hashable, Codable, Sendable {
    case manualQBO = "manual_qbo"
    case stagedAPI = "staged_api"
}

public struct GuidedProcedure: Hashable, Codable, Sendable {
    public let steps: [String]
    public let pitfalls: [String]
    public let doneCriteria: String

    public init(steps: [String], pitfalls: [String], doneCriteria: String) {
        self.steps = steps
        self.pitfalls = pitfalls
        self.doneCriteria = doneCriteria
    }
}

public enum Consequence: Hashable, Codable, Sendable {
    case reconciliation(String)
    case reporting(String)
    case auditTrail(String)
}

public enum ReversalPlan: Hashable, Codable, Sendable {
    case reversibleManually(procedure: String)
    case irreversible
}

/// The concrete parameters for `updatePurchaseLineAccount`, attached to a
/// `ProposedAction` whose `resolution == .stagedAPI`. A rule populates this
/// only when it can identify the fix unambiguously — see
/// `CreditCardPaymentMiscodedRule`'s doc comment on when it does and
/// doesn't. This is the "draft" in CLAUDE.md rule 2's "detect -> draft ->
/// review -> push" — the UI still requires an explicit human confirmation
/// (and the realm must be in Write-Enabled mode) before anything is sent.
public struct StagedAPIWriteDetails: Hashable, Codable, Sendable {
    public let purchaseID: String
    public let lineID: String
    public let expectedSyncToken: String
    public let currentAccountID: String
    public let currentAccountName: String
    public let suggestedAccountID: String
    public let suggestedAccountName: String

    public init(
        purchaseID: String,
        lineID: String,
        expectedSyncToken: String,
        currentAccountID: String,
        currentAccountName: String,
        suggestedAccountID: String,
        suggestedAccountName: String
    ) {
        self.purchaseID = purchaseID
        self.lineID = lineID
        self.expectedSyncToken = expectedSyncToken
        self.currentAccountID = currentAccountID
        self.currentAccountName = currentAccountName
        self.suggestedAccountID = suggestedAccountID
        self.suggestedAccountName = suggestedAccountName
    }
}

public struct ProposedAction: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let title: String
    public let resolution: ResolutionKind
    public let guidedProcedure: GuidedProcedure?
    public let consequences: [Consequence]
    public let reversal: ReversalPlan
    public let apiWriteDetails: StagedAPIWriteDetails?

    public init(
        id: String,
        title: String,
        resolution: ResolutionKind,
        guidedProcedure: GuidedProcedure?,
        consequences: [Consequence],
        reversal: ReversalPlan,
        apiWriteDetails: StagedAPIWriteDetails? = nil
    ) {
        self.id = id
        self.title = title
        self.resolution = resolution
        self.guidedProcedure = guidedProcedure
        self.consequences = consequences
        self.reversal = reversal
        self.apiWriteDetails = apiWriteDetails
    }
}

public enum FindingStatus: String, Hashable, Codable, Sendable {
    case open
    case resolved
    case dismissed
}

public struct Finding: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let ruleID: RuleID
    public let ruleVersion: RuleVersion
    public let realmID: RealmID
    public let period: AccountingPeriod
    public let title: String
    public let severity: Severity
    public let confidence: Confidence
    public let dollarExposure: Money
    public let evidence: [EvidenceItem]
    public let proposedActions: [ProposedAction]
    public let provenance: [Provenance]
    public var status: FindingStatus
    /// The vendor/payee this finding is about, when the rule that produced
    /// it clearly has one — additive (`Codable` default via the init's
    /// default value, same pattern as `LedgerTransaction.lines`/`syncToken`
    /// earlier this project) so every existing rule's `Finding(...)` call
    /// needed zero changes. Feeds `ClientMemoryRule` matching — a rule with
    /// no single clear vendor (e.g. a Balance Sheet check) leaves this
    /// `nil`, and `ClientMemoryRule` correctly never matches a `nil`.
    public let vendorName: String?
    /// Gauntlet Loop, Gauntlet B (2026-08-23): a deterministic, Core-computed
    /// plain-English sentence stating what was found — "Two purchases from
    /// Permian Supply for $486.20 were posted..." — as opposed to `title`,
    /// which is a short label for list rows. This is NOT the AI kill
    /// switch's territory: there is currently no AI/Claude integration in
    /// this codebase at all, and even once one exists, `explanation:
    /// GeneratedProse?` (spec'd separately, not yet built) is where AI-
    /// authored prose would live — this field must keep rendering exactly
    /// the same whether or not that ever ships or is switched off, the same
    /// way `ClientQuestionDrafter`'s template prose already does elsewhere
    /// in this app. Additive, `nil` for every rule that hasn't been given
    /// one yet.
    public let narrative: String?
    /// Gauntlet Loop, Gauntlet B (2026-08-23): spec'd at
    /// `docs/phase-0/05_FINDING_SCHEMA.md` §5.1 ("view both transactions in
    /// QBO") and referenced in `docs/phase-0/11_VERTICAL_SLICE.md`'s finding
    /// mapping table as the "Before proceeding" note — never actually
    /// carried into the shipped `Finding` type until now. Steps a human
    /// should do BEFORE approving/proceeding, not part of the guided
    /// procedure itself (which is what to do AFTER deciding to act).
    /// Additive, empty for every rule that hasn't been given one yet.
    public let preApprovalChecklist: [String]
    /// Gauntlet Loop, Gauntlet B critic pass (2026-08-23): spec'd at
    /// `docs/phase-0/05_FINDING_SCHEMA.md` §5.1 as `riskIfIgnored:
    /// RiskStatement` — a fresh critic explicitly checked "does the finding
    /// say what happens if ignored?" and found nothing did. States the
    /// concrete, ongoing consequence of leaving a finding open (neither
    /// approved nor dismissed) — distinct from `ProposedAction.consequences`,
    /// which describes what happens if you DO act. Additive, `nil` for every
    /// rule that hasn't been given one yet.
    public let riskIfIgnored: String?

    public init(
        id: String,
        ruleID: RuleID,
        ruleVersion: RuleVersion,
        realmID: RealmID,
        period: AccountingPeriod,
        title: String,
        severity: Severity,
        confidence: Confidence,
        dollarExposure: Money,
        evidence: [EvidenceItem],
        proposedActions: [ProposedAction],
        provenance: [Provenance],
        status: FindingStatus = .open,
        vendorName: String? = nil,
        narrative: String? = nil,
        preApprovalChecklist: [String] = [],
        riskIfIgnored: String? = nil
    ) {
        self.id = id
        self.ruleID = ruleID
        self.ruleVersion = ruleVersion
        self.realmID = realmID
        self.period = period
        self.title = title
        self.severity = severity
        self.confidence = confidence
        self.dollarExposure = dollarExposure
        self.evidence = evidence
        self.proposedActions = proposedActions
        self.provenance = provenance
        self.status = status
        self.vendorName = vendorName
        self.narrative = narrative
        self.preApprovalChecklist = preApprovalChecklist
        self.riskIfIgnored = riskIfIgnored
    }
}

/// docs/phase-0/08_RULE_ENGINE.md §8.5: "Finding IDs are therefore derived —
/// a digest over (ruleID, ruleVersion, realmID, period, sorted affected
/// source identities) — not random UUIDs." This is what makes re-detection
/// of the same problem produce the same ID (acceptance criterion 4,
/// docs/phase-0/11_VERTICAL_SLICE.md §11.5).
public enum FindingIDGenerator {
    public static func makeID(
        ruleID: RuleID,
        ruleVersion: RuleVersion,
        realmID: RealmID,
        period: AccountingPeriod,
        sortedAffectedIDs: [String]
    ) -> String {
        let joined = [
            ruleID.rawValue,
            "\(ruleVersion.major).\(ruleVersion.minor).\(ruleVersion.patch)",
            realmID.rawValue,
            "\(period.year)-\(period.month)",
            sortedAffectedIDs.sorted().joined(separator: ",")
        ].joined(separator: "|")

        let digest = SHA256.hash(data: Data(joined.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
