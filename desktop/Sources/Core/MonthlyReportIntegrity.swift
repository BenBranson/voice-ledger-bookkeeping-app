import Foundation

/// Report-integrity rules from the owner's review of the July 2026 sandbox
/// report (2026-09-29). Each one fixes a way the report could mislead:
/// balance findings read "as of today" shown in a period report, one item
/// counted three different ways, a bookkeeping plug presented as operating
/// loss, and two cash figures with no bridge between them. All figures are
/// computed here; the renderer only lays them out.

// MARK: - Client-facing text

public enum ClientText {
    private static let money = try! NSRegularExpression(pattern: #"(-?)USD (-?)(\d+)\.(\d{2})"#)
    private static let date = try! NSRegularExpression(pattern: #"\b(\d{4})-(\d{1,2})-(\d{1,2})\b"#)
    private static let shortMonths = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// Engine text → client text: `USD 25000.00` → `$25,000.00`,
    /// `-USD 12.00` → `($12.00)`, `2026-7-31` → `Jul 31, 2026`. Engine
    /// strings keep the `USD` form because in-app amount search matches it.
    public static func polish(_ text: String) -> String {
        var out = replace(money, in: text) { groups in
            guard let units = Int64(groups[3]), let cents = Int64(groups[4]) else { return nil }
            let negative = !groups[1].isEmpty || !groups[2].isEmpty
            let minor = units * 100 + cents
            return Money(minorUnits: negative ? -minor : minor, currency: .usd).accountingDescription
        }
        out = replace(date, in: out) { groups in
            guard let y = Int(groups[1]), let m = Int(groups[2]), let d = Int(groups[3]), (1...12).contains(m), (1...31).contains(d) else { return nil }
            return "\(shortMonths[m - 1]) \(d), \(y)"
        }
        return out
    }

    private static func replace(_ regex: NSRegularExpression, in text: String, _ transform: ([String]) -> String?) -> String {
        let ns = text as NSString
        var result = text
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            let groups = (0..<match.numberOfRanges).map { match.range(at: $0).location == NSNotFound ? "" : ns.substring(with: match.range(at: $0)) }
            guard let replacement = transform(groups), let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }
}

// MARK: - Open items: one status per item, one count everywhere

public struct ReportOpenItem: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case confirmed, possible, awaitingClient, awaitingVerification
    }

    public let findingID: String
    public let kind: Kind
    public let tag: String
    public let title: String
    public let amountText: String
    public let detail: String
    public let action: String?
    /// Other open items with the identical dollar amount — very likely the
    /// same underlying problem seen by two checks. Listed, never hidden.
    public let related: [String]
}

public enum ReportStatus {
    /// Rules that detect a *possibility* (a pattern that often means an
    /// error) rather than establish a fact from the data.
    static let suspicionRules: Set<String> = [
        "VL-DUP-BILL-001", "VL-DUP-EXP-001", "VL-DUP-EXP-002", "VL-DUP-INV-001", "VL-DUP-NEAR-001", "VL-DUP-PAY-001", "VL-DUP-VEND-001",
        "VL-VEND-ANOMALY-001", "VL-VEND-PRICE-001", "VL-TRANSPOSITION-001", "VL-PERSONAL-001", "VL-CAT-MISCODE-001",
        "VL-VENDOR-MISMATCH-001", "VL-RELATIONSHIP-003", "VL-RELATIONSHIP-005", "VL-FEE-AVOIDABLE-001", "VL-RECON-AMBIGUOUS-001"
    ]

    /// Rules whose finding is a balance read "as of the latest sync".
    static let balanceRules: Set<String> = ["VL-BS-NEGBAL-001", "VL-OBE-BALANCE-001", "VL-BS-SUSPENSE-001"]

    public static func label(_ kind: ReportOpenItem.Kind) -> String {
        switch kind {
        case .confirmed: return "Confirmed issue"
        case .possible: return "Possible issue"
        case .awaitingClient: return "Awaiting client"
        case .awaitingVerification: return "Awaiting verification"
        }
    }

