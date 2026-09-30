import Foundation

/// One set of answers about a client, used by the pages, by Moneypenny (the
/// voice assistant), and by the regression tool — so all three always agree.
/// See docs/MONEYPENNY_CONSISTENCY_DESIGN.md. Pure functions over `ClientData`;
/// nothing in here talks to QuickBooks or to AppState.

/// Everything already loaded for one client, as plain values.
public struct ClientData: Sendable {
    public var period: AccountingPeriod
    public var transactions: [LedgerTransaction]
    public var accounts: [LedgerAccount]
    public var balanceSheet: [ReportLine]
    public var priorBalanceSheet: [ReportLine]
    public var profitAndLoss: [ReportLine]
    public var priorProfitAndLoss: [ReportLine]
    public var cashFlow: [ReportLine]
    public var findings: [Finding]
    public var history: HistorySnapshot?
    public var freshness: Freshness

    public init(period: AccountingPeriod, transactions: [LedgerTransaction] = [], accounts: [LedgerAccount] = [],
                balanceSheet: [ReportLine] = [], priorBalanceSheet: [ReportLine] = [], profitAndLoss: [ReportLine] = [],
                priorProfitAndLoss: [ReportLine] = [], cashFlow: [ReportLine] = [], findings: [Finding] = [],
                history: HistorySnapshot? = nil, freshness: Freshness = .neverSynced) {
        self.period = period
        self.transactions = transactions
        self.accounts = accounts
        self.balanceSheet = balanceSheet
        self.priorBalanceSheet = priorBalanceSheet
        self.profitAndLoss = profitAndLoss
        self.priorProfitAndLoss = priorProfitAndLoss
        self.cashFlow = cashFlow
        self.findings = findings
        self.history = history
        self.freshness = freshness
    }

    /// The current sync plus the 24-month history, de-duplicated by record.
    public var searchableTransactions: [LedgerTransaction] {
        var seen = Set<String>()
        return (transactions + (history?.transactions ?? [])).filter { seen.insert("\($0.entityKind.rawValue):\($0.id)").inserted }
    }

    public var searchableAccounts: [LedgerAccount] { accounts.isEmpty ? (history?.accounts ?? []) : accounts }
}

/// How current the loaded data is. The ONE description every page and
/// Moneypenny uses.
public enum Freshness: Sendable, Equatable {
    case neverSynced
    case cached(at: Date)
    case syncing
    case synced(at: Date)

    public func sentence(now: Date = Date()) -> String {
        func ago(_ d: Date) -> String {
            let seconds = max(0, Int(now.timeIntervalSince(d)))
            if seconds < 90 { return "just now" }
            if seconds < 3_600 { return "\(seconds / 60) minutes ago" }
            if seconds < 86_400 { let h = seconds / 3_600; return "\(h) hour\(h == 1 ? "" : "s") ago" }
            let days = seconds / 86_400; return "\(days) day\(days == 1 ? "" : "s") ago"
        }
        switch self {
        case .neverSynced: return "Not synced yet — no QuickBooks data is loaded."
        case .cached(let at): return "Showing saved data from the last sync (\(ago(at))) — sync to refresh."
        case .syncing: return "Syncing with QuickBooks…"
        case .synced(let at): return "Synced with QuickBooks \(ago(at))."
        }
    }

    public var isCurrent: Bool { if case .synced = self { return true }; return false }
}

/// What a fact covers, so an answer never has to guess its own scope.
public struct FactScope: Sendable, Equatable {
    public let period: AccountingPeriod
    public let source: String          // e.g. "the loaded July 2026 sync", "the 24-month history"
    public let freshness: Freshness

    public func sentence(now: Date = Date()) -> String {
        "For \(ClientFacts.periodLabel(period)) (\(source)). \(freshness.sentence(now: now))"
    }
}

public struct Fact<Value: Sendable>: Sendable {
    public let value: Value?
    public let scope: FactScope
    /// Why the value is missing, or a caveat that goes with it.
    public let note: String?
}

public struct AccountBalance: Sendable, Equatable {
    public let id: String
    public let name: String
    public let type: LedgerAccountType
    public let balance: Money
}

public enum FactFindingGroup: String, Sendable, CaseIterable {
    case duplicates, miscategorizedOrUncategorized = "miscategorized_or_uncategorized", personalExpense = "personal_expense"
    case negativeBalance = "negative_balance", lateFeesOrOverdrafts = "late_fees_or_overdrafts", vendorPriceIncrease = "vendor_price_increase"
    case cleanupAssessment = "cleanup_assessment", balanceSheetIntegrity = "balance_sheet_integrity", allOpen = "all_open"

