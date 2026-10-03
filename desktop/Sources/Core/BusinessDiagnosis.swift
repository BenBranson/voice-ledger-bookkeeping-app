import Foundation

/// Business Diagnosis (owner request 2026-10-02): a SWOT read of a client's
/// business — what's going right, what's going wrong, where the money goes.
/// Code computes and classifies every item from fixed, stated thresholds
/// (CLAUDE.md rule 1); each item carries its numbers and the basis it was
/// computed on. AI may only explain these items, never add one.
public enum BusinessDiagnosis {

    public enum Quadrant: String, Sendable, CaseIterable {
        case strength = "Strengths", weakness = "Weaknesses", opportunity = "Opportunities", threat = "Threats"
    }

    public struct Item: Identifiable, Sendable, Equatable {
        public let id: String
        public let quadrant: Quadrant
        public let title: String
        /// One line with the numbers: "12-month net margin 18.4% ($41,220 on $224,010 of revenue)".
        public let detail: String
        /// The amount the item is about, when there is one (for sorting and the headline).
        public let amount: Money?
        public let link: QBOTarget?
        /// How it was computed: "last 12 months through Sep 2026".
        public let basis: String
    }

    public struct Slice: Sendable, Equatable {
        public let label: String
        public let amount: Money
        public let share: Double
    }

    public struct Report: Sendable, Equatable {
        public let period: AccountingPeriod
        public let items: [Item]
        /// Top spending categories over the trailing months, largest first, plus "Everything else".
        public let whereMoneyGoes: [Slice]
        public let whereMoneyGoesBasis: String
        /// Month label → (revenue, net income), oldest first, for the trend chart.
        public let trend: [(String, Money, Money)]
        /// What couldn't be judged and why (gray, never silently dropped).
        public let notJudged: [String]

        public func items(_ q: Quadrant) -> [Item] { items.filter { $0.quadrant == q } }

        public static func == (a: Report, b: Report) -> Bool {
            a.period == b.period && a.items == b.items && a.whereMoneyGoes == b.whereMoneyGoes && a.notJudged == b.notJudged
                && a.trend.map { "\($0.0)|\($0.1.minorUnits)|\($0.2.minorUnits)" } == b.trend.map { "\($0.0)|\($0.1.minorUnits)|\($0.2.minorUnits)" }
        }
    }

    public struct Input: Sendable {
        public var period: AccountingPeriod
        /// Monthly P&Ls (the history snapshot), any order; months after `period` are ignored.
        public var monthly: [MonthlyReport]
        /// The reviewed month's live P&L; replaces that month in `monthly` when present.
        public var currentProfitAndLoss: [ReportLine]
        public var balanceSheet: [ReportLine]
        public var agedReceivables: [AgingLine]
        public var agedPayables: [AgingLine]
        /// Invoices etc. for customer concentration (the history snapshot's transactions).
        public var transactions: [LedgerTransaction]
        public var openFindings: [Finding]
        public var tieOut: [TieOut.Check]
        public var forecast: ThirteenWeekForecast?

        public init(period: AccountingPeriod, monthly: [MonthlyReport], currentProfitAndLoss: [ReportLine], balanceSheet: [ReportLine],
                    agedReceivables: [AgingLine], agedPayables: [AgingLine], transactions: [LedgerTransaction], openFindings: [Finding],
                    tieOut: [TieOut.Check], forecast: ThirteenWeekForecast?) {
            self.period = period; self.monthly = monthly; self.currentProfitAndLoss = currentProfitAndLoss; self.balanceSheet = balanceSheet
            self.agedReceivables = agedReceivables; self.agedPayables = agedPayables; self.transactions = transactions
            self.openFindings = openFindings; self.tieOut = tieOut; self.forecast = forecast
        }
    }

    // MARK: Thresholds (stated so every item can say why)

    static let strongNetMargin = 15.0, thinNetMargin = 5.0
    static let growthPercent = 10.0
    static let expenseRisePercent = 25.0, expenseRiseFloorCents: Int64 = 30_000
    static let lateReceivablesShare = 25.0
    static let concentrationShare = 30.0
    static let runwayStrongMonths = 3.0, runwayThreatMonths = 1.0

    // MARK: Helpers

