import Foundation

/// Builders for Moneypenny's pop-up cards. Pure functions over data the
/// pages already show, so a card's figures always match its page.
public enum InsightCards {
    public static func m(_ x: Money?) -> Money { x ?? Money(minorUnits: 0, currency: .usd) }
    static func sum(_ xs: [Money]) -> Money { Money(minorUnits: xs.reduce(0) { $0 + $1.minorUnits }, currency: .usd) }

    static let shortMonths = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    /// "Jul '26" — short enough for 12 labels on one axis.
    public static func monthLabel(_ p: AccountingPeriod) -> String { "\(shortMonths[p.month - 1]) '\(String(p.year).suffix(2))" }

    public static func kindLabel(_ k: QBOEntityKind) -> String {
        switch k {
        case .purchase: return "Expense"
        case .bill: return "Bill"
        case .billPayment: return "Bill payment"
        case .invoice: return "Invoice"
        case .payment: return "Customer payment"
        case .journalEntry: return "Journal entry"
        case .vendorCredit: return "Vendor credit"
        default: return k.rawValue
        }
    }

    // MARK: Aging (who owes us / what we owe)

    public static func aging(_ lines: [AgingLine], receivables: Bool, footnote: String) -> InsightCard? {
        let leaves = AgingSummary.topLevelRows(lines).filter { ($0.total?.minorUnits ?? 0) != 0 }
        guard !leaves.isEmpty else { return nil }
        let reportTotal = lines.last { $0.isSummary && $0.label.uppercased() == "TOTAL" }?.total
        let net = reportTotal ?? sum(leaves.map { m($0.total) })
        /// Owed more than 60 days; a credit in a bucket doesn't reduce it.
        func late(_ l: AgingLine) -> Money { Money(minorUnits: max(0, m(l.days61to90).minorUnits) + max(0, m(l.days91AndOver).minorUnits), currency: .usd) }
        let sorted = leaves.sorted { m($0.total).minorUnits > m($1.total).minorUnits }
        let top = sorted.filter { m($0.total).minorUnits > 0 }.prefix(10)
        let chart = InsightChartData(type: .hstackedBar, categories: top.map(\.label), series: [
            .init(name: "Current", values: top.map { m($0.current).majorUnitsDouble }, valueTexts: top.map { m($0.current).accountingDescription }),
            .init(name: "1–60 days", values: top.map { (m($0.days1to30) + m($0.days31to60)).majorUnitsDouble }, valueTexts: top.map { (m($0.days1to30) + m($0.days31to60)).accountingDescription }),
            .init(name: "Over 60 days", values: top.map { late($0).majorUnitsDouble }, valueTexts: top.map { late($0).accountingDescription })
        ], ids: top.map(\.id))
        let rows = sorted.map { l -> InsightRow in
            var parts: [String] = []
            if m(l.current).minorUnits != 0 { parts.append("current \(m(l.current).accountingDescription)") }
            let mid = m(l.days1to30) + m(l.days31to60)
            if mid.minorUnits != 0 { parts.append("1–60 days \(mid.accountingDescription)") }
            if m(l.days61to90).minorUnits != 0 { parts.append("61–90 days \(m(l.days61to90).accountingDescription)") }
            if m(l.days91AndOver).minorUnits != 0 { parts.append("over 90 days \(m(l.days91AndOver).accountingDescription)") }
            let link: QBOTarget = receivables ? .customer(id: l.entityID, name: l.label) : .vendor(id: l.entityID, name: l.label)
            return InsightRow(id: l.id, label: l.label, detail: parts.joined(separator: " · "), amountText: m(l.total).accountingDescription,
                              link: link, warn: late(l).minorUnits > 0 || m(l.total).minorUnits < 0)
        }
        let overdue = leaves.filter { late($0).minorUnits > 0 }
        let over90 = leaves.filter { m($0.days91AndOver).minorUnits > 0 }
        let credits = leaves.filter { m($0.total).minorUnits < 0 }
        var recs: [String] = []
        if receivables {
            if !overdue.isEmpty { recs.append("Follow up with \(overdue.count) customer\(overdue.count == 1 ? "" : "s") more than 60 days late (\(sum(overdue.map(late)).accountingDescription)): send a statement from QuickBooks and ask the client to confirm each will be paid.") }
            if !over90.isEmpty { recs.append("For balances over 90 days (\(sum(over90.map { m($0.days91AndOver) }).accountingDescription)), ask the client whether each is still collectible. A payment recorded as a deposit instead of against the invoice also leaves an invoice open; check that first.") }
            if !credits.isEmpty { recs.append("\(credits.count) customer\(credits.count == 1 ? " shows" : "s show") a credit (\(sum(credits.map { m($0.total) }).accountingDescription)). Apply each credit or unapplied payment to an open invoice, or refund it.") }
            if recs.isEmpty { recs.append("Nothing is more than 60 days late. Keep sending statements monthly.") }
        } else {
            if !overdue.isEmpty { recs.append("\(overdue.count) vendor\(overdue.count == 1 ? " has" : "s have") bills more than 60 days old (\(sum(overdue.map(late)).accountingDescription)). Ask the client whether they were paid outside QuickBooks: a payment entered as an expense leaves the bill open and doubles the expense. If paid, link the payment to the bill; if not, confirm the due date.") }
            if !credits.isEmpty { recs.append("\(credits.count) vendor\(credits.count == 1 ? " shows" : "s show") a credit (\(sum(credits.map { m($0.total) }).accountingDescription)): an unapplied vendor credit or an overpayment. Apply it to the next bill or ask the vendor for a refund.") }
            if recs.isEmpty { recs.append("No bills are more than 60 days old.") }
        }
        return InsightCard(title: receivables ? "Who Owes Us" : "What We Owe",
                           subtitle: receivables ? "Open customer invoices by age (Aged Receivables)" : "Open vendor bills by age (Aged Payables)",
                           headline: net.accountingDescription, chart: chart, rows: Array(rows), recommendations: recs, footnote: footnote)
    }