    /// A balance finding re-checked against the period-end Balance Sheet.
    /// `nil` = the condition wasn't present at period end (the balance moved
    /// after the report date), so it doesn't belong in this month's report.
    static func periodEndBalance(_ finding: Finding, balanceSheet: [ReportLine]) -> (keep: Bool, amount: Money?) {
        guard balanceRules.contains(finding.ruleID.rawValue), !balanceSheet.isEmpty,
              let accountID = finding.evidence.first?.transactionID else { return (true, nil) }
        // An account absent from the Balance Sheet had a zero balance then.
        guard let amount = balanceSheet.first(where: { !$0.isSummary && $0.accountID == accountID })?.amount else { return (false, nil) }
        switch finding.ruleID.rawValue {
        // Balance Sheet shows assets and amounts owed as positive, so any
        // negative line is overdrawn / more paid than owed.
        case "VL-BS-NEGBAL-001": return (amount.minorUnits < 0, amount)
        default: return (amount.minorUnits != 0, amount)
        }
    }

    /// Open items for the report, excluding anything already shown in the
    /// work log as awaiting verification or client input (those count once,
    /// under that status).
    public static func openItems(findings: [Finding], workItems: [WorkItem], clientQuestions: [ClientQuestionDrafter.Thread], balanceSheet: [ReportLine], periodEndLabel: String) -> (items: [ReportOpenItem], droppedAfterPeriod: Int) {
        let workStatus = Dictionary(workItems.map { ($0.findingID, $0.status) }, uniquingKeysWith: { first, _ in first })
        let waitingOnClient = Set(clientQuestions.filter { $0.answer == nil }.map(\.findingID))
        var dropped = 0
        var prepared: [(Finding, ReportOpenItem.Kind, Money, String, String)] = []
        for finding in FindingTriage.sorted(findings.filter { $0.status == .open }) {
            let check = periodEndBalance(finding, balanceSheet: balanceSheet)
            guard check.keep else { dropped += 1; continue }
            var title = finding.title
            var detail = finding.narrative ?? ""
            var amount = finding.dollarExposure
            if let periodEnd = check.amount {
                let shown = Money(minorUnits: abs(periodEnd.minorUnits), currency: periodEnd.currency)
                if shown != finding.dollarExposure {
                    title = title.replacingOccurrences(of: finding.dollarExposure.description, with: shown.description)
                    detail = detail.replacingOccurrences(of: finding.dollarExposure.description, with: shown.description)
                        .replacingOccurrences(of: "as of the latest sync", with: "at \(periodEndLabel)")
                    detail += " (Balance at \(periodEndLabel): \(periodEnd.accountingDescription); the latest sync shows \(finding.dollarExposure.accountingDescription).)"
                } else {
                    detail = detail.replacingOccurrences(of: "as of the latest sync", with: "at \(periodEndLabel)")
                }
                amount = shown
            }
            let kind: ReportOpenItem.Kind
            if workStatus[finding.id] == .awaitingClient || waitingOnClient.contains(finding.id) { kind = .awaitingClient }
            else if workStatus[finding.id] == .awaitingVerification { kind = .awaitingVerification }
            else if suspicionRules.contains(finding.ruleID.rawValue) || finding.confidence != .high { kind = .possible }
            else { kind = .confirmed }
            prepared.append((finding, kind, amount, title, detail))
        }
        let items = prepared.map { finding, kind, amount, title, detail -> ReportOpenItem in
            let related = amount.minorUnits >= 10_000
                ? prepared.filter { $0.0.id != finding.id && $0.2 == amount }.map { ClientText.polish($0.3) + " (\(label($0.1).lowercased()))" }
                : []
            return ReportOpenItem(findingID: finding.id, kind: kind, tag: label(kind), title: ClientText.polish(title), amountText: amount.accountingDescription,
                                  detail: ClientText.polish(detail), action: finding.proposedActions.first.map { ClientText.polish($0.title) }, related: related)
        }
        return (items, dropped)
    }

    /// The single status summary every page uses.
    public static func summary(workItems: [WorkItem], openItems: [ReportOpenItem]) -> [MonthlyClientReport.Row] {
        let work = Dictionary(grouping: workItems, by: \.status).mapValues(\.count)
        let open = Dictionary(grouping: openItems, by: \.kind).mapValues(\.count)
        // Work-log items still awaiting something are open findings too;
        // count each finding once, under the open-item status.
        let openIDs = Set(openItems.map(\.findingID))
        let workOnly = { (s: WorkItem.Status) in workItems.filter { $0.status == s && !openIDs.contains($0.findingID) }.count }
        let rows: [(String, Int)] = [
            ("Corrected and verified", work[.correctedVerified] ?? 0),
            ("Awaiting verification", (open[.awaitingVerification] ?? 0) + workOnly(.awaitingVerification)),
            ("Awaiting client", (open[.awaitingClient] ?? 0) + workOnly(.awaitingClient)),
            ("Confirmed issues open", open[.confirmed] ?? 0),
            ("Possible issues to review", open[.possible] ?? 0),
            ("Reviewed — not an error", work[.notAnError] ?? 0)
        ]
        return rows.map { MonthlyClientReport.Row(label: $0.0, valueText: "\($0.1)", depth: 0, isTotal: false) }
    }
}

