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
        var monthEndCash: [MonthlyAmount] = []
        for month in monthsInRange {
            let lines = try await withRateLimitRetry { try await fetchProfitAndLoss(realmID: realmID, period: month) }
            monthly.append(MonthlyReport(period: month, lines: lines))
            let sheet = try? await withRateLimitRetry { try await fetchBalanceSheet(realmID: realmID, period: month) }
            monthEndCash.append(MonthlyAmount(period: month, amount: sheet.flatMap { $0.first { $0.isSummary && $0.label == "Total Bank Accounts" }?.amount }))
        }
        let balanceSheet = try await withRateLimitRetry { try await fetchBalanceSheet(realmID: realmID, period: currentMonth) }
        let cashFlow = try await withRateLimitRetry { try await fetchCashFlow(realmID: realmID, period: currentMonth.previousMonth) }

        var snapshot = HistorySnapshot(
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
            coverage: Self.syncCoverage(pageCounts: ["accounts": accounts.count])
        )
        snapshot.monthEndCash = monthEndCash
        return snapshot
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

extension QBOSyncClient {
    struct ReadAccountLedgerParams: Encodable, Sendable {
        let reportKind = "GeneralLedger"
        let startDate: String
        let endDate: String
        let accountId: String
    }

    /// Every posting to one account, all dates through `through` —
    /// evidence rows for an account-balance finding (owner request
    /// 2026-09-29). Live-verified against the sandbox's Opening Balance
    /// Equity and seeded Suspense accounts.
    public func fetchAccountLedger(realmID: RealmID, accountID: String, through: AccountingDate) async throws -> [GeneralLedgerLine] {
        let data = try await backend.call(
            .readReport,
            realmID: realmID,
            params: ReadAccountLedgerParams(startDate: "2000-01-01", endDate: Self.format(through), accountId: accountID)
        )
        let decoded = try JSONDecoder().decode(QBORawReport.self, from: data)
        return Self.flattenGeneralLedger(decoded.rows, depth: 0).filter { !$0.isSummary && !$0.isAccountHeader && $0.transactionType != nil }
    }
}

extension QBOSyncClient {
    /// Profit & Loss lines plus the accounting basis QBO states for them.
    public func fetchProfitAndLossWithBasis(realmID: RealmID, period: AccountingPeriod) async throws -> (lines: [ReportLine], basis: String?) {
        let (startDate, endDate) = Self.dateRange(for: period)
        let data = try await backend.call(.readReport, realmID: realmID, params: ReadReportParams(reportKind: "ProfitAndLoss", startDate: startDate, endDate: endDate))
        let decoded = try JSONDecoder().decode(QBORawReport.self, from: data)
        return (Self.flatten(decoded.rows, depth: 0), decoded.header?.reportBasis)
    }

    /// Everything the monthly client report needs, read-only: 13 monthly
    /// P&Ls ending with `period` (so last year's same month can be
    /// compared), the period's Balance Sheet and Cash Flow, A/R aging, and
    /// account types. No writes.
    public func loadMonthlyReportInputs(realmID: RealmID, period: AccountingPeriod, clientName: String, environment: String, findings: [Finding], coverage: Coverage, today: AccountingDate) async throws -> MonthlyReportInputs {
        var monthly: [MonthlyReport] = []
        var monthEndCash: [MonthlyAmount] = []
        var basis: String?
        for month in period.trailingMonths(13) {
            let result = try await withReportRetry { try await fetchProfitAndLossWithBasis(realmID: realmID, period: month) }
            if month == period { basis = result.basis }
            monthly.append(MonthlyReport(period: month, lines: result.lines))
            let sheet = try? await withReportRetry { try await fetchBalanceSheet(realmID: realmID, period: month) }
            monthEndCash.append(MonthlyAmount(period: month, amount: sheet.flatMap { $0.first { $0.isSummary && $0.label == "Total Bank Accounts" }?.amount }))
        }
        let balanceSheet = try await withReportRetry { try await fetchBalanceSheet(realmID: realmID, period: period) }
        let cashFlow = (try? await withReportRetry { try await fetchCashFlow(realmID: realmID, period: period) }) ?? []
        let agingAsOf = Self.agingDate(for: period, today: today)
        let receivables = try? await withReportRetry { try await fetchAgedReceivables(realmID: realmID, asOf: agingAsOf) }
        let payables = try? await withReportRetry { try await fetchAgedPayables(realmID: realmID, asOf: agingAsOf) }
        let accountsData = try await backend.call(.readAccounts, realmID: realmID, params: ReadAccountsParams(activeOnly: false))
        let accounts = (try JSONDecoder().decode(QBOAccountQueryResponse.self, from: accountsData).queryResponse.account ?? []).compactMap { Self.normalize($0) }
        var inputs = MonthlyReportInputs(
            clientName: clientName, period: period, today: today, generatedAt: Date(), accountingBasis: basis, environment: environment,
            monthlyProfitAndLoss: monthly, balanceSheet: balanceSheet, cashFlow: cashFlow, agedReceivables: receivables ?? [],
            accountTypes: Dictionary(accounts.map { ($0.id, $0.accountType) }, uniquingKeysWith: { first, _ in first }),
            findings: findings, coverage: coverage
        )
        inputs.agedPayables = payables ?? []
        inputs.monthEndCash = monthEndCash
        inputs.receivablesLoaded = receivables != nil
        inputs.payablesLoaded = payables != nil
        return inputs
    }

    private func withReportRetry<T>(_ work: () async throws -> T) async throws -> T {
        for attempt in 0..<3 {
            do { return try await work() } catch BackendClientError.httpError(let status, _) where status == 429 && attempt < 2 {
                try await Task.sleep(nanoseconds: UInt64(attempt + 1) * 1_000_000_000)
            }
        }
        return try await work()
    }
}
