import Foundation

/// docs/VOICE_LEDGER_SPEC.md's Firm Cockpit: "Next Best Action — the app
/// says where to start." Firm Cockpit itself (every connected client on one
/// screen) is not built — this is the single-client decision logic that
/// feature would need per-client, usable standalone since it only needs
/// this one realm's already-loaded state. Deterministic priority order,
/// not a judgment call (`CLAUDE.md` rule 1): open high-severity findings
/// first (highest dollar exposure, materiality-gated already by the rule
/// that produced them), then an unimported Bank Feed Cleanup gap (Type B
/// pages can't even run their checks without one), then the next unlocked,
/// incomplete Month-End Close item, else nothing left to do.
public enum NextBestAction: Equatable, Sendable {
    case reviewHighSeverityFindings(count: Int)
    case importBankStatement
    case completeChecklistItem(ChecklistItem)
    case allClear

    public static func compute(
        findings: [Finding],
        checklistCompletions: [ChecklistItemCompletion],
        period: AccountingPeriod,
        hasImportedStatement: Bool
    ) -> NextBestAction {
        let openHighSeverity = findings.filter { $0.status == .open && $0.severity == .high }
        if !openHighSeverity.isEmpty {
            return .reviewHighSeverityFindings(count: openHighSeverity.count)
        }

        if !hasImportedStatement {
            return .importBankStatement
        }

        let completedIDs = Set(checklistCompletions.filter { $0.period == period }.map(\.itemID))
        if let next = MonthEndChecklist.defaultItems.first(where: { item in
            !completedIDs.contains(item.id) && MonthEndChecklist.isUnlocked(item, completedItemIDs: completedIDs)
        }) {
            return .completeChecklistItem(next)
        }

        return .allClear
    }
}
