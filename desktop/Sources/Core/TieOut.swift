import Foundation

/// Self-checking math (owner request 2026-10-02: "no matter what data we feed
/// it, it performs correctly"). After every sync the app proves its figures
/// agree with each other and with QuickBooks' own totals, to the cent, before
/// trusting them. A figure whose check fails is shown gray with "doesn't tie"
/// instead of a number that might be wrong (CLAUDE.md rule 5).
///
/// Pure arithmetic over the reports the sync already read. No tolerance: QBO
/// reports are in cents, so any difference is a real difference.
public enum TieOut {

    /// The figures a check vouches for. A failed check grays out these.
    public enum Figure: String, Sendable, CaseIterable {
        case balanceSheet, receivables, payables, netIncome, revenue, cash
    }

    public enum Status: Sendable, Equatable {
        case ties
        case doesNotTie(difference: Money)
        case notChecked(String)

        public var tied: Bool { if case .ties = self { return true }; return false }
    }

    public struct Check: Identifiable, Sendable, Equatable {
        public let id: String
        public let title: String
        /// "Total assets vs. total liabilities + equity"
        public let compares: String
        public let leftLabel: String
        public let left: Money?
        public let rightLabel: String
        public let right: Money?
        public let status: Status
        public let affects: [Figure]
    }

    public struct Input: Sendable {
        public var period: AccountingPeriod
        public var balanceSheet: [ReportLine]
        public var priorBalanceSheet: [ReportLine]
        public var profitAndLoss: [ReportLine]
        public var cashFlow: [ReportLine]
        public var trialBalance: [TrialBalanceLine]
        public var agedReceivables: [AgingLine]
        public var agedPayables: [AgingLine]
        public var accounts: [LedgerAccount]
        /// True when the aging is as of the period's last day (a finished month);
        /// false when it's as of today (the month in progress).
        public var agingIsPeriodEnd: Bool

        public init(period: AccountingPeriod, balanceSheet: [ReportLine], priorBalanceSheet: [ReportLine] = [], profitAndLoss: [ReportLine],
                    cashFlow: [ReportLine] = [], trialBalance: [TrialBalanceLine] = [], agedReceivables: [AgingLine] = [], agedPayables: [AgingLine] = [],
                    accounts: [LedgerAccount] = [], agingIsPeriodEnd: Bool) {
            self.period = period; self.balanceSheet = balanceSheet; self.priorBalanceSheet = priorBalanceSheet; self.profitAndLoss = profitAndLoss
            self.cashFlow = cashFlow; self.trialBalance = trialBalance; self.agedReceivables = agedReceivables; self.agedPayables = agedPayables
            self.accounts = accounts; self.agingIsPeriodEnd = agingIsPeriodEnd
        }
    }

    // MARK: Helpers

    static let usd = CurrencyCode.usd

    /// A top-level (depth 0) summary line by exact label. Sub-section labels repeat
    /// across sections ("Total Job Materials" is both an income and an expense
    /// subtotal), so only depth-0 totals are read here.
    static func total(_ label: String, _ lines: [ReportLine]) -> Money? {
        lines.first { $0.isSummary && $0.depth == 0 && $0.label == label }?.amount
            ?? lines.first { $0.isSummary && $0.label == label }?.amount
    }

    static func line(_ label: String, _ lines: [ReportLine]) -> Money? {
        lines.first { $0.label == label }?.amount
    }

    static func compare(_ id: String, _ title: String, _ compares: String, _ leftLabel: String, _ left: Money?, _ rightLabel: String, _ right: Money?,
                        affects: [Figure], missing: String) -> Check {
        guard let l = left, let r = right else {
            return Check(id: id, title: title, compares: compares, leftLabel: leftLabel, left: left, rightLabel: rightLabel, right: right,
                         status: .notChecked(missing), affects: affects)
        }
        let diff = l - r
        return Check(id: id, title: title, compares: compares, leftLabel: leftLabel, left: l, rightLabel: rightLabel, right: r,
                     status: diff.minorUnits == 0 ? .ties : .doesNotTie(difference: diff), affects: affects)
    }

    static func sum(_ xs: [Money]) -> Money { Money(minorUnits: xs.reduce(0) { $0 + $1.minorUnits }, currency: usd) }

    // MARK: The checks

