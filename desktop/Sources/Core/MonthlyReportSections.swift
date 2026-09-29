import Foundation

/// Owner-summary and narrative sections of the monthly client report
/// (owner direction 2026-09-29): a four-area health check in plain words,
/// three takeaways, three priorities, questions for the client, and a
/// "what happened → why it matters → next step" note per page. Every
/// sentence is assembled from computed figures; nothing claims a cause the
/// data doesn't show.
public enum MonthlyReportSections {
    typealias R = MonthlyClientReport

    static func summary(_ label: String, _ lines: [ReportLine]) -> Money? {
        lines.first { $0.isSummary && $0.label == label }?.amount
    }

    static func anyLine(_ label: String, _ lines: [ReportLine]) -> Money? {
        lines.first { $0.label == label }?.amount
    }

    static func pct(_ part: Money, of whole: Money) -> String {
        guard whole.minorUnits != 0 else { return "—" }
        return String(format: "%.0f%%", Double(part.minorUnits) / Double(whole.minorUnits) * 100)
    }

    static func month(_ p: AccountingPeriod) -> String { MonthlyReportBuilder.monthNames[p.month - 1] }

    public static func enrich(_ base: MonthlyClientReport, input: MonthlyReportInputs) -> MonthlyClientReport {
        var report = base
        let period = input.period
        let prior = input.period.previousMonth
        let current = input.monthlyProfitAndLoss.first { $0.period == period }?.lines ?? []
        let priorLines = input.monthlyProfitAndLoss.first { $0.period == prior }?.lines
        let bs = input.balanceSheet

        let revenue = summary("Total Income", current)
        let net = TaxEstimate.netIncome(from: current) ?? (current.isEmpty ? nil : .zero)
        let priorNet = priorLines.map { TaxEstimate.netIncome(from: $0) ?? .zero }
        let priorRevenue = priorLines.map { summary("Total Income", $0) ?? .zero }
        let cash = summary("Total Bank Accounts", bs)
        let currentLiabilities = summary("Total Current Liabilities", bs)
        let open = input.findings.filter { $0.status == .open }

        report.preparedBy = input.preparedBy
        report.workCompleted = WorkLog.items(activityLog: input.activityLog, findings: input.findings, period: period)
        let workCounts = Dictionary(grouping: report.workCompleted, by: \.status).mapValues(\.count)
        report.workSummary = [WorkItem.Status.correctedVerified, .awaitingVerification, .awaitingClient, .notAnError].map {
            R.Row(label: WorkLog.label($0), valueText: "\(workCounts[$0] ?? 0)", depth: 0, isTotal: false)
        }

        // Expense changes vs last month, matched by account ID.
        var changes: [(Int64, R.ComparisonRow)] = []
        if let priorLines, let now = ChartData.expenseCategories(from: current, top: 100), let before = ChartData.expenseCategories(from: priorLines, top: 100) {
            let priorByID = Dictionary(before.allItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            var ids = Set(now.allItems.map(\.id))
            ids.formUnion(before.allItems.map(\.id))
            for id in ids {
                let c = now.allItems.first { $0.id == id }
                let p = priorByID[id]
                let cm = Money(minorUnits: Int64(((c?.value ?? 0) * 100).rounded()), currency: .usd)
                let pm = Money(minorUnits: Int64(((p?.value ?? 0) * 100).rounded()), currency: .usd)
                let delta = cm - pm
                guard abs(delta.minorUnits) >= 50_000 else { continue }
                if pm.minorUnits > 0, abs(Double(delta.minorUnits)) / Double(pm.minorUnits) < 0.2 { continue }
                changes.append((abs(delta.minorUnits), R.ComparisonRow(
                    label: c?.label ?? p?.label ?? id, currentText: cm.accountingDescription, priorText: pm.accountingDescription,
                    changeText: MonthlyReportBuilder.changeText(current: cm, prior: pm), percentText: MonthlyReportBuilder.percentText(current: cm, prior: pm))))
            }
        }
        report.expenseChanges = changes.sorted { $0.0 > $1.0 }.prefix(5).map(\.1)

        // Payables aging (same shape as receivables).
        if let total = input.agedPayables.last(where: \.isSummary), let grand = total.total, grand.minorUnits != 0 {
            let buckets: [(String, String, Money?)] = [("current", "Current", total.current), ("1-30", "1–30 days", total.days1to30), ("31-60", "31–60 days", total.days31to60), ("61-90", "61–90 days", total.days61to90), ("91+", "91+ days", total.days91AndOver)]
            report.payables = R.Receivables(
                buckets: buckets.map { ChartItem(id: $0.0, accountID: nil, label: $0.1, value: ($0.2 ?? .zero).majorUnitsDouble, valueText: ($0.2 ?? .zero).accountingDescription, category: $0.0 == "91+" ? "overdraft" : "asset") },
                totalText: grand.accountingDescription,
                topCustomers: input.agedPayables.filter { !$0.isSummary && ($0.total?.minorUnits ?? 0) != 0 }
                    .sorted { ($0.total?.minorUnits ?? 0) > ($1.total?.minorUnits ?? 0) }.prefix(8)
                    .map { R.Row(label: $0.label, valueText: $0.total!.accountingDescription, depth: 0, isTotal: false) },
                note: "Bills the business owes vendors, by how long they have been outstanding. Upcoming commitments not yet billed (payroll, loan payments, taxes) are not included."
            )
        }

        // Financial position in plain English.
        var position: [R.Row] = []
        if let assets = summary("TOTAL ASSETS", bs) ?? summary("Total Assets", bs) { position.append(R.Row(label: "What the business owns (total assets)", valueText: assets.accountingDescription, depth: 0, isTotal: false)) }
        if let liabilities = summary("Total Liabilities", bs) { position.append(R.Row(label: "What it owes (total liabilities)", valueText: liabilities.accountingDescription, depth: 0, isTotal: false)) }
        if let equity = summary("Total Equity", bs) { position.append(R.Row(label: "Owner's stake (equity)", valueText: equity.accountingDescription, depth: 0, isTotal: true)) }
        if let wc = FinancialKPIs.workingCapital(from: bs) { position.append(R.Row(label: "Working capital (short-term assets minus short-term obligations)", valueText: wc.accountingDescription, depth: 0, isTotal: false)) }
        if let ratio = FinancialKPIs.currentRatio(from: bs) { position.append(R.Row(label: "Current ratio (short-term assets ÷ short-term obligations)", valueText: String(format: "%.2f×", ratio), depth: 0, isTotal: false)) }
        report.position = position

        // Comparative P&L (this month vs last month), matched by stable key.
        let priorByKey = Dictionary((priorLines ?? []).compactMap { l in l.amount.map { (l.isSummary ? "sum:\(l.label)" : l.stableKey, $0) } }, uniquingKeysWith: { first, _ in first })
        report.comparativeProfitAndLoss = current.filter { $0.amount != nil }.map { line in
            R.ComparativeRow(label: line.label, currentText: line.amount!.accountingDescription,
                             priorText: priorLines == nil ? "—" : (priorByKey[line.isSummary ? "sum:\(line.label)" : line.stableKey]?.accountingDescription ?? "$0.00"),
                             depth: line.depth, isTotal: line.isSummary)
        }
        report.cashFlowStatement = input.cashFlow.filter { $0.amount != nil }.map { R.Row(label: $0.label, valueText: $0.amount!.accountingDescription, depth: $0.depth, isTotal: $0.isSummary) }

        // Health check.
        var health: [R.HealthCheck] = []
        func check(_ area: String, _ question: String, _ kind: String, _ detail: String) {
            let status = kind == "stable" ? "Stable" : kind == "attention" ? "Needs attention" : "Insufficient information"
            health.append(R.HealthCheck(area: area, question: question, status: status, statusKind: kind, detail: detail))
        }
        let completeMonths = input.monthlyProfitAndLoss.filter { $0.period != period }.suffix(3)
        let trailingNet = completeMonths.map { TaxEstimate.netIncome(from: $0.lines) ?? .zero }.reduce(Money.zero, +)
        if let net {
            if net.minorUnits < 0 {
                check("Profitability", "Is the business earning more than it spends?", "attention", "Net loss of \(Money(minorUnits: -net.minorUnits, currency: .usd).accountingDescription) in \(month(period)).")
            } else if !completeMonths.isEmpty && trailingNet.minorUnits < 0 {
                check("Profitability", "Is the business earning more than it spends?", "attention", "Profit of \(net.accountingDescription) this month, but a combined loss of \(trailingNet.accountingDescription) over the prior \(completeMonths.count) months.")
            } else {
                let margin = revenue.map { $0.minorUnits > 0 ? " (\(pct(net, of: $0)) of revenue)" : "" } ?? ""
                check("Profitability", "Is the business earning more than it spends?", "stable", "Net profit of \(net.accountingDescription)\(margin) in \(month(period)).")
            }
        } else {
            check("Profitability", "Is the business earning more than it spends?", "insufficient", "No Profit & Loss data for \(month(period)).")
        }
        if let cash {
            if cash.minorUnits < 0 {
                check("Cash & bills", "Is there cash to cover what's coming due?", "attention", "Bank accounts are overdrawn by \(Money(minorUnits: -cash.minorUnits, currency: .usd).accountingDescription).")
            } else if let cl = currentLiabilities, cl.minorUnits > 0, cash < cl {
                check("Cash & bills", "Is there cash to cover what's coming due?", "attention", "Cash of \(cash.accountingDescription) covers \(pct(cash, of: cl)) of \(cl.accountingDescription) in bills and short-term obligations.")
            } else {
                check("Cash & bills", "Is there cash to cover what's coming due?", "stable", "Cash of \(cash.accountingDescription)\(currentLiabilities.map { " against \($0.accountingDescription) in short-term obligations" } ?? "").")
            }
        } else {
            check("Cash & bills", "Is there cash to cover what's coming due?", "insufficient", "No bank balances on the Balance Sheet.")
        }
        let arTotal = input.agedReceivables.last(where: \.isSummary)
        if !input.receivablesLoaded {
            check("Collections", "Are customers paying on time?", "insufficient", "The receivables aging report could not be loaded.")
        } else if let arTotal, let total = arTotal.total, total.minorUnits > 0 {
            let over60 = (arTotal.days61to90 ?? .zero) + (arTotal.days91AndOver ?? .zero)
            let over90 = arTotal.days91AndOver ?? .zero
            let attention = Double(over90.minorUnits) > Double(total.minorUnits) * 0.10 || Double(over60.minorUnits) > Double(total.minorUnits) * 0.20
            check("Collections", "Are customers paying on time?", attention ? "attention" : "stable",
                  "Customers owe \(total.accountingDescription); \(over60.accountingDescription) (\(pct(over60, of: total))) is more than 60 days old.")
        } else {
            check("Collections", "Are customers paying on time?", "stable", "No customer balances are outstanding.")
        }
        let failedChecks = report.checks.filter { !$0.passed }.count
        let highOpen = open.filter { $0.severity == .high }.count
        if case .partial = input.coverage {
            check("Reliable books", "Can these numbers be trusted?", "insufficient", "Some data could not be fully loaded this month; see notes.")
        } else if failedChecks > 0 || highOpen > 0 {
            check("Reliable books", "Can these numbers be trusted?", "attention",
                  [highOpen > 0 ? "\(highOpen) high-priority bookkeeping item\(highOpen == 1 ? "" : "s") still open" : nil, failedChecks > 0 ? "\(failedChecks) reconciliation check\(failedChecks == 1 ? "" : "s") not passed" : nil].compactMap { $0 }.joined(separator: "; ") + ".")
        } else {
            check("Reliable books", "Can these numbers be trusted?", "stable", open.isEmpty ? "All automated checks passed with no open items." : "\(open.count) minor item\(open.count == 1 ? "" : "s") open; totals tie to QuickBooks.")
        }
        report.healthChecks = health

        // Takeaways.
        var takeaways: [String] = []
        if let net {
            let verb = net.minorUnits < 0 ? "lost \(Money(minorUnits: -net.minorUnits, currency: .usd).accountingDescription)" : "earned a profit of \(net.accountingDescription)"
            let vs = priorNet.map { p -> String in
                let d = net - p
                return d.minorUnits == 0 ? ", the same as \(month(prior))" : ", \(d.minorUnits > 0 ? "up" : "down") \(Money(minorUnits: abs(d.minorUnits), currency: .usd).accountingDescription) from \(month(prior))"
            } ?? ""
            takeaways.append("The business \(verb) in \(month(period))\(vs).")
        }
        if let change = report.expenseChanges.first {
            let rose = change.changeText.hasPrefix("+")
            let amount = rose ? String(change.changeText.dropFirst()) : change.changeText.trimmingCharacters(in: CharacterSet(charactersIn: "()"))
            takeaways.append("\(change.label) \(rose ? "rose" : "fell") \(amount) from \(month(prior)) — the biggest change in costs.")
        } else if let top = report.expenses?.allItems.first {
            takeaways.append("\(top.label) was the largest cost at \(top.valueText)\(top.share.map { String(format: " (%.0f%% of operating expenses)", $0 * 100) } ?? "").")
        }
        if let flagged = health.first(where: { $0.statusKind == "attention" && ($0.area == "Cash & bills" || $0.area == "Collections") }) {
            takeaways.append(flagged.detail)
        } else if (workCounts[.correctedVerified] ?? 0) > 0 {
            takeaways.append("\(workCounts[.correctedVerified]!) bookkeeping correction\(workCounts[.correctedVerified]! == 1 ? " was" : "s were") completed and verified in QuickBooks.")
        } else if let cash {
            takeaways.append("Bank balances ended the month at \(cash.accountingDescription).")
        }
        report.takeaways = Array(takeaways.prefix(3))

        // Questions for the client.
        var questions = input.clientQuestions.filter { $0.answer == nil }.map { "\($0.findingTitle): \($0.question.split(separator: "\n").first.map(String.init) ?? $0.question)" }
        questions += report.workCompleted.filter { $0.status == .awaitingClient }.map { "\($0.title) — waiting on your answer." }
        report.questionsForClient = Array(questions.prefix(6))

        // Priorities.
        var priorities: [R.Priority] = []
        let timing = "Before the next monthly close"
        if let cashCheck = health.first(where: { $0.area == "Cash & bills" && $0.statusKind == "attention" }) {
            priorities.append(R.Priority(action: "Plan cash for upcoming bills and payroll", owner: "Kris, with Benjamin", why: cashCheck.detail, timing: "This week"))
        }
        if health.contains(where: { $0.area == "Collections" && $0.statusKind == "attention" }),
           let oldest = input.agedReceivables.filter({ !$0.isSummary }).max(by: { (($0.days61to90 ?? .zero) + ($0.days91AndOver ?? .zero)).minorUnits < (($1.days61to90 ?? .zero) + ($1.days91AndOver ?? .zero)).minorUnits }) {
            let overdue = (oldest.days61to90 ?? .zero) + (oldest.days91AndOver ?? .zero)
            priorities.append(R.Priority(action: "Follow up on overdue customer balances, starting with \(oldest.label)", owner: "Kris", why: "\(overdue.accountingDescription) from \(oldest.label) is more than 60 days old.", timing: "This week"))
        }
        if !report.questionsForClient.isEmpty {
            priorities.append(R.Priority(action: "Answer \(report.questionsForClient.count) open bookkeeping question\(report.questionsForClient.count == 1 ? "" : "s")", owner: "Kris", why: "These items can't be finalized without your input.", timing: timing))
        }
        for finding in FindingTriage.sorted(open) where priorities.count < 3 {
            guard let action = finding.proposedActions.first?.title else { continue }
            priorities.append(R.Priority(action: action, owner: "Benjamin", why: "\(finding.title).", timing: timing))
        }
        report.priorities = Array(priorities.prefix(3))

        // Page narratives.
        var n: [String: R.Narrative] = [:]
        if let revenue, let net {
            let revChange = priorRevenue.map { r -> String in
                let d = revenue - r
                return d.minorUnits == 0 ? ", unchanged from \(month(prior))" : ", \(d.minorUnits > 0 ? "up" : "down") \(Money(minorUnits: abs(d.minorUnits), currency: .usd).accountingDescription) from \(month(prior))"
            } ?? ""
            let happened = "Revenue was \(revenue.accountingDescription)\(revChange); the month ended with a net \(net.minorUnits < 0 ? "loss" : "profit") of \(net.accountingDescription)."
            let matters: String
            switch (priorRevenue.map { revenue > $0 }, priorNet.map { net > $0 }) {
            case (true?, false?): matters = "Sales grew but profit fell, so costs rose faster than revenue."
            case (false?, true?): matters = "Profit improved even though sales were lower, so costs came down."
            case (true?, true?): matters = "Both sales and profit improved."
            case (false?, false?): matters = "Both sales and profit were lower than last month."
            default: matters = net.minorUnits < 0 ? "The business spent more than it brought in this month." : "The business covered its costs this month."
            }
            n["performance"] = R.Narrative(happened: happened, matters: matters, next: report.expenseChanges.isEmpty ? "No single expense category moved enough to single out; keep watching the trend." : "Review the expense categories that changed most (next page).")
        }
        if let exp = report.expenses, let top = exp.allItems.first {
            let change = report.expenseChanges.first
            n["expenses"] = R.Narrative(
                happened: "Operating expenses were \(exp.totalText). \(top.label) was the largest at \(top.valueText).",
                matters: change.map { "\($0.label) moved by \($0.changeText) from last month, the largest change in spending." } ?? "Spending by category was broadly in line with last month.",
                next: change.map { "Confirm whether the change in \($0.label) is one-time or ongoing." } ?? "No action needed on spending mix this month."
            )
        }
        if let cash {
            let ops = anyLine("Net cash provided by operating activities", input.cashFlow)
            let happened = "Bank balances ended at \(cash.accountingDescription)." + (ops.map { " Day-to-day operations \($0.minorUnits < 0 ? "used" : "brought in") \(Money(minorUnits: abs($0.minorUnits), currency: .usd).accountingDescription) of cash" + (net.map { ", compared with net \($0.minorUnits < 0 ? "loss" : "profit") of \($0.accountingDescription)." } ?? ".") } ?? "")
            n["cash"] = R.Narrative(
                happened: happened,
                matters: "Profit and cash differ because of timing: sales not yet collected, bills not yet paid, loan payments, equipment purchases, and owner draws.",
                next: cash.minorUnits < 0 ? "Bring the overdrawn account back above zero and confirm any transfers that haven't posted." : "Keep enough cash on hand for the bills on the following pages."
            )
        }
        if let ar = report.receivables, let arTotal {
            let over60 = (arTotal.days61to90 ?? .zero) + (arTotal.days91AndOver ?? .zero)
            n["receivables"] = R.Narrative(
                happened: "Customers owe \(ar.totalText); \(over60.accountingDescription) is more than 60 days old.",
                matters: "The older a balance gets, the less likely it is to be collected.",
                next: over60.minorUnits > 0 ? "Contact the customers with the oldest balances first." : "Collections are current; no follow-up needed."
            )
        }
        if let ap = report.payables, let apTotal = input.agedPayables.last(where: \.isSummary) {
            let past = (apTotal.days1to30 ?? .zero) + (apTotal.days31to60 ?? .zero) + (apTotal.days61to90 ?? .zero) + (apTotal.days91AndOver ?? .zero)
            n["payables"] = R.Narrative(
                happened: "The business owes vendors \(ap.totalText); \(past.accountingDescription) is past its due date.",
                matters: "Late bills can bring fees and strain vendor relationships.",
                next: past.minorUnits > 0 ? "Schedule payment of the oldest bills." : "Bills are current."
            )
        }
        if let wc = FinancialKPIs.workingCapital(from: bs) {
            n["position"] = R.Narrative(
                happened: "Short-term assets exceed short-term obligations by \(wc.accountingDescription).".replacingOccurrences(of: "exceed short-term obligations by (", with: "fall short of short-term obligations by ("),
                matters: wc.minorUnits < 0 ? "The business may need cash from sales, savings, or financing to meet near-term obligations." : "The business has a cushion to meet near-term obligations.",
                next: "Balances are as of \(report.meta.balanceDateLabel.replacingOccurrences(of: "Balances as of ", with: ""))."
            )
        }
        report.narratives = n
        report.moneyFlow = ChartData.moneyFlow(from: current, hubLabel: "\(month(period)) \(period.year)", topExpenses: 6)
        report.sparklines = ChartData.sparklines(months: input.monthlyProfitAndLoss, monthEndCash: input.monthEndCash)
        if input.agedPayables.isEmpty && !input.payablesLoaded { report.notes.append("The payables aging report could not be loaded, so bills coming due are not shown.") }
        return report
    }
}
