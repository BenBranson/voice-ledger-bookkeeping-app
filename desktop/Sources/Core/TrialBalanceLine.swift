import Foundation

/// docs/VOICE_LEDGER_SPEC.md Page 12. Deliberately NOT `ReportLine`: QBO's
/// `TrialBalance` report has a fundamentally different shape from
/// BalanceSheet/ProfitAndLoss/CashFlow — verified live 2026-08-18. Its leaf
/// rows carry a `Debit` column and a `Credit` column (a value in exactly
/// one, never both) instead of a single signed amount, AND its leaf rows
/// carry no `type` field at all, unlike the other three reports' `"type":
/// "Data"` tag. Reusing `ReportLine`/`flatten` against this shape silently
/// dropped every real account row in testing and rendered only the "TOTAL"
/// summary line — a false-green report. This type and its own decoder
/// (`QBOSyncClient.flattenTrialBalance`) exist specifically to avoid that.
public struct TrialBalanceLine: Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let debit: Money?
    public let credit: Money?
    public let isSummary: Bool

    public init(label: String, debit: Money?, credit: Money?, isSummary: Bool) {
        self.id = "\(label)-\(isSummary)-\(UUID().uuidString.prefix(8))"
        self.label = label
        self.debit = debit
        self.credit = credit
        self.isSummary = isSummary
    }
}