    // MARK: Vendor or customer detail

    public static func counterparty(_ name: String, transactions: [LedgerTransaction], asOf: AccountingDate, footnote: String) -> InsightCard? {
        let hits = transactions.filter { !$0.isVoided && ClientFacts.nameMatches($0.vendorName ?? "", name) }
            .sorted { $0.txnDate > $1.txnDate }
        guard let first = hits.first else { return nil }
        let displayName = first.vendorName ?? name
        let isCustomer = hits.allSatisfy { $0.entityKind == .invoice || $0.entityKind == .payment }
        let spendKinds: Set<QBOEntityKind> = isCustomer ? [.invoice] : [.purchase, .bill]
        var months: [(String, Money)] = []
        var cursor = AccountingPeriod(year: asOf.year, month: asOf.month)
        for _ in 0..<12 {
            let total = sum(hits.filter { spendKinds.contains($0.entityKind) && cursor.contains($0.txnDate) }.map(\.totalAmount))
            months.insert((monthLabel(cursor), total), at: 0)
            cursor = cursor.previousMonth
        }
        let yearTotal = sum(months.map(\.1))
        let rows = hits.prefix(12).map { t in
            InsightRow(id: t.id, label: ClientText.polish(t.txnDate.formatted), detail: [kindLabel(t.entityKind), t.docNumber.map { "#\($0)" }, t.memo].compactMap { $0 }.joined(separator: " · "),
                       amountText: t.totalAmount.accountingDescription, link: .transaction(id: t.id, kind: t.entityKind))
        }
        var recs: [String] = []
        let spend = hits.filter { spendKinds.contains($0.entityKind) }
        if spend.count >= 4, let latest = spend.first {
            let prior = spend.dropFirst().prefix(6)
            let avg = Double(prior.reduce(0) { $0 + $1.totalAmount.minorUnits }) / Double(prior.count)
            if avg > 0, Double(latest.totalAmount.minorUnits) > avg * 1.25 {
                let pct = Int(((Double(latest.totalAmount.minorUnits) / avg) - 1) * 100)
                recs.append("The latest \(isCustomer ? "invoice" : "charge") (\(latest.totalAmount.accountingDescription) on \(ClientText.polish(latest.txnDate.formatted))) is \(pct)% above the recent average of \(Money(minorUnits: Int64(avg.rounded()), currency: .usd).accountingDescription). \(isCustomer ? "Confirm the amount with the client." : "Check it against the vendor's invoice for a price change, an extra item or a duplicate.")")
            }
        }
        var seen: [String: LedgerTransaction] = [:]
        for t in spend {
            let key = "\(t.txnDate.formatted)|\(t.totalAmount.minorUnits)"
            if let other = seen[key], other.id != t.id {
                recs.append("Two \(kindLabel(t.entityKind).lowercased())s of \(t.totalAmount.accountingDescription) on \(ClientText.polish(t.txnDate.formatted)). Open both in QuickBooks and confirm one isn't a duplicate.")
                break
            }
            seen[key] = t
        }
        if recs.isEmpty { recs.append(isCustomer ? "Invoices look steady over the last 12 months." : "Charges look steady; nothing out of pattern.") }
        return InsightCard(title: displayName, subtitle: isCustomer ? "Invoiced to this customer, last 12 months" : "Spent with this vendor, last 12 months (expenses and bills)",
                           headline: yearTotal.accountingDescription, chart: .money(.bar, months, name: isCustomer ? "Invoiced" : "Spent"),
                           rows: Array(rows), recommendations: recs,
                           footnote: "Chart and headline: last 12 months. All loaded history: \(hits.count) transaction\(hits.count == 1 ? "" : "s"), \(sum(hits.filter { spendKinds.contains($0.entityKind) }.map(\.totalAmount)).accountingDescription). \(footnote)")
    }

    // MARK: Revenue / net income trend

    public enum TrendMetric: Sendable { case revenue, netIncome }

    /// `focus` is the month being reviewed: the headline and the comparison
    /// are about it, so they match the page and the spoken figure.
    public static func trend(_ metric: TrendMetric, monthly: [MonthlyReport], focus: AccountingPeriod?, footnote: String) -> InsightCard? {
        let all: [(AccountingPeriod, Money)] = monthly.compactMap { r in
            (metric == .revenue ? FinancialKPIs.totalIncome(from: r.lines) : TaxEstimate.netIncome(from: r.lines)).map { (r.period, $0) }
        }
        let points = Array(all.suffix(12))
        guard points.count >= 2 else { return nil }
        let label = metric == .revenue ? "Revenue" : "Net Income"
        let focusIndex = focus.flatMap { f in points.firstIndex { $0.0 == f } } ?? points.count - 1
        let focused = points[focusIndex]
        let before = points[..<focusIndex]
        var recs: [String] = []
        if !before.isEmpty {
            let avg = Double(before.reduce(0) { $0 + $1.1.minorUnits }) / Double(before.count)
            let change = avg != 0 ? (Double(focused.1.minorUnits) - avg) / abs(avg) * 100 : 0
            recs.append("\(ClientFacts.periodLabel(focused.0)): \(focused.1.accountingDescription), \(abs(Int(change.rounded())))% \(change >= 0 ? "above" : "below") the average of the \(before.count) month\(before.count == 1 ? "" : "s") before it (\(Money(minorUnits: Int64(avg.rounded()), currency: .usd).accountingDescription)).")
            if metric == .revenue && abs(change) > 25 {
                recs.append("A swing that large is worth a look: check for a missing month of deposits, invoices dated in the wrong month, or a one-time sale.")
            }
        }
        if metric == .netIncome {
            let losses = points.filter { $0.1.minorUnits < 0 }
            if !losses.isEmpty { recs.append("\(losses.count) of the last \(points.count) months show a loss. Before reading that as real, confirm those months are reconciled and nothing is uncategorized.") }
        }
        let rows = points.reversed().prefix(4).map { InsightRow(id: "\($0.0.year)-\($0.0.month)", label: ClientFacts.periodLabel($0.0) + ($0.0 == focused.0 ? " (reviewing)" : ""), amountText: $0.1.accountingDescription, warn: $0.1.minorUnits < 0) }
        return InsightCard(title: label, subtitle: "By month, \(monthLabel(points.first!.0)) to \(monthLabel(points.last!.0)); headline is \(ClientFacts.periodLabel(focused.0))", headline: focused.1.accountingDescription,
                           chart: .money(metric == .netIncome ? .bar : .line, points.map { (monthLabel($0.0), $0.1) }, name: label, markZero: metric == .netIncome),
                           rows: Array(rows), recommendations: recs, footnote: footnote)
    }

    // MARK: Cash outlook

    public static func cashOutlook(_ f: ThirteenWeekForecast, receivablesOver60: Money?, footnote: String) -> InsightCard {
        let pts = f.weeks.map { ("W\($0.number)", $0.endingCash) }
        var rows: [InsightRow] = [InsightRow(id: "today", label: "Cash today", amountText: f.startingCash.accountingDescription)]
        if let low = f.lowestWeek { rows.append(InsightRow(id: "low", label: "Lowest point: week \(low.number)", detail: "week of \(ClientText.polish(low.start.formatted))", amountText: low.endingCash.accountingDescription, warn: low.endingCash.minorUnits < 0)) }
        if let end = f.weeks.last { rows.append(InsightRow(id: "end", label: "End of week 13", amountText: end.endingCash.accountingDescription, warn: end.endingCash.minorUnits < 0)) }
        var recs: [String] = []
        if let neg = f.firstNegativeWeek {
            recs.append("Cash is projected below zero in week \(neg.number) (week of \(ClientText.polish(neg.start.formatted))). Talk with the owner before then about collecting overdue invoices\(receivablesOver60.map { $0.minorUnits > 0 ? " (\($0.accountingDescription) is more than 60 days late)" : "" } ?? ""), timing non-urgent bill payments, or a line of credit.")
        } else {
            recs.append("No week goes below zero.")
        }
        recs.append("This is a projection from open invoices, open bills and recurring charges; add planned purchases on the Cash Flow Forecast page.")
        return InsightCard(title: "Cash Outlook", subtitle: "Projected ending cash, next 13 weeks", headline: f.startingCash.accountingDescription,
                           chart: .money(.line, pts, name: "Ending cash", markZero: true), rows: rows, recommendations: recs, footnote: footnote)
    }

    // MARK: Deadlines

    public static func deadlines(_ d: [ComplianceDeadline], checks: [ComplianceCheck], clientName: String) -> InsightCard {
        let rows = d.prefix(10).map { InsightRow(id: $0.id, label: ClientText.polish($0.date.formatted), detail: "\($0.title) — \($0.detail)") }
        var recs = checks.prefix(4).map { "\($0.title): \($0.detail)" }
        if recs.isEmpty { recs = ["Every date shown comes from rules checked on official sites or the IRS."] }
        return InsightCard(title: "What's Due", subtitle: "Filings and deliveries for \(clientName), next 120 days", headline: d.first.map { ClientText.polish($0.date.formatted) },
                           rows: Array(rows), recommendations: recs, footnote: "From the Compliance Calendar profile.")
    }

    // MARK: One account

    public static func account(_ a: LedgerAccount, postings: [LedgerTransaction], footnote: String) -> InsightCard {
        let bal = a.presentedBalance
        var recs: [String] = []
        let lower = a.name.lowercased()
        if a.hasAbnormalBalance {
            switch a.accountType {
            case .bank:
                recs.append("Overdrawn on the books. Compare to the bank statement: if the bank isn't overdrawn, a deposit is missing or a payment was posted to this account by mistake.")
            case .creditCard, .accountsPayable, .otherCurrentLiability, .longTermLiability:
                recs.append("This liability is on the wrong side: the books show more paid than owed. Usually a payment was recorded without the charge or bill it pays, or a payment was entered twice. Reconcile it to the statement.")
            default:
                recs.append("This balance is on the unusual side for a \(a.accountType.rawValue.lowercased()) account. Review the postings below for miscoding.")
            }
        } else if bal.minorUnits != 0 && (lower.contains("clearing") || lower.contains("suspense") || lower.contains("undeposited")) {
            recs.append("A clearing, suspense or Undeposited Funds account should be at zero at month end. Find the items sitting in it and move each to where it belongs.")
        } else {
            recs.append(a.accountType.isAssetOrLiability ? "Normal balance. Reconcile it to the statement each month." : "Income and expense accounts have no statement; review the transactions for miscoding.")
        }
        let rows = postings.sorted { $0.txnDate > $1.txnDate }.prefix(10).map { t in
            InsightRow(id: t.id, label: ClientText.polish(t.txnDate.formatted), detail: [kindLabel(t.entityKind), t.vendorName].compactMap { $0 }.joined(separator: " · "),
                       amountText: t.totalAmount.accountingDescription, link: .transaction(id: t.id, kind: t.entityKind))
        }
        let owedWord = a.isCreditNormal && a.accountType != .equity ? (a.hasAbnormalBalance ? " (overpaid)" : " owed") : ""
        return InsightCard(title: a.name, subtitle: "\(a.accountType.rawValue) account, current QuickBooks balance\(owedWord)", headline: bal.accountingDescription, headerLink: .account(a.id),
                           rows: Array(rows), recommendations: recs, footnote: rows.isEmpty ? "No postings to this account in the loaded data. \(footnote)" : "Latest postings in the loaded data. \(footnote)")
    }

    // MARK: A group of findings

    /// How to work this kind of discrepancy, in QuickBooks then back in the app.
    public static func guidance(for group: FactFindingGroup) -> [String] {
        switch group {
        case .duplicates: return ["Open both records of each pair in QuickBooks. Keep the one matched to the bank line; void or delete the other.", "If both are real (two identical charges really happened), dismiss the finding with a note."]
        case .miscategorizedOrUncategorized: return ["Open each transaction and recode it to the right account; ask the client about anything you can't identify.", "Use Batch Fixes for several at once once writes are enabled for this client."]
        case .personalExpense: return ["Confirm with the client, then recode personal charges to Owner's Draw (or a shareholder distribution or loan for corporations)."]
        case .negativeBalance: return ["Open the account register and compare to the statement: look for a missing deposit or charge, a payment entered twice, or a payment posted to the wrong account."]
        case .lateFeesOrOverdrafts: return ["Tell the client which fees were avoidable and why (late payment, low balance); set up reminders or autopay where it helps."]
        case .vendorPriceIncrease: return ["Compare the new charge with the vendor's invoice or contract; a price change is fine if expected, otherwise ask the client."]
        case .cleanupAssessment, .balanceSheetIntegrity: return ["Clearing, suspense and Undeposited Funds accounts should end the month at zero: find each item sitting there and move it to where it belongs.", "Opening Balance Equity should be zero once setup is done; reclassify it with the CPA's agreement."]
        case .allOpen: return ["Work the largest dollar items first, then the oldest."]
        }
    }

    public static func findings(_ list: [Finding], group: FactFindingGroup, title: String, footnote: String) -> InsightCard? {
        guard !list.isEmpty else { return nil }
        let sorted = list.sorted { abs($0.dollarExposure.minorUnits) > abs($1.dollarExposure.minorUnits) }
        let total = sum(sorted.map { Money(minorUnits: abs($0.dollarExposure.minorUnits), currency: $0.dollarExposure.currency) })
        func short(_ f: Finding) -> String {
            let t = ClientText.polish(f.title)
            return t.components(separatedBy: " — ").first ?? t
        }
        let top = sorted.prefix(10)
        let chart = InsightChartData(type: .hbar, categories: top.map(short),
                                     series: [.init(name: "Amount", values: top.map { abs($0.dollarExposure.majorUnitsDouble) }, valueTexts: top.map { $0.dollarExposure.accountingDescription })],
                                     ids: top.map(\.id))
        let rows = sorted.map { f in
            InsightRow(id: f.id, label: ClientText.polish(f.title), detail: [f.severity.rawValue.capitalized + " severity", f.proposedActions.first.map { "Fix: \($0.title)" }].compactMap { $0 }.joined(separator: " · "),
                       amountText: f.dollarExposure.accountingDescription, link: .finding(f.id), warn: f.severity == .high)
        }
        return InsightCard(title: title, subtitle: "\(list.count) open · largest first", headline: total.accountingDescription, chart: chart, rows: rows,
                           recommendations: guidance(for: group) + ["Say \"is it fixed\" after fixing one in QuickBooks; Voice Ledger re-checks it."], footnote: footnote)
    }

    // MARK: Spend by vendor

    public static func vendorSpend(_ vendors: [VendorSpendSummary.VendorTotal], footnote: String) -> InsightCard? {
        guard !vendors.isEmpty else { return nil }
        let total = sum(vendors.map(\.total))
        var recs: [String] = []
        if let top = vendors.first, total.minorUnits > 0 {
            let share = Int((Double(top.total.minorUnits) / Double(total.minorUnits) * 100).rounded())
            recs.append("\(top.vendorName) is \(share)% of the spend shown. Open the vendor in QuickBooks to check its charges are coded to the right accounts.")
        }
        recs.append("Ask Moneypenny about any vendor by name (\"find Hicks Hardware\") for its 12-month pattern and recent charges.")
        return InsightCard(title: "Spend by Vendor", subtitle: "Expenses and bills this month, largest first (customers excluded)", headline: total.accountingDescription,
                           chart: .money(.hbar, vendors.map { ($0.vendorName, $0.total) }, name: "Spend"),
                           rows: vendors.map { InsightRow(id: $0.id, label: $0.vendorName, detail: "\($0.transactionCount) transaction\($0.transactionCount == 1 ? "" : "s")", amountText: $0.total.accountingDescription, link: .vendor(id: nil, name: $0.vendorName)) },
                           recommendations: recs, footnote: footnote)
    }

    // MARK: New accounts

    public static func newAccounts(_ alerts: [NewAccountAlert]) -> InsightCard? {
        guard !alerts.isEmpty else { return nil }
        return InsightCard(title: "New Accounts in QuickBooks", subtitle: "Bank, card or loan accounts that appeared since an earlier sync", headline: "\(alerts.count)",
                           rows: alerts.map { InsightRow(id: $0.accountID, label: $0.name, detail: "\($0.type) · first seen \($0.firstSeenAt.formatted(date: .abbreviated, time: .omitted))", link: .account($0.accountID), warn: true) },
                           recommendations: ["Ask the client what each account is for and when it was opened.", "Request statements from the opening date and add each to the monthly reconciliation.", "Mark it added on the Dashboard once it's on your list."],
                           footnote: "Detected by comparing accounts between syncs.")
    }
}
