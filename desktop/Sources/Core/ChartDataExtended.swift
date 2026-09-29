import Foundation

// Five more validated chart datasets (owner request 2026-09-29): money-flow
// Sankey, KPI sparklines, trend with margin, posting-activity calendar,
// and an expense treemap. Same contract as ChartData.swift: computed here
// from QBO data, drawn by report-renderer/shared/vl-charts.js.

private func cents(_ m: Money) -> Int64 { m.minorUnits }
private func major(_ c: Int64) -> Double { Double(c) / 100 }
private func text(_ c: Int64) -> String { Money(minorUnits: c, currency: .usd).accountingDescription }
private func summary(_ label: String, _ lines: [ReportLine]) -> Money? {
    lines.first { $0.isSummary && $0.label == label }?.amount
}

// MARK: - Money flow (Sankey)

public struct FlowNode: Codable, Equatable, Sendable {
    public let id: String
    public let accountID: String?
    public let label: String
    /// source, hub, use, profit, loss
    public let kind: String
    public let valueText: String
}

public struct FlowLink: Codable, Equatable, Sendable {
    public let source: String
    public let target: String
    public let value: Double
    public let valueText: String
}

public struct MoneyFlowData: Codable, Equatable, Sendable {
    public let nodes: [FlowNode]
    public let links: [FlowLink]
    public let totalText: String
    public let note: String
}

public extension ChartData {
    /// Where the month's money came from and went. Sources (income
    /// accounts, other income, expense credits, and — for a loss — the
    /// shortfall) flow into one hub, which flows out to cost of goods sold,
    /// each expense category, other expenses, income reductions, and — for a
    /// profit — net profit. Built only when every section ties to QBO's own
    /// totals, so inflows equal outflows exactly.
    static func moneyFlow(from lines: [ReportLine], hubLabel: String, topExpenses: Int = 8) -> MoneyFlowData? {
        guard let totalIncome = summary("Total Income", lines),
              let incomeEnd = lines.firstIndex(where: { $0.isSummary && $0.label == "Total Income" }),
              let netIncome = TaxEstimate.netIncome(from: lines) else { return nil }
        let incomeLeaves = lines[..<incomeEnd].filter { !$0.isSummary && ($0.amount?.minorUnits ?? 0) != 0 }
        guard incomeLeaves.reduce(Int64(0), { $0 + cents($1.amount!) }) == cents(totalIncome) else { return nil }

        let expenses = expenseCategories(from: lines, top: topExpenses)
        let totalExpenses = summary("Total Expenses", lines)
        if let expenses, totalExpenses != nil, !expenses.reconciles { return nil }
        let cogs = summary("Total Cost of Goods Sold", lines).map(cents) ?? 0
        let otherIncome = summary("Total Other Income", lines).map(cents) ?? 0
        let otherExpenses = summary("Total Other Expenses", lines).map(cents) ?? 0
        let credits = expenses?.creditItems.reduce(Int64(0)) { $0 - Int64(($1.value * 100).rounded()) } ?? 0
        let incomeReductions = incomeLeaves.filter { $0.amount!.minorUnits < 0 }.reduce(Int64(0)) { $0 - cents($1.amount!) }
        let net = cents(netIncome)

        var nodes: [FlowNode] = []
        var links: [FlowLink] = []
        let hub = "hub"
        func source(_ id: String, _ accountID: String?, _ label: String, _ kind: String, _ c: Int64) {
            guard c > 0 else { return }
            nodes.append(FlowNode(id: id, accountID: accountID, label: label, kind: kind, valueText: text(c)))
            links.append(FlowLink(source: id, target: hub, value: major(c), valueText: text(c)))
        }
        func use(_ id: String, _ accountID: String?, _ label: String, _ kind: String, _ c: Int64) {
            guard c > 0 else { return }
            nodes.append(FlowNode(id: id, accountID: accountID, label: label, kind: kind, valueText: text(c)))
            links.append(FlowLink(source: hub, target: id, value: major(c), valueText: text(c)))
        }

        for line in incomeLeaves where line.amount!.minorUnits > 0 {
            source(line.stableKey, line.accountID, line.label, "source", cents(line.amount!))
        }
        source("other-income", nil, "Other income", "source", otherIncome)
        source("expense-credits", nil, "Expense credits & refunds", "source", credits)
        if net < 0 { source("shortfall", nil, "Spent beyond income (net loss)", "loss", -net) }

        use("cogs", nil, "Cost of goods sold", "use", cogs)
        for item in expenses?.items ?? [] {
            use(item.id, item.accountID, item.label, "use", Int64((item.value * 100).rounded()))
        }
        use("other-expenses", nil, "Other expenses", "use", otherExpenses)
        use("income-reductions", nil, "Refunds & discounts given", "use", incomeReductions)
        if net > 0 { use("profit", nil, "Net profit", "profit", net) }

        let inflow = links.filter { $0.target == hub }.reduce(Int64(0)) { $0 + Int64(($1.value * 100).rounded()) }
        let outflow = links.filter { $0.source == hub }.reduce(Int64(0)) { $0 + Int64(($1.value * 100).rounded()) }
        guard inflow > 0, abs(inflow - outflow) <= Int64(links.count) else { return nil }
        nodes.insert(FlowNode(id: hub, accountID: nil, label: hubLabel, kind: "hub", valueText: text(inflow)), at: 0)
        return MoneyFlowData(
            nodes: nodes, links: links, totalText: text(inflow),
            note: net < 0
                ? "Spending exceeded income by \(text(-net)); that gap is shown as its own inflow so both sides balance."
                : "Every dollar that came in is shown going to a cost or to profit; both sides total \(text(inflow))."
        )
    }
}