    public static func run(_ input: Input) -> [Check] {
        var out: [Check] = []
        let bs = input.balanceSheet, pl = input.profitAndLoss

        // 1. The balance sheet balances.
        out.append(compare("bs-balances", "Balance sheet balances", "Total assets vs. total liabilities + equity",
                           "Total assets", total("TOTAL ASSETS", bs), "Liabilities + equity", total("TOTAL LIABILITIES AND EQUITY", bs),
                           affects: [.balanceSheet, .cash], missing: "The balance sheet isn't loaded."))

        // 2. Trial balance debits equal credits.
        if input.trialBalance.isEmpty {
            out.append(compare("tb-balances", "Trial balance balances", "Total debits vs. total credits", "Debits", nil, "Credits", nil,
                               affects: [.balanceSheet], missing: "The trial balance isn't loaded."))
        } else {
            let totalRow = input.trialBalance.last { $0.isSummary }
            let debits = totalRow?.debit ?? sum(input.trialBalance.filter { !$0.isSummary }.compactMap(\.debit))
            let credits = totalRow?.credit ?? sum(input.trialBalance.filter { !$0.isSummary }.compactMap(\.credit))
            out.append(compare("tb-balances", "Trial balance balances", "Total debits vs. total credits", "Debits", debits, "Credits", credits,
                               affects: [.balanceSheet], missing: ""))
        }

        // 3–4. Each aging report's rows add up to its own TOTAL (proves the report was read right:
        // a parent customer's own invoices live only on its "Total X" row).
        for (id, title, lines, figure) in [("ar-rows", "Who Owes Us adds up", input.agedReceivables, Figure.receivables),
                                           ("ap-rows", "What We Owe adds up", input.agedPayables, Figure.payables)] {
            let reportTotal = lines.last { $0.isSummary && $0.label.uppercased() == "TOTAL" }?.total
            let rows = lines.isEmpty ? nil : sum(AgingSummary.topLevelRows(lines).compactMap(\.total))
            out.append(compare(id, title, "Customer/vendor rows vs. the report's TOTAL", "Sum of rows", rows, "Report TOTAL", reportTotal,
                               affects: [figure], missing: "The aging report isn't loaded."))
        }

        // Open documents (aging detail) add up to the summary TOTAL: proves the exact
        // owed-before-credits split rests on the same money as the report.
        for (id, title, lines, figure) in [("ar-open", "Open invoices add up", input.agedReceivables, Figure.receivables),
                                           ("ap-open", "Open bills add up", input.agedPayables, Figure.payables)] {
            let totalLine = lines.last { $0.isSummary && $0.label.uppercased() == "TOTAL" }
            out.append(compare(id, title, "Each open document vs. the aging TOTAL", "Open documents", totalLine?.openItems?.net, "Report TOTAL", totalLine?.total,
                               affects: [figure], missing: lines.isEmpty ? "The aging report isn't loaded." : "The aging detail wasn't read."))
        }

        // 5–6. Aging TOTAL vs. the A/R or A/P balance on the same date.
        func agingTotal(_ lines: [AgingLine]) -> Money? { lines.last { $0.isSummary && $0.label.uppercased() == "TOTAL" }?.total }
        func currentBalance(_ type: LedgerAccountType, flip: Bool) -> Money? {
            let of = input.accounts.filter { $0.accountType == type }
            guard !of.isEmpty else { return nil }
            let s = of.reduce(Int64(0)) { $0 + $1.currentBalance.minorUnits }
            return Money(minorUnits: flip ? -s : s, currency: usd)
        }
        let sameDay = input.agingIsPeriodEnd ? "the balance sheet on the same day" : "the account balance today"
        out.append(compare("ar-tie", "Receivables tie", "Aging TOTAL vs. \(sameDay)", "Aging TOTAL", agingTotal(input.agedReceivables),
                           input.agingIsPeriodEnd ? "Balance sheet A/R" : "A/R account",
                           input.agingIsPeriodEnd ? total("Total Accounts Receivable", bs) : currentBalance(.accountsReceivable, flip: false),
                           affects: [.receivables], missing: "The aging report or the A/R balance isn't loaded."))
        out.append(compare("ap-tie", "Payables tie", "Aging TOTAL vs. \(sameDay)", "Aging TOTAL", agingTotal(input.agedPayables),
                           input.agingIsPeriodEnd ? "Balance sheet A/P" : "A/P account",
                           input.agingIsPeriodEnd ? total("Total Accounts Payable", bs) : currentBalance(.accountsPayable, flip: true),
                           affects: [.payables], missing: "The aging report or the A/P balance isn't loaded."))

        // 7. Profit math: income − cost of goods − expenses + other income − other expenses = net income,
        // step by step against QuickBooks' own subtotals.
        if let income = total("Total Income", pl), let net = total("Net Income", pl) {
            let cogs = total("Total Cost of Goods Sold", pl) ?? Money(minorUnits: 0, currency: usd)
            let expenses = total("Total Expenses", pl) ?? Money(minorUnits: 0, currency: usd)
            let netOther = total("Net Other Income", pl)
                ?? ((total("Total Other Income", pl) ?? Money(minorUnits: 0, currency: usd)) - (total("Total Other Expenses", pl) ?? Money(minorUnits: 0, currency: usd)))
            let gross = income - cogs
            var computed = gross - expenses + netOther
            var label = "Revenue − costs"
            // If QuickBooks shows a subtotal that disagrees, report the first step that breaks.
            if let qGross = total("Gross Profit", pl), qGross != gross { computed = gross; label = "Income − cost of goods"
                out.append(compare("pl-math", "Profit math", "Each step of the P&L vs. QuickBooks' subtotals", label, computed, "Gross profit", qGross, affects: [.netIncome, .revenue], missing: ""))
            } else if let qNOI = total("Net Operating Income", pl), qNOI != gross - expenses {
                out.append(compare("pl-math", "Profit math", "Each step of the P&L vs. QuickBooks' subtotals", "Gross profit − expenses", gross - expenses, "Net operating income", qNOI, affects: [.netIncome], missing: ""))
            } else {
                out.append(compare("pl-math", "Profit math", "Revenue − all costs vs. net income on the P&L", label, computed, "Net income", net, affects: [.netIncome, .revenue], missing: ""))
            }
        } else {
            out.append(compare("pl-math", "Profit math", "Revenue − all costs vs. net income on the P&L", "Revenue − costs", nil, "Net income", nil,
                               affects: [.netIncome, .revenue],
                               missing: pl.isEmpty ? "The profit and loss isn't loaded." : "The profit and loss has no Total Income or Net Income line."))
        }

        // 8. The month's profit lands on the balance sheet: the equity section's year-to-date
        // "Net Income" grows by exactly this month's net income. In the first month of a fiscal
        // year it restarts, so it then equals this month's net income outright.
        let monthNet = total("Net Income", pl)
        let bsNet = line("Net Income", bs), priorNet = line("Net Income", input.priorBalanceSheet)
        if let monthNet, let bsNet, let priorNet {
            let change = bsNet - priorNet
            let resetYear = change != monthNet && bsNet == monthNet
            out.append(compare("pl-to-bs", "Profit carries to the balance sheet",
                               resetYear ? "New fiscal year: balance sheet net income vs. this month's" : "Change in the balance sheet's net income vs. this month's P&L",
                               resetYear ? "Balance sheet net income" : "Change on the balance sheet", resetYear ? bsNet : change,
                               "P&L net income", monthNet, affects: [.netIncome, .balanceSheet], missing: ""))
        } else {
            out.append(compare("pl-to-bs", "Profit carries to the balance sheet", "Change in the balance sheet's net income vs. this month's P&L",
                               "Change on the balance sheet", nil, "P&L net income", nil, affects: [.netIncome],
                               missing: monthNet == nil ? "This month's net income isn't available."
                                   : input.priorBalanceSheet.isEmpty ? "Last month's balance sheet isn't loaded."
                                   : bs.isEmpty ? "This month's balance sheet isn't loaded." : "A balance sheet has no Net Income line."))
        }

        // 9. Cash: the cash flow statement's ending cash = bank accounts + Undeposited Funds
        // (QuickBooks counts payments waiting to be deposited as cash; verified 2026-10-02:
        // July 10,448.92 + 2,862.52 = 13,311.44).
        let undepositedIDs = Set(input.accounts.filter { $0.accountSubType == "UndepositedFunds" }.map(\.id))
        let undeposited = bs.first { !$0.isSummary && (($0.accountID.map(undepositedIDs.contains) ?? false) || $0.label == "Undeposited Funds") }?.amount
            ?? Money(minorUnits: 0, currency: usd)
        let bank = total("Total Bank Accounts", bs)
        out.append(compare("cash-tie", "Cash ties", "Cash flow ending cash vs. bank accounts + Undeposited Funds",
                           "Bank + Undeposited", bank.map { $0 + undeposited }, "Cash flow ending cash", line("Cash at end of period", input.cashFlow),
                           affects: [.cash], missing: "The cash flow statement or balance sheet isn't loaded."))
        return out
    }

    /// The figures that may NOT be shown as verified: any check that vouches for
    /// them and doesn't tie. (A check that couldn't run doesn't block a figure;
    /// that figure's own freshness/coverage rules already govern it.)
    public static func failing(_ checks: [Check]) -> Set<Figure> {
        Set(checks.filter { if case .doesNotTie = $0.status { return true }; return false }.flatMap(\.affects))
    }
}
