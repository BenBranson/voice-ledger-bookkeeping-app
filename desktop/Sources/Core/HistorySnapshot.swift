import Foundation

public extension AccountingPeriod {
    var nextMonth: AccountingPeriod {
        month == 12 ? AccountingPeriod(year: year + 1, month: 1) : AccountingPeriod(year: year, month: month + 1)
    }

    /// `count` consecutive months ending with (and including) `self`, oldest first.
    func trailingMonths(_ count: Int) -> [AccountingPeriod] {
        var months: [AccountingPeriod] = []
        var cursor = self
        for _ in 0..<max(count, 0) {
            months.insert(cursor, at: 0)
            cursor = cursor.previousMonth
        }
        return months
    }
}

public struct MonthlyReport: Codable, Hashable, Sendable {
    public let period: AccountingPeriod
    public let lines: [ReportLine]

    public init(period: AccountingPeriod, lines: [ReportLine]) {
        self.period = period
        self.lines = lines
    }
}

/// Multi-month history for one client (owner decision 2026-09-29): the
/// real data behind the cleanup scope score, flux analysis, and the stale
/// bank-feed sentinel. Separate from the single-period sync, which is
/// unchanged. Always scoped to one realm and stored in that realm's own
/// `ClientStore`.
public struct HistorySnapshot: Codable, Sendable, Equatable {
    public let realmID: RealmID
    public let fetchedAt: Date
    public let from: AccountingDate
    public let through: AccountingDate
    public let transactions: [LedgerTransaction]
    public let deposits: [LedgerDeposit]
    public let vendorCredits: [LedgerVendorCredit]
    public let accounts: [LedgerAccount]
    /// Oldest first; one entry per calendar month in range.
    public let monthlyProfitAndLoss: [MonthlyReport]
    public let latestBalanceSheet: [ReportLine]
    public let latestCashFlow: [ReportLine]
    public let coverage: Coverage
    /// Total Bank Accounts at each month end, oldest first. `nil` on
    /// snapshots saved before this was collected.
    public var monthEndCash: [MonthlyAmount]?

    public init(realmID: RealmID, fetchedAt: Date, from: AccountingDate, through: AccountingDate, transactions: [LedgerTransaction], deposits: [LedgerDeposit], vendorCredits: [LedgerVendorCredit], accounts: [LedgerAccount], monthlyProfitAndLoss: [MonthlyReport], latestBalanceSheet: [ReportLine], latestCashFlow: [ReportLine], coverage: Coverage) {
        self.realmID = realmID
        self.fetchedAt = fetchedAt
        self.from = from
        self.through = through
        self.transactions = transactions
        self.deposits = deposits
        self.vendorCredits = vendorCredits
        self.accounts = accounts
        self.monthlyProfitAndLoss = monthlyProfitAndLoss
        self.latestBalanceSheet = latestBalanceSheet
        self.latestCashFlow = latestCashFlow
        self.coverage = coverage
    }

    public var monthsCovered: Int { monthlyProfitAndLoss.count }
}
