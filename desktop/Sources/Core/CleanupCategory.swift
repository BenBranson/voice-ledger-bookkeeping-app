import Foundation

/// Owner directive (2026-08-30), via Gemma's own suggestion on the Cleanup
/// Assessment page: "group the findings into logical categories... to make
/// the scope manageable." A static rule→category table, not a judgment
/// call — CLAUDE.md rule 1 means even a UI grouping stays deterministic,
/// not something an LLM decides per-finding. Every `AppState
/// .cleanupAssessmentRuleIDs` entry has exactly one category here; a new
/// rule added to that set without a mapping here falls into `.other`
/// rather than crashing or vanishing.
public enum CleanupCategory: String, CaseIterable, Sendable {
    case balanceSheetIntegrity
    case duplicatesAndUnresolvedItems
    case categorizationAndCoding
    case vendorAndFeeAnomalies
    case other

    public var label: String {
        switch self {
        case .balanceSheetIntegrity: return "Balance Sheet Integrity"
        case .duplicatesAndUnresolvedItems: return "Duplicates & Unresolved Items"
        case .categorizationAndCoding: return "Categorization & Coding"
        case .vendorAndFeeAnomalies: return "Vendor & Fee Anomalies"
        case .other: return "Other"
        }
    }

    /// Display order — balance sheet integrity first (the errors most
    /// likely to distort the financial statements themselves), vendor/fee
    /// anomalies last (real, but rarely a books-are-wrong problem).
    public var sortOrder: Int {
        switch self {
        case .balanceSheetIntegrity: return 0
        case .duplicatesAndUnresolvedItems: return 1
        case .categorizationAndCoding: return 2
        case .vendorAndFeeAnomalies: return 3
        case .other: return 4
        }
    }

    private static let ruleCategories: [String: CleanupCategory] = [
        "VL-OBE-BALANCE-001": .balanceSheetIntegrity,
        "VL-BS-NEGBAL-001": .balanceSheetIntegrity,
        "VL-BS-UNDEP-001": .balanceSheetIntegrity,
        "VL-FORCED-RECON-001": .balanceSheetIntegrity,
        "VL-REPORT-TIE-001": .balanceSheetIntegrity,
        "VL-CLOSED-PERIOD-DRIFT-001": .balanceSheetIntegrity,
        "VL-BS-DRCR-001": .balanceSheetIntegrity,

        "VL-DUP-VEND-001": .duplicatesAndUnresolvedItems,
        "VL-DUP-BILL-001": .duplicatesAndUnresolvedItems,
        "VL-DUP-INV-001": .duplicatesAndUnresolvedItems,
        "VL-DUP-PAY-001": .duplicatesAndUnresolvedItems,
        "VL-VENDCREDIT-UNAPPLIED-001": .duplicatesAndUnresolvedItems,
        "VL-PERIOD-CLOSED-001": .duplicatesAndUnresolvedItems,
        "VL-TRANSPOSITION-001": .duplicatesAndUnresolvedItems,

        "VL-CC-PAYMENT-001": .categorizationAndCoding,
        "VL-PAYROLL-LUMP-001": .categorizationAndCoding,
        "VL-RELATIONSHIP-005": .categorizationAndCoding,
        "VL-RELATIONSHIP-003": .categorizationAndCoding,
        "VL-CAT-MISCODE-001": .categorizationAndCoding,
        "VL-PERSONAL-001": .categorizationAndCoding,

        "VL-VEND-ANOMALY-001": .vendorAndFeeAnomalies,
        "VL-VEND-PRICE-001": .vendorAndFeeAnomalies,
        "VL-FEE-AVOIDABLE-001": .vendorAndFeeAnomalies
    ]

    public static func category(forRuleID ruleID: String) -> CleanupCategory {
        ruleCategories[ruleID] ?? .other
    }
}