    /// nil = every rule. Page-backed categories use the SAME sets the pages use.
    public var ruleIDs: Set<String>? {
        switch self {
        case .duplicates: return ["VL-DUP-NEAR-001", "VL-DUP-EXP-001", "VL-DUP-EXP-002", "VL-DUP-VEND-001", "VL-DUP-BILL-001", "VL-DUP-INV-001", "VL-DUP-PAY-001"]
        case .miscategorizedOrUncategorized: return ["VL-CAT-MISCODE-001", "VL-CAT-UNCAT-001"]
        case .personalExpense: return ["VL-PERSONAL-001"]
        case .negativeBalance: return ["VL-BS-NEGBAL-001"]
        case .lateFeesOrOverdrafts: return ["VL-FEE-AVOIDABLE-001"]
        case .vendorPriceIncrease: return ["VL-VEND-PRICE-001"]
        case .cleanupAssessment: return CleanupCategory.ruleIDs
        case .balanceSheetIntegrity: return CleanupCategory.ruleIDs(in: .balanceSheetIntegrity)
        case .allOpen: return nil
        }
    }
}

public enum ReportKind: String, Sendable, CaseIterable { case balanceSheet = "balance_sheet", incomeStatement = "income_statement", cashFlow = "cash_flow" }

public enum PeriodChoice: String, Sendable { case current, priorMonth = "prior_month" }

public struct VendorSummary: Sendable, Equatable {
    public let name: String
    public let transactionCount: Int
    public let total: Money
    public let lastDate: AccountingDate?
}

public struct AmountSearchResult: Sendable {
    public let amount: Money
    public let exact: [LedgerTransaction]
    /// Accounts whose CURRENT balance equals the amount, with their postings.
    public let balanceAccounts: [(account: LedgerAccount, postings: [LedgerTransaction])]
    /// Two or three transactions that add up to the amount (only looked for when nothing matched exactly).
    public let combination: [LedgerTransaction]?
    public init(amount: Money, exact: [LedgerTransaction], balanceAccounts: [(account: LedgerAccount, postings: [LedgerTransaction])], combination: [LedgerTransaction]?) {
        self.amount = amount; self.exact = exact; self.balanceAccounts = balanceAccounts; self.combination = combination
    }
}

public enum ClientFacts {
    static let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    public static func periodLabel(_ p: AccountingPeriod) -> String { "\(months[p.month - 1]) \(p.year)" }

    private static func scope(_ d: ClientData, _ source: String, prior: Bool = false) -> FactScope {
        FactScope(period: prior ? d.period.previousMonth : d.period, source: source, freshness: d.freshness)
    }
    private static var currentSource: String { "the loaded month" }

    // MARK: Freshness / history
    public static func freshnessSentence(_ d: ClientData, now: Date = Date()) -> String { d.freshness.sentence(now: now) }

    public static func searchScope(_ d: ClientData) -> String {
        var parts: [String] = []
        if !d.transactions.isEmpty { parts.append("the last sync (\(periodLabel(d.period)))") }
        if let h = d.history {
            parts.append("the 24-month history (\(months[h.from.month - 1].prefix(3)) \(h.from.year) – \(months[h.through.month - 1].prefix(3)) \(h.through.year))")
        }
        return parts.isEmpty ? "nothing yet" : parts.joined(separator: " and ")
    }

    // MARK: KPIs
    public static func cashBalance(_ d: ClientData, _ period: PeriodChoice = .current) -> Fact<Money> {
        let lines = period == .current ? d.balanceSheet : d.priorBalanceSheet
        let v = FinancialKPIs.cashBalance(from: lines)
        return Fact(value: v, scope: scope(d, currentSource, prior: period == .priorMonth), note: v == nil ? "The Balance Sheet isn't loaded for this month." : nil)
    }

    public static func revenue(_ d: ClientData, _ period: PeriodChoice = .current) -> Fact<Money> {
        let v = FinancialKPIs.totalIncome(from: period == .current ? d.profitAndLoss : d.priorProfitAndLoss)
        return Fact(value: v, scope: scope(d, currentSource, prior: period == .priorMonth), note: v == nil ? "The Profit & Loss isn't loaded for this month." : nil)
    }

    public static func netIncome(_ d: ClientData, _ period: PeriodChoice = .current) -> Fact<Money> {
        let v = TaxEstimate.netIncome(from: period == .current ? d.profitAndLoss : d.priorProfitAndLoss)
        return Fact(value: v, scope: scope(d, currentSource, prior: period == .priorMonth), note: v == nil ? "The Profit & Loss isn't loaded for this month." : nil)
    }

    // MARK: Accounts
    public static func accountBalance(_ d: ClientData, name: String) -> Fact<AccountBalance> {
        let q = name.trimmingCharacters(in: .whitespaces)
        let accounts = d.searchableAccounts
        let match = accounts.first { $0.name.caseInsensitiveCompare(q) == .orderedSame } ?? accounts.first { $0.name.localizedCaseInsensitiveContains(q) }
        let value = match.map { AccountBalance(id: $0.id, name: $0.name, type: $0.accountType, balance: $0.currentBalance) }
        return Fact(value: value, scope: scope(d, "the chart of accounts as of the last sync"),
                    note: match == nil ? "No account named “\(q)” in the chart of accounts." : "Balances are QuickBooks' current balances, which include activity after \(periodLabel(d.period)).")
    }

