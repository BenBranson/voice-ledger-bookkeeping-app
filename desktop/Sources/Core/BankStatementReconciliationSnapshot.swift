import Foundation

/// Captured at the moment an OFX bank statement import is confirmed
/// (`AppState.confirmOFXImport`) — the file's own `<LEDGERBAL>`, tied to
/// the QBO account the statement was imported against. One per account;
/// a later import for the same account replaces the earlier snapshot
/// (only the most recent statement is a meaningful reconciliation
/// baseline).
public struct BankStatementReconciliationSnapshot: Codable, Sendable, Equatable {
    public let accountID: String
    public let statedEndingBalance: Money
    public let statedAsOfDate: AccountingDate?
    public let importedAt: Date

    public init(accountID: String, statedEndingBalance: Money, statedAsOfDate: AccountingDate?, importedAt: Date = Date()) {
        self.accountID = accountID
        self.statedEndingBalance = statedEndingBalance
        self.statedAsOfDate = statedAsOfDate
        self.importedAt = importedAt
    }
}
