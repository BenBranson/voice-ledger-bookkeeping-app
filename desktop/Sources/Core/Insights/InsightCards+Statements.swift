import Foundation

/// Cards for the profit & loss charts (expenses, cost drivers, income vs
/// expenses) and the balance-sheet ratios (owner request 2026-10-02: every
/// chart gets QBO links and what to do). Income and expense accounts have no
/// register in QBO, so each category links to its largest transaction this
/// month, the exact record, never a general page.
extension InsightCards {

    /// Accounts whose balance means something wasn't finished, not real spending.
    static let holdingAccountWords = ["reconciliation discrepanc", "ask my accountant", "uncategorized", "suspense"]

    static func isHoldingAccount(_ label: String) -> Bool {
        let l = label.lowercased()
        return holdingAccountWords.contains { l.contains($0) }
    }

    /// Expense lines below the income section, largest first (same split as `TopExpenseDrivers`).
    static func expenseLines(_ lines: [ReportLine]) -> [ReportLine] {
        let split = lines.contains(where: { $0.isSummary && $0.label == "Gross Profit" }) ? "Gross Profit" : "Total Income"
        guard let i = lines.firstIndex(where: { $0.isSummary && $0.label == split }) else { return [] }
        return lines[(i + 1)...].filter { !$0.isSummary && ($0.amount?.minorUnits ?? 0) != 0 }
            .sorted { abs(m($0.amount).minorUnits) > abs(m($1.amount).minorUnits) }
    }

    static func summary(_ label: String, _ lines: [ReportLine]) -> Money? {
        lines.first { $0.isSummary && $0.label == label }?.amount
    }

    /// The month's transactions that post to an account, largest first.
    static func postings(touching accountID: String?, in txns: [LedgerTransaction]) -> [LedgerTransaction] {
        guard let id = accountID else { return [] }
        return txns.filter { !$0.isVoided && ($0.lineAccountIDs.contains(id) || $0.lines.contains { $0.accountID == id }) }
            .sorted { abs($0.totalAmount.minorUnits) > abs($1.totalAmount.minorUnits) }
    }

    // MARK: Expenses / cost drivers

    /// `pareto: true` shows up to 15 categories with a running share of the total.
    public static func expenses(_ lines: [ReportLine], prior: [ReportLine], transactions: [LedgerTransaction], pareto: Bool, period: AccountingPeriod, footnote: String) -> InsightCard? {
        let all = expenseLines(lines)
        guard !all.isEmpty else { return nil }
        let shown = Array(all.prefix(pareto ? 15 : 8))
        let total = sum(all.map { m($0.amount) })
        let priorByLabel = Dictionary(expenseLines(prior).map { ($0.label, m($0.amount)) }, uniquingKeysWith: { a, _ in a })
        var running: Int64 = 0
        let rows = shown.map { line -> InsightRow in
            let amt = m(line.amount)
            running += amt.minorUnits
            let hits = postings(touching: line.accountID, in: transactions)
            var parts: [String] = []
            if pareto, total.minorUnits != 0 { parts.append("\(Int((Double(running) / Double(total.minorUnits) * 100).rounded()))% of spending so far") }
            if let p = priorByLabel[line.label] { parts.append("last month \(p.accountingDescription)") } else if !prior.isEmpty { parts.append("new this month") }
            if let top = hits.first {
                parts.append("\(hits.count) transaction\(hits.count == 1 ? "" : "s"); largest \(top.vendorName ?? kindLabel(top.entityKind)) \(top.totalAmount.accountingDescription), \(ClientText.polish(top.txnDate.formatted))")
            }
            let link: QBOTarget? = hits.first.map { .transaction(id: $0.id, kind: $0.entityKind) }
            return InsightRow(id: line.id, label: line.label, detail: parts.joined(separator: " · "), amountText: amt.accountingDescription,
                              link: link, warn: isHoldingAccount(line.label))
        }
        var recs: [String] = []
        let holding = all.filter { isHoldingAccount($0.label) }
        for h in holding.prefix(2) {
            recs.append("\(h.label) (\(m(h.amount).accountingDescription)) isn't real spending; it holds something unfinished. Open the transaction, find what it really was, and recode it to the right account.")
        }
        // Month-over-month movers: up 25% or more and at least $250.
        let movers = shown.compactMap { line -> (String, Money, Money)? in
            guard let p = priorByLabel[line.label], p.minorUnits > 0 else { return nil }
            let now = m(line.amount)
            guard now.minorUnits - p.minorUnits >= 25_000, Double(now.minorUnits) >= Double(p.minorUnits) * 1.25 else { return nil }
            return (line.label, now, p)
        }
        for (label, now, p) in movers.prefix(2) {
            recs.append("\(label) rose from \(p.accountingDescription) to \(now.accountingDescription). Check the largest transaction is coded right and isn't a duplicate, then ask the client if the increase is expected.")
        }
        if pareto, total.minorUnits > 0 {
            var r: Int64 = 0, n = 0
            for line in all { r += m(line.amount).minorUnits; n += 1; if Double(r) >= Double(total.minorUnits) * 0.8 { break } }
            recs.append("\(n) of \(all.count) categories make up 80% of spending. Review those first; the rest is small.")
        } else if let top = shown.first(where: { !isHoldingAccount($0.label) }), total.minorUnits > 0 {
            let share = Int((Double(m(top.amount).minorUnits) / Double(total.minorUnits) * 100).rounded())
            recs.append("\(top.label) is \(share)% of this month's spending. Open its largest transaction in QuickBooks to confirm it's coded right.")
        }
        let pairs = shown.map { ($0.label, m($0.amount)) }
        return InsightCard(title: pareto ? "Biggest Cost Drivers" : "Top Expense Categories",
                           subtitle: "\(ClientText.polish(ClientFacts.periodLabel(period))) · \(all.count) categories · links open each category's largest transaction",
                           headline: total.accountingDescription, chart: .money(.hbar, pairs, name: "Spent"), rows: rows, recommendations: recs, footnote: footnote)
    }