    public static func chartOfAccounts(_ d: ClientData, types: Set<LedgerAccountType>? = nil) -> Fact<[AccountBalance]> {
        let list = d.searchableAccounts.filter { types?.contains($0.accountType) ?? true }
            .map { AccountBalance(id: $0.id, name: $0.name, type: $0.accountType, balance: $0.currentBalance) }
        return Fact(value: list, scope: scope(d, "the chart of accounts as of the last sync"), note: nil)
    }

    // MARK: Search
    public static func searchAmount(_ d: ClientData, text: String) -> Fact<AmountSearchResult> {
        let sc = scope(d, searchScope(d))
        guard let amount = AmountSearch.parseAmount(text) else { return Fact(value: nil, scope: sc, note: "“\(text)” isn't a recognizable dollar amount.") }
        let pool = d.searchableTransactions
        let exact = AmountSearch.findTransactions(matching: amount, in: pool).sorted { $0.txnDate < $1.txnDate }
        let balances = AmountSearch.accountsWithBalance(amount, in: d.searchableAccounts).map { ($0, AmountSearch.transactions(for: $0, in: pool)) }
        let combo = exact.isEmpty ? AmountSearch.combination(matching: amount, in: pool) : nil
        return Fact(value: AmountSearchResult(amount: amount, exact: exact, balanceAccounts: balances, combination: combo), scope: sc,
                    note: pool.isEmpty ? "Nothing is loaded to search yet." : (d.history == nil ? "Only the current month is loaded — load the 24-month history to search older transactions." : nil))
    }

    /// Vendor-name / memo search over the same pool as the amount search.
    public static func searchText(_ d: ClientData, query: String) -> Fact<[LedgerTransaction]> {
        let q = query.trimmingCharacters(in: .whitespaces)
        let hits = d.searchableTransactions.filter { ($0.vendorName ?? "").localizedCaseInsensitiveContains(q) || ($0.memo ?? "").localizedCaseInsensitiveContains(q) }
            .sorted { $0.txnDate > $1.txnDate }
        return Fact(value: hits, scope: scope(d, searchScope(d)), note: d.history == nil ? "Only the current month is loaded." : nil)
    }

    // MARK: Vendors
    public static func vendor(_ d: ClientData, name: String) -> Fact<VendorSummary> {
        let hits = d.searchableTransactions.filter { !$0.isVoided && ($0.vendorName ?? "").localizedCaseInsensitiveContains(name) }
        guard let first = hits.first else { return Fact(value: nil, scope: scope(d, searchScope(d)), note: "No transactions for a vendor matching “\(name)”.") }
        let total = hits.map(\.totalAmount).reduce(Money.zero, +)
        let summary = VendorSummary(name: first.vendorName ?? name, transactionCount: hits.count, total: total, lastDate: hits.map(\.txnDate).max())
        return Fact(value: summary, scope: scope(d, searchScope(d)), note: nil)
    }

    public static func vendorsBySpend(_ d: ClientData, limit: Int) -> Fact<[VendorSpendSummary.VendorTotal]> {
        Fact(value: VendorSpendSummary.top(limit, from: d.transactions), scope: scope(d, currentSource), note: nil)
    }

    // MARK: Reports
    public static func reportLines(_ d: ClientData, kind: ReportKind) -> Fact<[ReportLine]> {
        let lines: [ReportLine]
        switch kind {
        case .balanceSheet: lines = d.balanceSheet
        case .incomeStatement: lines = d.profitAndLoss
        case .cashFlow: lines = d.cashFlow
        }
        return Fact(value: lines.isEmpty ? nil : lines, scope: scope(d, currentSource), note: lines.isEmpty ? "That report isn't loaded yet." : nil)
    }

    // MARK: Findings
    public static func findings(_ d: ClientData, category: FactFindingGroup) -> Fact<[Finding]> {
        let open = d.findings.filter { $0.status == .open }
        let list = category.ruleIDs.map { ids in open.filter { ids.contains($0.ruleID.rawValue) } } ?? open
        return Fact(value: FindingTriage.sorted(list), scope: scope(d, "the last sync's findings"), note: nil)
    }

    /// The Cleanup Assessment header number.
    public static func totalExposure(_ d: ClientData, category: FactFindingGroup) -> Fact<Money> {
        let list = findings(d, category: category).value ?? []
        guard let currency = list.first?.dollarExposure.currency, list.allSatisfy({ $0.dollarExposure.currency == currency }) else {
            return Fact(value: list.isEmpty ? Money.zero : nil, scope: scope(d, "the last sync's findings"), note: nil)
        }
        return Fact(value: list.reduce(Money(minorUnits: 0, currency: currency)) { $0 + $1.dollarExposure }, scope: scope(d, "the last sync's findings"), note: nil)
    }

    public static func openFindingCount(_ d: ClientData) -> Int { d.findings.filter { $0.status == .open }.count }
}