// MARK: - KPI sparklines

public struct SparkRow: Codable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let periods: [String]
    public let values: [Double?]
    public let latestText: String
    public let changeText: String
    /// "up is good" (revenue, profit, cash) vs "up is bad" (expenses).
    public let higherIsBetter: Bool
}

public struct SparklineData: Codable, Equatable, Sendable {
    public let rows: [SparkRow]
    public let rangeLabel: String
}

public extension ChartData {
    /// `through` drops later months — pass the last *completed* month so a
    /// partial current month never shows as the "latest" value.
    static func sparklines(months: [MonthlyReport], monthEndCash: [MonthlyAmount], lastN: Int = 12, through: AccountingPeriod? = nil) -> SparklineData? {
        func keep(_ p: AccountingPeriod) -> Bool {
            guard let through else { return true }
            return (p.year, p.month) <= (through.year, through.month)
        }
        let months = months.filter { keep($0.period) }
        let monthEndCash = monthEndCash.filter { keep($0.period) }
        let trend = ChartData.trend(from: months)
        let points = Array(trend.points.suffix(lastN))
        guard points.count >= 2 else { return nil }
        func row(_ id: String, _ label: String, _ values: [Double?], _ periods: [String], _ higherIsBetter: Bool) -> SparkRow? {
            guard let last = values.last ?? nil else { return nil }
            let previous = values.dropLast().last ?? nil
            let change = previous.map { p -> String in
                let d = Int64(((last - p) * 100).rounded())
                return (d > 0 ? "+" : "") + text(d) + " vs prior month"
            } ?? "No prior month"
            return SparkRow(id: id, label: label, periods: periods, values: values, latestText: text(Int64((last * 100).rounded())), changeText: change, higherIsBetter: higherIsBetter)
        }
        let periods = points.map(\.label)
        var rows = [
            row("revenue", "Revenue", points.map(\.revenue), periods, true),
            row("expenses", "Expenses", points.map(\.expenses), periods, false),
            row("net", "Net income", points.map(\.netIncome), periods, true)
        ].compactMap { $0 }
        let cash = Array(monthEndCash.suffix(lastN))
        if cash.count >= 2 {
            let names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
            if let cashRow = row("cash", "Cash (month end)", cash.map { $0.amount.map(\.majorUnitsDouble) }, cash.map { "\(names[$0.period.month - 1]) \($0.period.year)" }, true) {
                rows.append(cashRow)
            }
        }
        return SparklineData(rows: rows, rangeLabel: "\(points.first!.label) – \(points.last!.label)")
    }
}

public struct MonthlyAmount: Codable, Equatable, Sendable {
    public let period: AccountingPeriod
    /// `nil` when that month's balance could not be read — never zero-filled.
    public let amount: Money?

    public init(period: AccountingPeriod, amount: Money?) {
        self.period = period
        self.amount = amount
    }
}

// MARK: - Posting-activity calendar

public struct CalendarDay: Codable, Equatable, Sendable {
    public let date: String
    public let count: Int
    public let amountText: String
}

public struct PostingCalendar: Codable, Equatable, Sendable {
    public let accountID: String
    public let accountLabel: String
    public let start: String
    public let end: String
    public let days: [CalendarDay]
    public let maxCount: Int
    public let lastPostingText: String
}

