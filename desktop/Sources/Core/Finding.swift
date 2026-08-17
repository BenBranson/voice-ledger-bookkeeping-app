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

    public init(transactionID: String, highlightedFields: [String]) {
        self.transactionID = transactionID
        self.highlightedFields = highlightedFields
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

public struct ProposedAction: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let title: String
    public let resolution: ResolutionKind
    public let guidedProcedure: GuidedProcedure?
    public let consequences: [Consequence]
    public let reversal: ReversalPlan

    public init(
        id: String,
        title: String,
        resolution: ResolutionKind,
        guidedProcedure: GuidedProcedure?,
        consequences: [Consequence],
        reversal: ReversalPlan
    ) {
        self.id = id
        self.title = title
        self.resolution = resolution
        self.guidedProcedure = guidedProcedure
        self.consequences = consequences
        self.reversal = reversal
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
        status: FindingStatus = .open
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