// MARK: - Operating result vs reported result

public struct PerformanceBridge: Codable, Sendable {
    public let rows: [MonthlyClientReport.Row]
    public let adjustmentsText: String
    public let beforeAdjustmentsText: String
    public let reportedText: String
    public let note: String?
}

public enum PerformanceAnalysis {
    /// P&L accounts that hold bookkeeping entries rather than business
    /// activity. QBO creates "Reconciliation Discrepancies" when a
    /// reconciliation is forced closed (VL-FORCED-RECON-001).
    static let adjustmentAccounts: Set<String> = ["reconciliation discrepancies"]
    /// Holding accounts for real spending not yet classified.
    static let unclassifiedAccounts: Set<String> = ["ask my accountant", "uncategorized expense"]

    static func sum(_ lines: [ReportLine], _ names: Set<String>) -> Money {
        lines.filter { !$0.isSummary && names.contains($0.label.lowercased()) }.compactMap(\.amount).reduce(.zero, +)
    }

    public static func adjustments(_ lines: [ReportLine]) -> Money { sum(lines, adjustmentAccounts) }
    public static func unclassified(_ lines: [ReportLine]) -> Money { sum(lines, unclassifiedAccounts) }

    /// Reported net income split into the result before bookkeeping
    /// adjustments and the adjustments themselves. `nil` when there is
    /// nothing to separate or the parts don't tie to QuickBooks' net income.
    public static func bridge(_ lines: [ReportLine]) -> PerformanceBridge? {
        guard let revenue = MonthlyReportBuilder.summary("Total Income", lines),
              let net = TaxEstimate.netIncome(from: lines),
              let costs = MonthlyReportBuilder.totalCosts(lines) else { return nil }
        let adj = adjustments(lines)
        let parked = unclassified(lines)
        guard adj.minorUnits != 0 || parked.minorUnits != 0 else { return nil }
        let otherIncome = MonthlyReportBuilder.summary("Total Other Income", lines) ?? .zero
        let before = net + adj
        let costsExcluding = costs - adj
        guard revenue + otherIncome - costsExcluding == before else { return nil }
        typealias Row = MonthlyClientReport.Row
        var rows = [Row(label: "Revenue", valueText: revenue.accountingDescription, depth: 0, isTotal: false)]
        if otherIncome.minorUnits != 0 { rows.append(Row(label: "Other income", valueText: otherIncome.accountingDescription, depth: 0, isTotal: false)) }
        rows.append(Row(label: "Costs of running the business", valueText: Money(minorUnits: -costsExcluding.minorUnits, currency: .usd).accountingDescription, depth: 0, isTotal: false))
        rows.append(Row(label: "Result before bookkeeping adjustments", valueText: before.accountingDescription, depth: 0, isTotal: true))
        if adj.minorUnits != 0 {
            rows.append(Row(label: "Reconciliation adjustment (bookkeeping entry under review)", valueText: Money(minorUnits: -adj.minorUnits, currency: .usd).accountingDescription, depth: 0, isTotal: false))
        }
        rows.append(Row(label: "Reported net income (QuickBooks)", valueText: net.accountingDescription, depth: 0, isTotal: true))
        let note = parked.minorUnits != 0
            ? "\(parked.accountingDescription) of the costs above sits in a holding account (such as Ask My Accountant) until it is classified. It is real spending, so it stays in the result; only its category is unknown."
            : nil
        return PerformanceBridge(rows: rows, adjustmentsText: adj.accountingDescription, beforeAdjustmentsText: before.accountingDescription, reportedText: net.accountingDescription, note: note)
    }
}

// MARK: - Year to date