    // MARK: Income vs expenses

    public static func incomeVsExpenses(_ lines: [ReportLine], prior: [ReportLine], period: AccountingPeriod, footnote: String) -> InsightCard? {
        guard let income = FinancialKPIs.totalIncome(from: lines), let net = TaxEstimate.netIncome(from: lines) else { return nil }
        let expenses = income - net
        let pIncome = FinancialKPIs.totalIncome(from: prior), pNet = TaxEstimate.netIncome(from: prior)
        let pExpenses = (pIncome != nil && pNet != nil) ? pIncome! - pNet! : nil
        let cats = ["Revenue", "Expenses", "Net income"]
        var series: [InsightChartData.Series] = []
        if let pi = pIncome, let pe = pExpenses, let pn = pNet {
            series.append(.init(name: "Last month", values: [pi, pe, pn].map { $0.majorUnitsDouble }, valueTexts: [pi, pe, pn].map(\.accountingDescription)))
        }
        series.append(.init(name: "This month", values: [income, expenses, net].map { $0.majorUnitsDouble }, valueTexts: [income, expenses, net].map(\.accountingDescription)))
        let chart = InsightChartData(type: .bar, categories: cats, series: series, ids: cats, markZero: true)
        func vs(_ now: Money, _ before: Money?) -> String { before.map { "last month \($0.accountingDescription)" } ?? "" }
        var rows = [
            InsightRow(id: "inc", label: "Revenue", detail: vs(income, pIncome), amountText: income.accountingDescription),
            InsightRow(id: "exp", label: "Expenses (all costs)", detail: vs(expenses, pExpenses), amountText: expenses.accountingDescription),
        ]
        if let other = summary("Total Other Expenses", lines), other.minorUnits != 0 {
            rows.append(InsightRow(id: "oth", label: "of which other expenses", detail: "below operating income", amountText: other.accountingDescription))
        }
        rows.append(InsightRow(id: "net", label: "Net income", detail: vs(net, pNet), amountText: net.accountingDescription, warn: net.minorUnits < 0))
        var recs: [String] = []
        if income.minorUnits > 0 {
            let margin = Double(net.minorUnits) / Double(income.minorUnits) * 100
            recs.append(String(format: "Kept %.0f cents of every revenue dollar (net margin %.1f%%).", max(margin, 0), margin))
        }
        if let pn = pNet, pn.minorUnits != 0, net.minorUnits < pn.minorUnits {
            let biggest = expenseLines(lines).filter { isHoldingAccount($0.label) }.first
            recs.append("Net income fell from \(pn.accountingDescription) to \(net.accountingDescription)." + (biggest.map { " \($0.label) (\(m($0.amount).accountingDescription)) is part of the gap; clearing it would change this month's profit." } ?? " Open the Top Expense Categories card to see which costs grew."))
        }
        if net.minorUnits < 0 { recs.append("The month lost money. Check for duplicate or miscoded expenses before telling the client.") }
        recs.append("Say \"expense chart\" for the categories behind the expenses, each linked to its largest transaction.")
        return InsightCard(title: "Income vs. Expenses", subtitle: "\(ClientText.polish(ClientFacts.periodLabel(period))) vs. the month before",
                           headline: net.accountingDescription, chart: chart, rows: rows, recommendations: recs, footnote: footnote)
    }

