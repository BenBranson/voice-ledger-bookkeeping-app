import Foundation

/// Sales by customer state over the last 12 months, against each state's
/// remote-seller threshold (owner directive 2026-10-02). A SCREEN, not a
/// determination: it flags states worth a closer look. Thresholds checked
/// on the state's own site are used as-is; every other state is screened
/// at the most common $100,000 and labeled "check the state's rule".
/// Uses QuickBooks invoices (ship-to state, else bill-to); sales receipts
/// and marketplace sales are not included, which is stated on the page.
public struct NexusStateRow: Identifiable, Sendable, Equatable {
    public var id: String { state }
    public let state: String
    public let stateName: String
    public let sales: Money
    public let transactionCount: Int
    public let threshold: NexusThreshold
    public let thresholdChecked: Bool
    public let isHomeState: Bool
    public let hasTaxAgency: Bool

    /// Over the threshold (and the transaction count where the state requires both).
    public var overThreshold: Bool {
        sales.minorUnits > threshold.amount.minorUnits && (threshold.minimumTransactions.map { transactionCount > $0 } ?? true)
    }
    /// 80% of the way there.
    public var approaching: Bool { !overThreshold && sales.minorUnits * 5 >= threshold.amount.minorUnits * 4 }
    /// Needs the bookkeeper's attention: over (or near) a threshold where no tax agency is set up.
    public var needsReview: Bool { !isHomeState && !hasTaxAgency && (overThreshold || approaching) }
}

public enum EconomicNexusScreen {
    public static func rows(sales transactions: [LedgerTransaction], homeState: String, taxAgencyNames: [String], asOf: AccountingDate) -> [NexusStateRow] {
        let from = asOf.adding(days: -365)
        var totals: [String: (Int64, Int)] = [:]
        for t in transactions where t.entityKind == .invoice && !t.isVoided && t.txnDate > from && t.txnDate <= asOf {
            guard let s = t.customerState, StateComplianceRules.name(for: s) != nil else { continue }
            let cur = totals[s] ?? (0, 0)
            totals[s] = (cur.0 + t.totalAmount.minorUnits, cur.1 + 1)
        }
        let agencies = taxAgencyNames.map { $0.lowercased() }
        return totals.map { state, value in
            let name = StateComplianceRules.name(for: state) ?? state
            let checked = StateComplianceRules.rule(for: state).nexusThreshold
            let hasAgency = agencies.contains { $0.contains(name.lowercased()) || $0.hasPrefix(state.lowercased() + " ") || $0 == state.lowercased() }
            return NexusStateRow(state: state, stateName: name, sales: Money(minorUnits: value.0, currency: .usd), transactionCount: value.1,
                                 threshold: checked ?? StateComplianceRules.commonNexusScreen, thresholdChecked: checked != nil,
                                 isHomeState: state == homeState.uppercased(), hasTaxAgency: hasAgency)
        }
        .sorted { $0.sales.minorUnits > $1.sales.minorUnits }
    }
}