    static func money(_ cents: Int64) -> Money { Money(minorUnits: cents, currency: .usd) }
    static func income(_ l: [ReportLine]) -> Int64 { (TieOut.total("Total Income", l) ?? money(0)).minorUnits }
    static func net(_ l: [ReportLine]) -> Int64 { (TieOut.total("Net Income", l) ?? money(0)).minorUnits }
    static func pct(_ a: Int64, _ b: Int64) -> Double? { b == 0 ? nil : Double(a) / Double(b) * 100 }
    static func label(_ p: AccountingPeriod) -> String { InsightCards.monthLabel(p) }
    static func span(_ months: [MonthlyReport]) -> String {
        guard let f = months.first?.period, let l = months.last?.period else { return "" }
        return f == l ? ReviewPeriod.label(f) : "\(label(f)) – \(label(l))"
    }
    static func before(_ a: AccountingPeriod, _ b: AccountingPeriod) -> Bool { (a.year, a.month) < (b.year, b.month) }

    // MARK: Build

    public static func build(_ input: Input) -> Report {
        // Months up to and including the reviewed one, oldest first, the reviewed month live.
        var months = input.monthly.filter { !before(input.period, $0.period) }.sorted { before($0.period, $1.period) }
        if !input.currentProfitAndLoss.isEmpty {
            months.removeAll { $0.period == input.period }
            months.append(MonthlyReport(period: input.period, lines: input.currentProfitAndLoss))
        }
        var items: [Item] = []
        var notJudged: [String] = []
        let t12 = Array(months.suffix(12)), t3 = Array(months.suffix(3)), prev3 = Array(months.dropLast(3).suffix(3))

        // Profitability (12 months).
        if t12.count >= 12 {
            let rev = t12.reduce(0) { $0 + income($1.lines) }, ni = t12.reduce(0) { $0 + net($1.lines) }
            if let m = pct(ni, rev) {
                let detail = String(format: "12-month net margin %.1f%%", m) + " (\(money(ni).accountingDescription) kept from \(money(rev).accountingDescription) of revenue)"
                if m >= strongNetMargin { items.append(Item(id: "margin", quadrant: .strength, title: "Healthy profit margin", detail: detail, amount: money(ni), link: nil, basis: "\(span(t12)); strong at \(Int(strongNetMargin))%+")) }
                else if m < thinNetMargin { items.append(Item(id: "margin", quadrant: .weakness, title: "Thin profit margin", detail: detail, amount: money(ni), link: nil, basis: "\(span(t12)); thin below \(Int(thinNetMargin))%")) }
            }
        } else {
            notJudged.append("Profit margin and revenue trend need 12 months of history (\(t12.count) loaded).")
        }

        // Revenue trend: last 3 months vs the same 3 months a year earlier, else vs the 3 before.
        if t3.count == 3 {
            let yearAgo = t3.compactMap { m in months.first { $0.period.year == m.period.year - 1 && $0.period.month == m.period.month } }
            let (base, basis) = yearAgo.count == 3 ? (yearAgo, "vs. the same months a year earlier") : (prev3, "vs. the 3 months before")
            if base.count == 3 {
                let now = t3.reduce(0) { $0 + income($1.lines) }, then = base.reduce(0) { $0 + income($1.lines) }
                if let change = pct(now - then, then), then > 0 {
                    let detail = String(format: "Revenue %@%.0f%%: %@ in %@ %@ (%@)", change >= 0 ? "+" : "−", abs(change),
                                        money(now).accountingDescription, span(t3), basis, money(then).accountingDescription)
                    if change >= growthPercent { items.append(Item(id: "growth", quadrant: .strength, title: "Revenue is growing", detail: detail, amount: money(now - then), link: nil, basis: "growth at \(Int(growthPercent))%+")) }
                    else if change <= -growthPercent { items.append(Item(id: "growth", quadrant: .weakness, title: "Revenue is shrinking", detail: detail, amount: money(now - then), link: nil, basis: "decline at \(Int(growthPercent))%+")) }
                }
            }
            // Losses in 2 of the last 3 months.
            let losses = t3.filter { net($0.lines) < 0 }
            if losses.count >= 2 {
                items.append(Item(id: "losses", quadrant: .threat, title: "Losing money most months",
                                  detail: "Net loss in \(losses.count) of the last 3 months (\(losses.map { label($0.period) }.joined(separator: ", ")))",
                                  amount: money(losses.reduce(0) { $0 + net($1.lines) }), link: nil, basis: span(t3)))
            }
        }

        // Expense categories that rose fastest (last 3 vs prior 3 months).
        if t3.count == 3, prev3.count == 3 {
            func byCategory(_ ms: [MonthlyReport]) -> [String: Int64] {
                var d: [String: Int64] = [:]
                for m in ms { for l in InsightCards.expenseLines(m.lines) { d[l.label, default: 0] += InsightCards.m(l.amount).minorUnits } }
                return d
            }
            let now = byCategory(t3), then = byCategory(prev3)
            let risers = now.compactMap { (k, v) -> (String, Int64, Int64)? in
                guard let p = then[k], p > 0, v - p >= expenseRiseFloorCents, let r = pct(v - p, p), r >= expenseRisePercent else { return nil }
                return (k, v, p)
            }.sorted { ($0.1 - $0.2) > ($1.1 - $1.2) }
            for (k, v, p) in risers.prefix(2) {
                let r = pct(v - p, p) ?? 0
                let holding = InsightCards.isHoldingAccount(k)
                items.append(Item(id: "rise-\(k)", quadrant: .weakness, title: holding ? "\(k) is growing" : "\(k) costs are rising",
                                  detail: String(format: "%@ in %@, up %.0f%% from %@", money(v).accountingDescription, span(t3), r, money(p).accountingDescription),
                                  amount: money(v - p), link: nil, basis: "rise of \(Int(expenseRisePercent))%+ and $\(expenseRiseFloorCents / 100)+ vs. the 3 months before"))
                if !holding {
                    items.append(Item(id: "trim-\(k)", quadrant: .opportunity, title: "Rein in \(k)",
                                      detail: "Bringing it back to its earlier level saves about \(money((v - p) / 3).accountingDescription) a month",
                                      amount: money(v - p), link: nil, basis: "the rise over \(span(t3))"))
                }
            }
        }

        // Where the money goes (12 months, or what's loaded).
        var spend: [String: Int64] = [:]
        for m in t12 { for l in InsightCards.expenseLines(m.lines) { spend[l.label, default: 0] += InsightCards.m(l.amount).minorUnits } }
        let totalSpend = spend.values.filter { $0 > 0 }.reduce(0, +)
        var slices: [Slice] = []
        if totalSpend > 0 {
            let ranked = spend.filter { $0.value > 0 }.sorted { $0.value > $1.value }
            for (k, v) in ranked.prefix(6) { slices.append(Slice(label: k, amount: money(v), share: Double(v) / Double(totalSpend) * 100)) }
            let rest = ranked.dropFirst(6).reduce(0) { $0 + $1.value }
            if rest > 0 { slices.append(Slice(label: "Everything else", amount: money(rest), share: Double(rest) / Double(totalSpend) * 100)) }
        }

        // Liquidity: cash runway and current ratio (month-end balance sheet).
        if let cash = TieOut.total("Total Bank Accounts", input.balanceSheet), t3.count == 3 {
            let costs = t3.reduce(0) { $0 + income($1.lines) - net($1.lines) } / 3
            if costs > 0 {
                let runway = Double(cash.minorUnits) / Double(costs)
                let detail = String(format: "%@ in the bank covers %.1f months of costs (%@ a month on average)", cash.accountingDescription, runway, money(costs).accountingDescription)
                if runway >= runwayStrongMonths { items.append(Item(id: "runway", quadrant: .strength, title: "Solid cash cushion", detail: detail, amount: cash, link: nil, basis: "\(span(t3)) average costs; strong at \(Int(runwayStrongMonths))+ months")) }
                else if runway < runwayThreatMonths { items.append(Item(id: "runway", quadrant: .threat, title: "Less than a month of cash", detail: detail, amount: cash, link: nil, basis: "\(span(t3)) average costs")) }
            }
        }
        if let cr = FinancialKPIs.currentRatio(from: input.balanceSheet), cr < 1 {
            items.append(Item(id: "current-ratio", quadrant: .threat, title: "Bills due exceed short-term assets",
                              detail: String(format: "Current ratio %.2f: every $1 due soon has $%.2f behind it", cr, cr), amount: nil, link: nil, basis: "month-end balance sheet"))
        }
        if let f = input.forecast, let neg = f.firstNegativeWeek {
            items.append(Item(id: "forecast", quadrant: .threat, title: "Cash projected to run out",
                              detail: "13-week forecast goes below zero in week \(neg.number) (week of \(ClientText.polish(neg.start.formatted))), at \(neg.endingCash.accountingDescription)",
                              amount: neg.endingCash, link: nil, basis: "open invoices, open bills and recurring charges from today"))
        }

        // Receivables: late money and the chance to collect it.
        if let totalLine = input.agedReceivables.last(where: { $0.isSummary && $0.label.uppercased() == "TOTAL" }) {
            let split = AgingSplit(totalLine)
            if split.owed.minorUnits > 0, split.over60Owed.minorUnits > 0, let share = pct(split.over60Owed.minorUnits, split.owed.minorUnits) {
                if share >= lateReceivablesShare {
                    items.append(Item(id: "late-ar", quadrant: .weakness, title: "Customers pay late",
                                      detail: String(format: "%.0f%% of what customers owe is over 60 days late (%@ of %@)", share, split.over60Owed.accountingDescription, split.owed.accountingDescription),
                                      amount: split.over60Owed, link: nil, basis: "aged receivables; flagged at \(Int(lateReceivablesShare))%+"))
                }
                let late = AgingSummary.topLevelRows(input.agedReceivables)
                    .map { ($0, max(0, InsightCards.m($0.days61to90).minorUnits) + max(0, InsightCards.m($0.days91AndOver).minorUnits)) }
                    .filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
                let who = late.prefix(3).map { "\($0.0.label) \(money($0.1).accountingDescription)" }.joined(separator: ", ")
                items.append(Item(id: "collect", quadrant: .opportunity, title: "Collect \(split.over60Owed.accountingDescription) of late invoices",
                                  detail: "Largest: \(who)", amount: split.over60Owed,
                                  link: late.first.map { .customer(id: $0.0.entityID, name: $0.0.label) }, basis: "aged receivables, over 60 days"))
            }
        }

        // Payables: bills over 60 days unpaid.
        if let ap = input.agedPayables.last(where: { $0.isSummary && $0.label.uppercased() == "TOTAL" }) {
            let late = AgingSplit(ap).over60Owed
            if late.minorUnits > 0 {
                items.append(Item(id: "late-ap", quadrant: .weakness, title: "Bills paid late",
                                  detail: "\(late.accountingDescription) of vendor bills are over 60 days past due", amount: late, link: nil, basis: "aged payables"))
            }
        }

        // Customer concentration (12 months of invoices, by billing name).
        if let last = t12.last?.period, let first = t12.first?.period, t12.count >= 6 {
            let start = AccountingDate(year: first.year, month: first.month, day: 1)
            let end = AccountingDate(year: last.year, month: last.month, day: last.daysInMonth)
            var billed: [String: Int64] = [:]
            for t in input.transactions where t.entityKind == .invoice && !t.isVoided && t.txnDate >= start && t.txnDate <= end {
                billed[t.vendorName ?? "(no name)", default: 0] += t.totalAmount.minorUnits
            }
            let total = billed.values.reduce(0, +)
            if total > 0, let top = billed.max(by: { $0.value < $1.value }), let share = pct(top.value, total), share >= concentrationShare {
                items.append(Item(id: "concentration", quadrant: .threat, title: "Depends on one customer",
                                  detail: String(format: "%@ is %.0f%% of sales billed (%@ of %@)", top.key, share, money(top.value).accountingDescription, money(total).accountingDescription),
                                  amount: money(top.value), link: .customer(id: nil, name: top.key), basis: "invoices \(span(t12)); flagged at \(Int(concentrationShare))%+"))
            }
        }

        // Books quality: they tie, and what's still open.
        let broken = input.tieOut.filter { if case .doesNotTie = $0.status { return true }; return false }
        if !input.tieOut.isEmpty, broken.isEmpty, input.tieOut.allSatisfy(\.status.tied) {
            items.append(Item(id: "ties", quadrant: .strength, title: "Books tie to QuickBooks",
                              detail: "All \(input.tieOut.count) tie-out checks agree to the cent", amount: nil, link: nil, basis: "self-checking math"))
        }
        if !input.openFindings.isEmpty {
            let exposure = input.openFindings.reduce(Int64(0)) { $0 + abs($1.dollarExposure.minorUnits) }
            items.append(Item(id: "findings", quadrant: .weakness, title: "Bookkeeping issues to clean up",
                              detail: "\(input.openFindings.count) open finding\(input.openFindings.count == 1 ? "" : "s") touching \(money(exposure).accountingDescription)",
                              amount: money(exposure), link: nil, basis: "Voice Ledger Health Scan, \(ReviewPeriod.label(input.period))"))
        }

        return Report(period: input.period, items: items, whereMoneyGoes: slices, whereMoneyGoesBasis: t12.isEmpty ? "" : span(t12),
                      trend: t12.map { (label($0.period), money(income($0.lines)), money(net($0.lines))) }, notJudged: notJudged)
    }
}