    // MARK: Self-checking math

    public static func tieOut(_ checks: [TieOut.Check], period: AccountingPeriod, footnote: String) -> InsightCard {
        let tied = checks.filter(\.status.tied).count
        let broken = checks.filter { if case .doesNotTie = $0.status { return true }; return false }
        let rows = checks.map { c -> InsightRow in
            switch c.status {
            case .ties:
                return InsightRow(id: c.id, label: "✓ " + c.title, detail: c.compares, amountText: c.right?.accountingDescription ?? "")
            case .doesNotTie(let d):
                return InsightRow(id: c.id, label: "✗ " + c.title,
                                  detail: "\(c.leftLabel) \(c.left?.accountingDescription ?? "—") vs \(c.rightLabel) \(c.right?.accountingDescription ?? "—")",
                                  amountText: "off \(d.accountingDescription)", warn: true)
            case .notChecked(let why):
                return InsightRow(id: c.id, label: "– " + c.title, detail: why, amountText: "not checked")
            }
        }
        var recs: [String] = []
        if broken.isEmpty {
            recs.append(tied == checks.count ? "Every number ties to QuickBooks to the cent. Safe to report." : "Everything that could be checked ties. Sync again to run the rest.")
        } else {
            recs.append("Sync again first: a transaction entered while the reports were being read can cause a one-time difference.")
            recs.append("If it stays, open both reports in QuickBooks for the same date and compare them line by line; the difference above is the amount to find.")
            recs.append("Until it ties, the affected figures show gray on the dashboard and Moneypenny warns before using them.")
        }
        return InsightCard(title: "Numbers Tie-Out", subtitle: "\(ClientText.polish(ClientFacts.periodLabel(period))) · each figure proven against QuickBooks' own totals",
                           headline: "\(tied) of \(checks.count) tie", rows: rows, recommendations: recs, footnote: footnote)
    }

    // MARK: Financial health (working capital and ratios)

    public enum HealthFocus: Sendable { case workingCapital, currentRatio, quickRatio, grossMargin, netMargin }