public extension ChartData {
    /// Posting activity per day for one bank/credit-card account over the
    /// loaded history. Days inside the range with no postings are real
    /// zeros (the history is complete for that range); days outside it are
    /// not drawn at all.
    static func postingCalendar(history: HistorySnapshot, accountID: String) -> PostingCalendar? {
        guard let account = history.accounts.first(where: { $0.id == accountID }) else { return nil }
        var counts: [AccountingDate: (Int, Int64)] = [:]
        func note(_ date: AccountingDate?, _ amount: Money?) {
            guard let date else { return }
            let current = counts[date] ?? (0, 0)
            counts[date] = (current.0 + 1, current.1 + abs(amount?.minorUnits ?? 0))
        }
        for txn in history.transactions where txn.paymentAccountID == accountID && !txn.isVoided { note(txn.txnDate, txn.totalAmount) }
        for deposit in history.deposits where deposit.depositToAccountID == accountID { note(deposit.txnDate, deposit.totalAmount) }
        func iso(_ d: AccountingDate) -> String { String(format: "%04d-%02d-%02d", d.year, d.month, d.day) }
        let days = counts.keys.sorted().map { d in CalendarDay(date: iso(d), count: counts[d]!.0, amountText: text(counts[d]!.1)) }
        return PostingCalendar(
            accountID: accountID, accountLabel: account.name,
            start: iso(history.from), end: iso(history.through),
            days: days, maxCount: max(1, counts.values.map(\.0).max() ?? 0),
            lastPostingText: counts.keys.max().map { "Last posting \(iso($0))" } ?? "No postings in the loaded history"
        )
    }
}

// MARK: - Expense treemap

public struct TreeNode: Codable, Equatable, Sendable {
    public let id: String
    public let accountID: String?
    public let label: String
    public let value: Double
    public let valueText: String
    public let children: [TreeNode]
}

public struct ExpenseTree: Codable, Equatable, Sendable {
    public let nodes: [TreeNode]
    public let totalText: String
    public let credits: [ChartItem]
}

public extension ChartData {
    /// Operating expenses nested by parent account → sub-account, as QBO's
    /// report nests them. Only positive amounts are area; credits are listed
    /// separately, never drawn as negative area.
    static func expenseTree(from lines: [ReportLine]) -> ExpenseTree? {
        let splitLabel = lines.contains { $0.isSummary && $0.label == "Gross Profit" } ? "Gross Profit" : "Total Income"
        guard let start = lines.firstIndex(where: { $0.isSummary && $0.label == splitLabel }) else { return nil }
        let end = lines[(start + 1)...].firstIndex { $0.isSummary && $0.label == "Total Expenses" } ?? lines.endIndex
        let section = lines[(start + 1)..<end]

        final class Builder {
            let id: String, accountID: String?, label: String
            var leaves: [TreeNode] = []
            var groups: [Builder] = []
            init(id: String, accountID: String?, label: String) { self.id = id; self.accountID = accountID; self.label = label }
            func node() -> TreeNode? {
                let children = groups.compactMap { $0.node() } + leaves
                let total = children.reduce(0.0) { $0 + $1.value }
                guard total > 0 else { return nil }
                let c = Int64((total * 100).rounded())
                return TreeNode(id: id, accountID: accountID, label: label, value: major(c), valueText: text(c), children: children.sorted { $0.value > $1.value })
            }
        }
        let root = Builder(id: "root", accountID: nil, label: "Expenses")
        var stack: [Builder] = [root]
        var credits: [ChartItem] = []
        for line in section {
            if line.amount == nil && !line.isSummary {
                guard line.accountID != nil else { continue }
                let group = Builder(id: line.stableKey, accountID: line.accountID, label: line.label)
                stack.last!.groups.append(group)
                stack.append(group)
            } else if line.isSummary {
                if stack.count > 1 && line.label == "Total \(stack.last!.label)" { stack.removeLast() }
            } else if let amount = line.amount, amount.minorUnits != 0 {
                if amount.minorUnits < 0 {
                    credits.append(ChartItem(id: line.stableKey, accountID: line.accountID, label: line.label, value: amount.majorUnitsDouble, valueText: amount.accountingDescription, category: "creditBalance"))
                } else {
                    stack.last!.leaves.append(TreeNode(id: line.stableKey, accountID: line.accountID, label: line.label, value: amount.majorUnitsDouble, valueText: amount.accountingDescription, children: []))
                }
            }
        }
        guard let top = root.node() else { return nil }
        return ExpenseTree(nodes: top.children, totalText: top.valueText, credits: credits)
    }
}

