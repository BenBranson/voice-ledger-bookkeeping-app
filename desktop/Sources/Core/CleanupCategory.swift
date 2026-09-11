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

    /// The exact rule IDs Cleanup Assessment evaluates — literally this
    /// type's own `ruleCategories` keys, exposed as a `Set` so every layer
    /// that needs this list (`AppState`, `voiceledger-mcp`) shares the
    /// ONE place it can be edited. Moved here 2026-09-06: this was
    /// previously `AppState.cleanupAssessmentRuleIDs`, a hand-typed
    /// literal duplicating these same 23 IDs — and `CleanupCategoryTests`
    /// had ALSO hand-mirrored a third copy of the identical list (its own
    /// doc comment explained why: `VoiceLedgerApp` can't be imported from
    /// `CoreTests` without inverting the module boundary
    /// `check-module-boundaries.sh` enforces). Three independently-typed
    /// copies of one list is exactly the kind of drift risk this app's own
    /// history keeps finding and fixing elsewhere — deriving this from the
    /// dictionary that already has to list every one of these rule IDs
    /// anyway makes divergence structurally impossible instead of merely
    /// unlikely.
    public static let ruleIDs: Set<String> = Set(ruleCategories.keys)

    /// The rule IDs filed under one category — used by `AppState
    /// .balanceSheetIntegrityRuleIDs` (2026-09-11 fix) the same way
    /// `ruleIDs` above is used for the full Cleanup Assessment set: that
    /// property used to be its own hand-typed literal of 5 IDs, which had
    /// silently drifted out of sync with this table — `VL-CLOSED-PERIOD-
    /// DRIFT-001` and `VL-BS-DRCR-001` were both filed here under
    /// `.balanceSheetIntegrity` but never added to the literal, so neither
    /// ever appeared on the actual Balance Sheet Integrity page despite
    /// being categorized as belonging to it. Deriving from this table
    /// instead makes that class of drift structurally impossible, same
    /// reasoning as `ruleIDs`'s own doc comment.
    public static func ruleIDs(in category: CleanupCategory) -> Set<String> {
        Set(ruleCategories.filter { $0.value == category }.keys)
    }
}
