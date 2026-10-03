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

    /// Findings only the client can resolve, with the question each one asks.
    static let clientOnlyQuestions: [String: String] = [
        "VL-PERSONAL-001": "was this a business cost, or personal (an owner draw)?",
        "VL-CAT-UNCAT-001": "what was this for, so it can go in the right category?",
    ]

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
        report.preparedBy = input.preparedBy
        report.workCompleted = WorkLog.items(activityLog: input.activityLog, findings: input.findings, period: period)
        let workCounts = Dictionary(grouping: report.workCompleted, by: \.status).mapValues(\.count)
        report.autoClearedCount = WorkLog.autoClearedCount(activityLog: input.activityLog, findings: input.findings, period: period)
        report.workImpact = WorkLog.impactSummary(report.workCompleted)

        // One authoritative set of open items and one status count.
        let periodEndLabel = report.meta.balanceDateLabel.replacingOccurrences(of: "Balances as of ", with: "")
        let openResult = ReportStatus.openItems(findings: input.findings, workItems: report.workCompleted, clientQuestions: input.clientQuestions, balanceSheet: bs, periodEndLabel: periodEndLabel)
        report.openItems = openResult.items
        report.droppedAfterPeriod = openResult.droppedAfterPeriod
        report.statusSummary = ReportStatus.summary(workItems: report.workCompleted, openItems: report.openItems)
        report.workSummary = report.statusSummary
        func findingRow(_ item: ReportOpenItem) -> R.FindingRow {
            R.FindingRow(title: item.title, amountText: item.amountText, detail: item.detail, action: item.action)
        }
        report.verifiedFindings = report.openItems.filter { $0.kind == .confirmed }.map(findingRow)
        report.reviewFindings = report.openItems.filter { $0.kind == .possible }.map(findingRow)
        let confirmedCount = report.openItems.filter { $0.kind == .confirmed }.count
        let possibleCount = report.openItems.filter { $0.kind == .possible }.count
        if report.droppedAfterPeriod > 0 {
            report.notes.append("\(report.droppedAfterPeriod) balance flag\(report.droppedAfterPeriod == 1 ? "" : "s") from the latest sync \(report.droppedAfterPeriod == 1 ? "is" : "are") left out: the balance was normal at \(periodEndLabel) and only changed afterwards.")
        }
        if report.autoClearedCount > 0 {
            report.notes.append("\(report.autoClearedCount) earlier flag\(report.autoClearedCount == 1 ? "" : "s") stopped appearing on a later sync without a recorded correction; \(report.autoClearedCount == 1 ? "it is" : "they are") not counted as work or as verified corrections.")
        }

        // Operating result vs the reported result, year to date, cash tie-out.
        report.performanceBridge = PerformanceAnalysis.bridge(current)
        let adjustments = PerformanceAnalysis.adjustments(current)
        let beforeAdjustments = net.map { $0 + adjustments }
        if let ytd = YearToDate.rows(months: input.monthlyProfitAndLoss, period: period) {
            report.ytd = ytd.rows
            report.ytdLabel = ytd.label
        }
        report.cashTie = CashTie.rows(balanceSheet: bs, cashFlow: input.cashFlow)?.rows ?? []
        if adjustments.minorUnits != 0, let before = beforeAdjustments, let i = report.kpis.firstIndex(where: { $0.id == "net" }) {
            let k = report.kpis[i]
            report.kpis[i] = R.KPI(id: k.id, label: k.label, valueText: k.valueText, comparisonText: k.comparisonText, detail: "Before the \(adjustments.accountingDescription) reconciliation adjustment: \(before.accountingDescription)", isNegative: k.isNegative)
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
        let unsettledForPosition = Self.unsettledBalances(bs)
        let positionHasCaveat = unsettledForPosition.minorUnits > 0 || (cash?.minorUnits ?? 0) < 0
        if let wc = FinancialKPIs.workingCapital(from: bs) {
            position.append(R.Row(label: "Working capital (short-term assets minus short-term obligations)", valueText: wc.accountingDescription, depth: 0, isTotal: false))
            // The same figure without balances still under review, so a reader
            // skimming the number sees how much of the cushion is unsettled.
            if unsettledForPosition.minorUnits > 0 {
                position.append(R.Row(label: "Working capital without the \(unsettledForPosition.accountingDescription) in suspense and clearing still under review", valueText: (wc - unsettledForPosition).accountingDescription, depth: 1, isTotal: false))
            }
        }
        if let ratio = FinancialKPIs.currentRatio(from: bs) {
            position.append(R.Row(label: "Current ratio (short-term assets ÷ short-term obligations)\(positionHasCaveat ? ", including balances still under review or overdrawn" : "")", valueText: String(format: "%.2f×", ratio), depth: 0, isTotal: false))
        }
        report.position = position

        // Comparative P&L (this month vs last month), matched by stable key.
        let priorByKey = Dictionary((priorLines ?? []).compactMap { l in l.amount.map { (l.isSummary ? "sum:\(l.label)" : l.stableKey, $0) } }, uniquingKeysWith: { first, _ in first })
        // Headings (no amount) are kept so sub-accounts always appear under their parent.
        report.comparativeProfitAndLoss = current.filter { $0.amount != nil || !$0.isSummary }.map { line in
            guard let amount = line.amount else { return R.ComparativeRow(label: line.label, currentText: "", priorText: "", depth: line.depth, isTotal: false) }
            return R.ComparativeRow(label: line.label, currentText: amount.accountingDescription,
                             priorText: priorLines == nil ? "—" : (priorByKey[line.isSummary ? "sum:\(line.label)" : line.stableKey]?.accountingDescription ?? "$0.00"),
                             depth: line.depth, isTotal: line.isSummary)
        }
        report.cashFlowStatement = input.cashFlow.filter { $0.amount != nil || !$0.isSummary }.map { R.Row(label: $0.label, valueText: $0.amount?.accountingDescription ?? "", depth: $0.depth, isTotal: $0.isSummary) }

        // Health check.
        var health: [R.HealthCheck] = []
        func check(_ area: String, _ question: String, _ kind: String, _ detail: String) {
            let status = kind == "stable" ? "Stable" : kind == "attention" ? "Needs attention" : kind == "low" ? "Needs attention" : "Insufficient information"
            health.append(R.HealthCheck(area: area, question: question, status: status, statusKind: kind, detail: detail))
        }
        let completeMonths = input.monthlyProfitAndLoss.filter { $0.period != period }.suffix(3)
        let trailingNet = completeMonths.map { TaxEstimate.netIncome(from: $0.lines) ?? .zero }.reduce(Money.zero, +)
        if let net, adjustments.minorUnits != 0, let before = beforeAdjustments {
            let nearBreakEven = revenue.map { abs(before.minorUnits) * 20 < $0.minorUnits } ?? false
            let kind = before.minorUnits < 0 || nearBreakEven ? "attention" : "stable"
            let describe = before.minorUnits < 0 ? "a loss of \(before.accountingDescription)" : nearBreakEven ? "about break-even (\(before.accountingDescription))" : "a profit of \(before.accountingDescription)"
            check("Operating result", "Before bookkeeping adjustments, did the business earn more than it spent?", kind,
                  "\(describe.prefix(1).uppercased() + describe.dropFirst()) in \(month(period)). QuickBooks reports a \(net.minorUnits < 0 ? "net loss" : "net profit") of \(Money(minorUnits: abs(net.minorUnits), currency: .usd).accountingDescription) after a \(adjustments.accountingDescription) reconciliation adjustment still under review.")
        } else if let net {
            if net.minorUnits < 0 {
                check("Operating result", "Is the business earning more than it spends?", "attention", "Net loss of \(Money(minorUnits: -net.minorUnits, currency: .usd).accountingDescription) in \(month(period)).")
            } else if !completeMonths.isEmpty && trailingNet.minorUnits < 0 {
                check("Operating result", "Is the business earning more than it spends?", "attention", "Profit of \(net.accountingDescription) this month, but a combined loss of \(trailingNet.accountingDescription) over the prior \(completeMonths.count) months.")
            } else {
                let margin = revenue.map { $0.minorUnits > 0 ? " (\(pct(net, of: $0)) of revenue)" : "" } ?? ""
                check("Operating result", "Is the business earning more than it spends?", "stable", "Net profit of \(net.accountingDescription)\(margin) in \(month(period)).")
            }
        } else {
            check("Operating result", "Is the business earning more than it spends?", "insufficient", "No Profit & Loss data for \(month(period)).")
        }
        if let cash {
            if cash.minorUnits < 0 {
                check("Cash & bills", "Is there cash to cover what's coming due?", "attention", "Bank accounts are overdrawn by \(Money(minorUnits: -cash.minorUnits, currency: .usd).accountingDescription).")
            } else if let cl = currentLiabilities, cl.minorUnits > 0, cash < cl {
                check("Cash & bills", "Is there cash to cover what's coming due?", "attention", "Cash of \(cash.accountingDescription) covers \(pct(cash, of: cl)) of the \(cl.accountingDescription) due within a year (vendor bills, credit cards, loan payments and taxes).")
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
            let split = AgingSplit(arTotal)
            let over90 = max(arTotal.days91AndOver ?? .zero, .zero)
            let attention = Double(over90.minorUnits) > Double(split.owed.minorUnits) * 0.10 || Double(split.over60Owed.minorUnits) > Double(split.owed.minorUnits) * 0.20
            let credits = split.credits.minorUnits < 0 ? " (plus \(split.creditsProseText) in customer credits to apply)" : ""
            check("Collections", "Are customers paying on time?", attention ? "attention" : "stable",
                  "Customers owe \(split.owed.accountingDescription)\(credits); \(split.over60Owed.accountingDescription) (\(pct(split.over60Owed, of: split.owed))) is more than 60 days old.")
        } else {
            check("Collections", "Are customers paying on time?", "stable", "No customer balances are outstanding.")
        }
        // Reporting confidence: a fixed rule, not a judgment.
        //   Low     — a tie-out check failed, data is incomplete, or bookkeeping
        //             adjustments exceed 25% of the month's costs.
        //   Limited — any confirmed issue, unclassified spending, or adjustment.
        //   Good    — none of the above.
        let failedChecks = report.checks.filter { !$0.passed }.count
        let costs = MonthlyReportBuilder.totalCosts(current) ?? .zero
        let parked = PerformanceAnalysis.unclassified(current)
        var reasons: [String] = []
        if adjustments.minorUnits != 0 { reasons.append("a \(adjustments.accountingDescription) reconciliation adjustment is unexplained") }
        if confirmedCount > 0 { reasons.append("\(confirmedCount) confirmed issue\(confirmedCount == 1 ? " is" : "s are") open") }
        if parked.minorUnits != 0 { reasons.append("\(parked.accountingDescription) of spending isn't classified yet") }
        if failedChecks > 0 { reasons.append("\(failedChecks) tie-out check\(failedChecks == 1 ? "" : "s") failed") }
        let lowAdjustments = costs.minorUnits > 0 && abs(adjustments.minorUnits) * 4 > costs.minorUnits
        if case .partial = input.coverage {
            report.reportingConfidence = "Insufficient information"
            check("Reporting confidence", "How far can these numbers be relied on?", "insufficient", "Some data could not be fully loaded this month; see notes.")
        } else if failedChecks > 0 || lowAdjustments {
            report.reportingConfidence = "Low"
            check("Reporting confidence", "How far can these numbers be relied on?", "low", "Low: " + reasons.joined(separator: "; ") + ".")
        } else if !reasons.isEmpty {
            report.reportingConfidence = "Limited"
            check("Reporting confidence", "How far can these numbers be relied on?", "attention", "Limited: " + reasons.joined(separator: "; ") + ".")
        } else {
            report.reportingConfidence = "Good"
            check("Reporting confidence", "How far can these numbers be relied on?", "stable", "Good: totals tie to QuickBooks and no confirmed issues are open\(possibleCount > 0 ? " (\(possibleCount) possible issue\(possibleCount == 1 ? "" : "s") to review)" : "").")
        }
        report.healthChecks = health

        // Takeaways.
        var takeaways: [String] = []
        if let net, adjustments.minorUnits != 0, let before = beforeAdjustments {
            takeaways.append("QuickBooks shows a \(net.minorUnits < 0 ? "net loss" : "net profit") of \(Money(minorUnits: abs(net.minorUnits), currency: .usd).accountingDescription), but \(adjustments.accountingDescription) of that is a reconciliation adjustment under review — before it, \(month(period)) came out at \(before.accountingDescription).")
        } else if let net {
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
            // Only corrections a person made and QuickBooks then confirmed.
            takeaways.append("\(workCounts[.correctedVerified]!) bookkeeping correction\(workCounts[.correctedVerified]! == 1 ? " was" : "s were") completed and verified in QuickBooks.")
        } else if let cash {
            takeaways.append("Bank balances ended the month at \(cash.accountingDescription).")
        }
        report.takeaways = Array(takeaways.prefix(3))

        // Questions for the client.
        var questions = input.clientQuestions.filter { $0.answer == nil }.map { "\($0.findingTitle): \($0.question.split(separator: "\n").first.map(String.init) ?? $0.question)" }
        questions += report.workCompleted.filter { $0.status == .awaitingClient }.map { "\($0.title) — waiting on your answer." }
        // Only the client can say what a purchase was for: a possible personal
        // expense or an uncategorized transaction becomes a question even before
        // one is drafted (Gemini review, 2026-10-03: the report flagged one in
        // Appendix B while saying "No open questions").
        let asked = Set(input.clientQuestions.map(\.findingID))
        let onReport = Set(report.openItems.map(\.findingID))
        questions += input.findings
            .filter { onReport.contains($0.id) && !asked.contains($0.id) && Self.clientOnlyQuestions[$0.ruleID.rawValue] != nil }
            .map { f in
                let what = f.vendorName.map { "\($0), \(f.dollarExposure.accountingDescription)" } ?? f.title
                return "\(ClientText.polish(what)): \(Self.clientOnlyQuestions[f.ruleID.rawValue]!)"
            }
        report.questionsForClient = Array(questions.prefix(6))

        // Priorities.
        var priorities: [R.Priority] = []
        let timing = "Before the next monthly close"
        let dueFormatter = DateFormatter()
        dueFormatter.locale = Locale(identifier: "en_US")
        dueFormatter.dateFormat = "MMM d"
        let thisWeek = "This week (by \(dueFormatter.string(from: input.generatedAt.addingTimeInterval(7 * 86_400))))"
        if adjustments.minorUnits != 0 {
            var p = R.Priority(action: "Trace the reconciliation adjustment to the bank statement", owner: "Benjamin", why: "\(adjustments.accountingDescription) of this month's result is an unexplained reconciliation adjustment.", timing: timing)
            p.impact = "Shows whether the \(net.map { $0.minorUnits < 0 ? "reported loss" : "reported result" } ?? "result") is real"
            priorities.append(p)
        }
        if let cashCheck = health.first(where: { $0.area == "Cash & bills" && $0.statusKind == "attention" }) {
            var p = R.Priority(action: "Plan cash for upcoming bills and payroll", owner: "Kris, with Benjamin", why: cashCheck.detail, timing: thisWeek)
            p.impact = "Avoid returned payments and overdraft fees"
            priorities.append(p)
        }
        if health.contains(where: { $0.area == "Collections" && $0.statusKind == "attention" }),
           let oldest = input.agedReceivables.filter({ !$0.isSummary }).max(by: { (($0.days61to90 ?? .zero) + ($0.days91AndOver ?? .zero)).minorUnits < (($1.days61to90 ?? .zero) + ($1.days91AndOver ?? .zero)).minorUnits }) {
            let overdue = (oldest.days61to90 ?? .zero) + (oldest.days91AndOver ?? .zero)
            var p = R.Priority(action: "Follow up on overdue customer balances, starting with \(oldest.label)", owner: "Kris", why: "\(overdue.accountingDescription) from \(oldest.label) is more than 60 days old.", timing: thisWeek)
            p.impact = "Collect up to \(overdue.accountingDescription)"
            priorities.append(p)
        }
        if !report.questionsForClient.isEmpty {
            var p = R.Priority(action: "Answer \(report.questionsForClient.count) open bookkeeping question\(report.questionsForClient.count == 1 ? "" : "s")", owner: "Kris", why: "These items can't be finalized without your input.", timing: timing)
            p.impact = "Lets these items be finalized"
            priorities.append(p)
        }
        for item in report.openItems where item.kind == .confirmed && priorities.count < 3 {
            guard let action = item.action, !priorities.contains(where: { $0.action == action }) else { continue }
            // The adjustment priority above already covers this one.
            if adjustments.minorUnits != 0 && item.amountText == adjustments.accountingDescription { continue }
            var p = R.Priority(action: action, owner: "Benjamin", why: "\(item.title).", timing: timing)
            p.impact = item.amountText == "—" ? "Makes the books reliable" : "Makes \(item.amountText) in the books reliable"
            priorities.append(p)
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
            if adjustments.minorUnits != 0, let before = beforeAdjustments {
                n["performance"] = R.Narrative(
                    happened: "Revenue was \(revenue.accountingDescription)\(revChange). Before a \(adjustments.accountingDescription) reconciliation adjustment the month came out at \(before.accountingDescription); after it, QuickBooks reports \(net.accountingDescription).",
                    matters: "The adjustment is a bookkeeping entry made when a bank reconciliation was closed with a difference, not day-to-day spending. Don't read the reported \(net.minorUnits < 0 ? "loss" : "result") as operating performance until it is traced.",
                    next: "Benjamin traces the adjustment to the bank statement before the next close; the result is restated if it turns out to be an error.")
            } else {
                n["performance"] = R.Narrative(happened: happened, matters: matters, next: report.expenseChanges.isEmpty ? "No single expense category moved enough to single out; keep watching the trend." : "Review the expense categories that changed most (below).")
            }
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
            let happened = "Bank balances ended at \(cash.accountingDescription)." + (ops.map { " Day-to-day operations \($0.minorUnits < 0 ? "used" : "brought in") \(Money(minorUnits: abs($0.minorUnits), currency: .usd).accountingDescription) of cash" + (net.map { ", compared with a net \($0.minorUnits < 0 ? "loss" : "profit") of \(Money(minorUnits: abs($0.minorUnits), currency: .usd).accountingDescription)." } ?? ".") } ?? "")
            n["cash"] = R.Narrative(
                happened: happened,
                matters: "Profit and cash differ because of timing: sales not yet collected, bills not yet paid, loan payments, equipment purchases, and owner draws.",
                next: cash.minorUnits < 0 ? "Bring the overdrawn account back above zero and confirm any transfers that haven't posted." : "Keep enough cash on hand for the bills on the following pages."
            )
        }
        if report.receivables != nil, let arTotal {
            let split = AgingSplit(arTotal)
            let over60 = split.over60Owed
            n["receivables"] = R.Narrative(
                happened: "Customers owe \(split.owed.accountingDescription); \(over60.accountingDescription) is more than 60 days old." + (split.credits.minorUnits < 0 ? " Another \(split.creditsProseText) is customer credits or unapplied payments, which lower the net balance to \(split.net.accountingDescription)." : ""),
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
            let equity = summary("Total Equity", bs)
            let assets = summary("TOTAL ASSETS", bs) ?? summary("Total Assets", bs)
            let liabilities = summary("Total Liabilities", bs)
            // Current-asset balances still being investigated.
            let unsettled = Self.unsettledBalances(bs)
            var happened = ""
            if let equity, let assets, let liabilities, equity.minorUnits < 0 {
                happened = "The business owns \(assets.accountingDescription) and owes \(liabilities.accountingDescription), so owner's equity is negative: \(equity.accountingDescription). "
            }
            happened += wc.minorUnits < 0
                ? "Short-term obligations exceed short-term assets by \(Money(minorUnits: -wc.minorUnits, currency: .usd).accountingDescription)."
                : "On paper, short-term assets exceed short-term obligations by \(wc.accountingDescription)."
            var matters: [String] = []
            if let equity, equity.minorUnits < 0 { matters.append("Negative equity means more has been lost or taken out than was put in; lenders treat it as a warning sign.") }
            if wc.minorUnits >= 0 && (unsettled.minorUnits > 0 || (cash?.minorUnits ?? 0) < 0) {
                let parts = [unsettled.minorUnits > 0 ? "counts \(unsettled.accountingDescription) in suspense and clearing balances still under review" : nil, (cash?.minorUnits ?? 0) < 0 ? "the bank accounts are overdrawn" : nil].compactMap { $0 }
                matters.append((wc - unsettled).minorUnits < 0
                    ? "The positive working capital depends on balances that aren't settled: it \(parts.joined(separator: ", and ")). It shouldn't be relied on as a cushion yet."
                    : "Working capital \(parts.joined(separator: ", and ")), so the cushion is thinner than it looks.")
            } else if wc.minorUnits < 0 {
                matters.append("The business may need cash from sales, savings, or financing to meet near-term obligations.")
            } else if matters.isEmpty {
                matters.append("The business has a cushion to meet near-term obligations.")
            }
            let hasBalanceItems = report.openItems.contains { $0.kind == .confirmed }
            n["position"] = R.Narrative(
                happened: happened,
                matters: matters.joined(separator: " "),
                next: hasBalanceItems ? "Resolve the confirmed balance-sheet items under Open items so this position can be relied on." : "No action needed; balances are as of \(periodEndLabel)."
            )
        }
        report.narratives = n
        // In a loss month the Sankey has to draw the loss as an inflow, which
        // reads badly; the waterfall tells that story instead.
        report.moneyFlow = (net?.minorUnits ?? -1) >= 0 ? ChartData.moneyFlow(from: current, hubLabel: "\(month(period)) \(period.year)", topExpenses: 6) : nil
        report.sparklines = ChartData.sparklines(months: input.monthlyProfitAndLoss, monthEndCash: input.monthEndCash)
        if input.agedPayables.isEmpty && !input.payablesLoaded { report.notes.append("The payables aging report could not be loaded, so bills coming due are not shown.") }
        return report
    }

    /// Current-asset balances still being investigated: positive suspense and
    /// clearing accounts. Shared by the position table and its narrative.
    static func unsettledBalances(_ bs: [ReportLine]) -> Money {
        bs.filter { !$0.isSummary && ["suspense", "clearing"].contains(where: $0.label.lowercased().contains) }
            .compactMap(\.amount).filter { $0.minorUnits > 0 }.reduce(Money.zero, +)
    }
}
