import Foundation
import Core

/// Loads a multi-month `HistorySnapshot`. Queries are chunked into
/// 3-month windows and paged 1,000 rows at a time so large ledgers finish
/// without oversized responses; the backend adds 429 backoff and the
/// per-realm concurrency cap underneath.
extension QBOSyncClient {
    struct HistoryPageParams: Encodable, Sendable {
        let startDate: String
        let endDate: String
        let startPosition: Int
        let maxResults: Int
    }

    static let historyPageSize = 1000
    static let historyWindowMonths = 3

    public func syncHistory(realmID: RealmID, months: Int, through today: AccountingDate) async throws -> HistorySnapshot {
        let currentMonth = AccountingPeriod(year: today.year, month: today.month)
        let monthsInRange = currentMonth.trailingMonths(max(months, 1))
        let first = monthsInRange[0]
        let from = AccountingDate(year: first.year, month: first.month, day: 1)

        var windows: [(start: String, end: String)] = []
        var index = 0
        while index < monthsInRange.count {
            let slice = monthsInRange[index..<min(index + Self.historyWindowMonths, monthsInRange.count)]
            let start = Self.dateRange(for: slice.first!).start
            let end = slice.last! == currentMonth ? Self.format(today) : Self.dateRange(for: slice.last!).end
            windows.append((start, end))
            index += Self.historyWindowMonths
        }

        let decoder = JSONDecoder()
        var transactions: [LedgerTransaction] = []
        var deposits: [LedgerDeposit] = []
        var vendorCredits: [LedgerVendorCredit] = []
        for window in windows {
            transactions += try await pagedHistory(.readPurchases, realmID: realmID, window: window) {
                (try decoder.decode(QBOPurchaseQueryResponse.self, from: $0).queryResponse.purchase ?? []).map { Self.normalize($0) }
            }
            transactions += try await pagedHistory(.readBills, realmID: realmID, window: window) {
                (try decoder.decode(QBOBillQueryResponse.self, from: $0).queryResponse.bill ?? []).map { Self.normalize($0) }
            }
            transactions += try await pagedHistory(.readInvoices, realmID: realmID, window: window) {
                (try decoder.decode(QBOInvoiceQueryResponse.self, from: $0).queryResponse.invoice ?? []).map { Self.normalize($0) }
            }
            transactions += try await pagedHistory(.readPayments, realmID: realmID, window: window) {
                (try decoder.decode(QBOPaymentQueryResponse.self, from: $0).queryResponse.payment ?? []).map { Self.normalize($0) }
            }
            deposits += try await pagedHistory(.readDeposits, realmID: realmID, window: window) {
                (try decoder.decode(QBODepositQueryResponse.self, from: $0).queryResponse.deposit ?? []).map { Self.normalize($0) }
            }
            vendorCredits += try await pagedHistory(.readVendorCredits, realmID: realmID, window: window) {
                (try decoder.decode(QBOVendorCreditQueryResponse.self, from: $0).queryResponse.vendorCredit ?? []).map { Self.normalize($0) }
            }
        }

        let accountsData = try await withRateLimitRetry {
            try await backend.call(.readAccounts, realmID: realmID, params: ReadAccountsParams())
        }
        let accounts = (try decoder.decode(QBOAccountQueryResponse.self, from: accountsData).queryResponse.account ?? []).compactMap { Self.normalize($0) }

        var monthly: [MonthlyReport] = []
        for month in monthsInRange {
            let lines = try await withRateLimitRetry { try await fetchProfitAndLoss(realmID: realmID, period: month) }
            monthly.append(MonthlyReport(period: month, lines: lines))
        }
        let balanceSheet = try await withRateLimitRetry { try await fetchBalanceSheet(realmID: realmID, period: currentMonth) }
        let cashFlow = try await withRateLimitRetry { try await fetchCashFlow(realmID: realmID, period: currentMonth.previousMonth) }

        return HistorySnapshot(
            realmID: realmID,
            fetchedAt: Date(),
            from: from,
            through: today,
            transactions: transactions,
            deposits: deposits,
            vendorCredits: vendorCredits,
            accounts: accounts,
            monthlyProfitAndLoss: monthly,
            latestBalanceSheet: balanceSheet,
            latestCashFlow: cashFlow,
            coverage: .complete
        )
    }

    private func pagedHistory<T>(
        _ operation: CatalogOperation,
        realmID: RealmID,
        window: (start: String, end: String),
        decode: (Data) throws -> [T]
    ) async throws -> [T] {
        var results: [T] = []
        var startPosition = 1
        while true {
            let params = HistoryPageParams(startDate: window.start, endDate: window.end, startPosition: startPosition, maxResults: Self.historyPageSize)
            let data = try await withRateLimitRetry { try await backend.call(operation, realmID: realmID, params: params) }
            let page = try decode(data)
            results += page
            guard page.count == Self.historyPageSize else { return results }
            startPosition += Self.historyPageSize
        }
    }

    /// The backend's own per-realm limiter answers 429 before QBO ever
    /// sees the request; wait and retry rather than failing a long load.
    private func withRateLimitRetry<T>(_ work: () async throws -> T) async throws -> T {
        var delayNanoseconds: UInt64 = 1_000_000_000
        for attempt in 0..<4 {
            do {
                return try await work()
            } catch BackendClientError.httpError(let status, _) where status == 429 && attempt < 3 {
                try await Task.sleep(nanoseconds: delayNanoseconds)
                delayNanoseconds *= 2
            }
        }
        return try await work()
    }

    static func format(_ date: AccountingDate) -> String {
        String(format: "%04d-%02d-%02d", date.year, date.month, date.day)
    }
}