public enum YearToDate {
    public static func rows(months: [MonthlyReport], period: AccountingPeriod) -> (rows: [MonthlyClientReport.ComparativeRow], label: String)? {
        let ytd = months.filter { $0.period.year == period.year && $0.period.month <= period.month }
        guard let current = ytd.first(where: { $0.period == period }), ytd.count >= 2 else { return nil }
        let active = ytd.filter { $0.lines.contains { !$0.isSummary && ($0.amount?.minorUnits ?? 0) != 0 } }.count
        func total(_ f: ([ReportLine]) -> Money?) -> Money { ytd.compactMap { f($0.lines) }.reduce(.zero, +) }
        let measures: [(String, ([ReportLine]) -> Money?)] = [
            ("Revenue", { MonthlyReportBuilder.summary("Total Income", $0) }),
            ("Costs of running the business", { l in MonthlyReportBuilder.totalCosts(l).map { $0 - PerformanceAnalysis.adjustments(l) } }),
            ("Bookkeeping adjustments", { PerformanceAnalysis.adjustments($0) }),
            ("Reported net income", { TaxEstimate.netIncome(from: $0) })
        ]
        let rows = measures.map { name, f in
            MonthlyClientReport.ComparativeRow(label: name, currentText: (f(current.lines) ?? .zero).accountingDescription, priorText: total(f).accountingDescription, depth: 0, isTotal: name == "Reported net income")
        }
        let label = "January–\(MonthlyReportBuilder.monthNames[period.month - 1]) \(period.year) · \(active) of \(period.month) month\(period.month == 1 ? "" : "s") with recorded activity"
        return (rows, label)
    }
}

// MARK: - Cash tie-out

public enum CashTie {
    /// Bank balances + Undeposited Funds, checked against the Statement of
    /// Cash Flows' ending cash — the two cash figures a reader sees.
    public static func rows(balanceSheet: [ReportLine], cashFlow: [ReportLine]) -> (rows: [MonthlyClientReport.Row], ties: Bool, detail: String)? {
        guard let bank = MonthlyReportBuilder.summary("Total Bank Accounts", balanceSheet),
              let ending = MonthlyReportBuilder.summary("Cash at end of period", cashFlow) else { return nil }
        let undeposited = balanceSheet.first { !$0.isSummary && $0.label.lowercased() == "undeposited funds" }?.amount ?? .zero
        typealias Row = MonthlyClientReport.Row
        var rows = [Row(label: "Bank accounts (Balance Sheet)", valueText: bank.accountingDescription, depth: 0, isTotal: false)]
        if undeposited.minorUnits != 0 {
            rows.append(Row(label: "Undeposited funds (received, not yet deposited)", valueText: undeposited.accountingDescription, depth: 0, isTotal: false))
        }
        rows.append(Row(label: "Cash used in the Statement of Cash Flows", valueText: (bank + undeposited).accountingDescription, depth: 0, isTotal: true))
        let gap = ending - (bank + undeposited)
        if gap.minorUnits != 0 {
            rows.append(Row(label: "Not explained by the accounts above", valueText: gap.accountingDescription, depth: 0, isTotal: false))
        }
        let detail = gap.minorUnits == 0
            ? "Bank \(bank.accountingDescription) + undeposited \(undeposited.accountingDescription) = cash-flow ending cash \(ending.accountingDescription)"
            : "Bank + undeposited = \((bank + undeposited).accountingDescription) vs cash-flow ending cash \(ending.accountingDescription)"
        return (rows, gap.minorUnits == 0, detail)
    }
}

// MARK: - Aging with credits kept apart

public struct AgingSplit: Sendable {
    public let owed: Money
    public let credits: Money
    public let over60Owed: Money
    public let net: Money

    /// Negative buckets are customer credits or unapplied payments, not
    /// money owed; they are reported separately, never netted into "old".
    public init(_ total: AgingLine) {
        // Exact, from the open documents, whenever the detail was read and ties.
        if let o = total.openItems, total.total == nil || total.total == o.net {
            owed = o.owed; credits = o.credits; over60Owed = o.over60Owed; net = total.total ?? o.net
            return
        }
        let buckets = [total.current, total.days1to30, total.days31to60, total.days61to90, total.days91AndOver].map { $0 ?? .zero }
        owed = buckets.filter { $0.minorUnits > 0 }.reduce(.zero, +)
        credits = buckets.filter { $0.minorUnits < 0 }.reduce(.zero, +)
        over60Owed = [total.days61to90, total.days91AndOver].map { $0 ?? .zero }.filter { $0.minorUnits > 0 }.reduce(.zero, +)
        net = total.total ?? (owed + credits)
    }
}