    public static func financialHealth(balanceSheet bs: [ReportLine], profitAndLoss pl: [ReportLine], accounts: [LedgerAccount], focus: HealthFocus,
                                       period: AccountingPeriod, footnote: String) -> InsightCard? {
        guard let ca = summary("Total Current Assets", bs), let cl = summary("Total Current Liabilities", bs) else { return nil }
        let cash = summary("Total Bank Accounts", bs) ?? summary("Cash", bs)
        let ar = summary("Total Accounts Receivable", bs) ?? summary("Accounts Receivable", bs)
        let ap = summary("Total Accounts Payable", bs)
        let cards = summary("Total Credit Cards", bs)
        let wc = ca - cl
        let cr = FinancialKPIs.currentRatio(from: bs), qr = FinancialKPIs.quickRatio(from: bs)
        let gm = FinancialKPIs.grossMarginPercent(from: pl), nm = FinancialKPIs.netMarginPercent(from: pl)
        // Link a total only when ONE account makes it up: then that account's register is the exact record.
        func acct(_ t: LedgerAccountType) -> QBOTarget? {
            let of = accounts.filter { $0.accountType == t }
            return of.count == 1 ? .account(of[0].id) : nil
        }
        let pairs: [(String, Money)] = [("Cash", cash), ("Receivables", ar), ("Current assets", ca), ("Payables", ap), ("Credit cards", cards), ("Current liabilities", cl)]
            .compactMap { l, v in v.map { (l, $0) } }
        var rows: [InsightRow] = []
        if let cash { rows.append(InsightRow(id: "cash", label: "Cash in bank accounts", detail: "month-end balance sheet", amountText: cash.accountingDescription, link: acct(.bank))) }
        if let ar { rows.append(InsightRow(id: "ar", label: "Owed by customers", amountText: ar.accountingDescription, link: acct(.accountsReceivable))) }
        rows.append(InsightRow(id: "ca", label: "Total current assets", amountText: ca.accountingDescription))
        if let ap { rows.append(InsightRow(id: "ap", label: "Owed to vendors", amountText: ap.accountingDescription, link: acct(.accountsPayable))) }
        if let cards, cards.minorUnits != 0 { rows.append(InsightRow(id: "cc", label: "Credit cards", amountText: cards.accountingDescription, link: acct(.creditCard))) }
        rows.append(InsightRow(id: "cl", label: "Total current liabilities", amountText: cl.accountingDescription))
        rows.append(InsightRow(id: "wc", label: "Working capital", detail: "current assets − current liabilities", amountText: wc.accountingDescription, warn: wc.minorUnits < 0))
        if let cr { rows.append(InsightRow(id: "cr", label: "Current ratio", detail: "current assets ÷ current liabilities", amountText: String(format: "%.2f to 1", cr), warn: cr < 1)) }
        if let qr { rows.append(InsightRow(id: "qr", label: "Quick ratio", detail: "(cash + receivables) ÷ current liabilities", amountText: String(format: "%.2f to 1", qr), warn: qr < 1)) }
        if let gm { rows.append(InsightRow(id: "gm", label: "Gross margin", amountText: String(format: "%.1f%%", gm))) }
        if let nm { rows.append(InsightRow(id: "nm", label: "Net margin", amountText: String(format: "%.1f%%", nm), warn: nm < 0)) }
        var recs: [String] = []
        // Common rules of thumb, applied by code: below 1 means short-term bills exceed short-term assets.
        if let cr {
            if cr < 1 { recs.append(String(format: "Current ratio %.2f: short-term bills exceed short-term assets. Talk with the client about cash before the next payroll or big bill.", cr)) }
            else if cr < 1.5 { recs.append(String(format: "Current ratio %.2f is thin. Collecting overdue invoices is the fastest way to raise it.", cr)) }
            else { recs.append(String(format: "Current ratio %.2f: short-term assets cover short-term bills %.1f times over.", cr, cr)) }
        }
        let other = ca - m(cash) - m(ar)
        if ca.minorUnits > 0, Double(other.minorUnits) > Double(ca.minorUnits) * 0.1 {
            let pct = Int((Double(other.minorUnits) / Double(ca.minorUnits) * 100).rounded())
            recs.append("\(other.accountingDescription) (\(pct)%) of current assets is neither cash nor receivables. Check that Undeposited Funds and clearing accounts in it are real assets, not unfinished entries.")
        }
        if let gm, gm >= 99.9, (summary("Total Cost of Goods Sold", pl) == nil) { recs.append("Gross margin is 100% because no costs are coded to Cost of Goods Sold. For a service business that's normal; if the client sells products or uses job materials, those costs may belong there.") }
        if let ar, ca.minorUnits > 0, Double(ar.minorUnits) > Double(ca.minorUnits) * 0.5 { recs.append("More than half of current assets is money customers still owe. Say \"who owes us\" to see who is late.") }
        let headline: String
        switch focus {
        case .workingCapital: headline = wc.accountingDescription
        case .currentRatio: headline = cr.map { String(format: "%.2f to 1", $0) } ?? "—"
        case .quickRatio: headline = qr.map { String(format: "%.2f to 1", $0) } ?? "—"
        case .grossMargin: headline = gm.map { String(format: "%.1f%%", $0) } ?? "—"
        case .netMargin: headline = nm.map { String(format: "%.1f%%", $0) } ?? "—"
        }
        return InsightCard(title: "Financial Health", subtitle: "Balance sheet at the end of \(ClientText.polish(ClientFacts.periodLabel(period)))",
                           headline: headline, chart: .money(.hbar, pairs, name: "Balance"), rows: rows, recommendations: recs, footnote: footnote)
    }
}
