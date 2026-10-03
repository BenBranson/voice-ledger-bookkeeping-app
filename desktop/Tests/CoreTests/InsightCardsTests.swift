import Testing
import Foundation
@testable import Core

@Suite("Insight cards")
struct InsightCardsTests {
    func usd(_ d: Int64) -> Money { Money(minorUnits: d * 100, currency: .usd) }
    func line(_ label: String, current: Int64 = 0, d30: Int64 = 0, d90: Int64 = 0, d91: Int64 = 0, summary: Bool = false, id: String? = nil) -> AgingLine {
        AgingLine(label: label, current: usd(current), days1to30: usd(d30), days31to60: usd(0), days61to90: usd(d90), days91AndOver: usd(d91),
                  total: usd(current + d30 + d90 + d91), depth: 0, isSummary: summary, entityID: id)
    }

    @Test("Receivables card: headline is the report TOTAL; late, over-90 and credit recommendations; customer links")
    func receivables() {
        let lines = [line("Amy", d91: 239, id: "1"), line("Cool Cars", d30: 1_000, d90: -800, id: "2"), line("Kate", current: 891, id: "3"), line("Bob", current: -50, id: "4"),
                     line("TOTAL", current: 841, d30: 1_000, d90: -800, d91: 239, summary: true)]
        let card = InsightCards.aging(lines, receivables: true, footnote: "f")!
        #expect(card.headline == "$1,280.00")
        #expect(card.recommendations.contains { $0.contains("over 90 days ($239.00)") })
        #expect(card.recommendations.contains { $0.contains("credit") })
        #expect(card.rows.first { $0.label == "Amy" }?.link == .customer(id: "1", name: "Amy"))
        #expect(card.chart?.type == .hstackedBar)
    }

    func txn(_ id: String, _ kind: QBOEntityKind, _ name: String, _ d: Int64, _ m: Int, _ day: Int = 5) -> LedgerTransaction {
        LedgerTransaction(id: id, entityKind: kind, vendorName: name, txnDate: AccountingDate(year: 2026, month: m, day: day), totalAmount: usd(d),
                          paymentAccountID: nil, docNumber: nil, isVoided: false, memo: nil, provenance: .qboAPI(readAt: Date()))
    }

    @Test("Vendor card: 12 monthly bars, transaction links, flags a price jump and a same-day duplicate")
    func vendor() {
        let t = [txn("1", .purchase, "Hicks Hardware", 100, 4), txn("2", .purchase, "Hicks Hardware", 100, 5), txn("3", .purchase, "Hicks Hardware", 100, 6),
                 txn("4", .purchase, "Hicks Hardware", 200, 9), txn("5", .purchase, "Hicks Hardware", 200, 9)]
        let card = InsightCards.counterparty("hicks", transactions: t, asOf: AccountingDate(year: 2026, month: 9, day: 30), footnote: "f")!
        #expect(card.title == "Hicks Hardware" && card.chart?.categories.count == 12 && card.headline == "$700.00")
        #expect(card.recommendations.contains { $0.contains("above the recent average") })
        #expect(card.recommendations.contains { $0.contains("duplicate") })
        #expect(card.rows.first?.link == .transaction(id: "4", kind: .purchase) || card.rows.first?.link == .transaction(id: "5", kind: .purchase))
    }

    @Test("Net income trend flags loss months; cash outlook flags the first negative week")
    func trendAndCash() {
        func month(_ m: Int, _ income: Int64, _ net: Int64) -> MonthlyReport {
            MonthlyReport(period: AccountingPeriod(year: 2026, month: m), lines: [ReportLine(label: "Total Income", amount: usd(income), depth: 0, isSummary: true),
                                                                                  ReportLine(label: "Net Income", amount: usd(net), depth: 0, isSummary: true)])
        }
        let card = InsightCards.trend(.netIncome, monthly: [month(5, 10_000, 1_000), month(6, 10_000, -500), month(7, 10_000, 2_000)], focus: AccountingPeriod(year: 2026, month: 6), footnote: "f")
        #expect(card?.recommendations.contains { $0.contains("1 of the last 3 months show a loss") } == true)
        #expect(card?.headline == "($500.00)")                                    // the reviewed month, not the latest
        #expect(card?.recommendations.first?.hasPrefix("June 2026: ($500.00)") == true)
        let f = ThirteenWeekForecastEngine.compute(currentCash: usd(100), agedReceivablesLines: [], agedPayablesLines: [line("V", current: 400)], recurringVendors: [], planned: [], asOf: AccountingDate(year: 2026, month: 10, day: 2))
        let cash = InsightCards.cashOutlook(f, receivablesOver60: nil, footnote: "f")
        #expect(cash.recommendations.first?.contains("below zero in week 2") == true)
        #expect(cash.chart?.markZero == true)
    }
}

@Suite("Aging: parent customers' own invoices (owner test 2026-10-02)")
struct AgingParentOwnTests {
    func usd(_ c: Int64) -> Money { Money(minorUnits: c, currency: .usd) }
    func row(_ label: String, d91: Int64?, depth: Int, summary: Bool = false, id: String? = nil) -> AgingLine {
        AgingLine(label: label, current: d91 == nil ? nil : usd(0), days1to30: nil, days31to60: nil, days61to90: nil, days91AndOver: d91.map(usd),
                  total: d91.map(usd), depth: depth, isSummary: summary, entityID: id)
    }

    @Test("Freeman's own $2,169.61 (only on its Total line) counts in totals and in its row")
    func freeman() {
        let lines = [
            row("Amy's Bird Sanctuary", d91: 23_900, depth: 0, id: "1"),
            row("Freeman Sporting Goods", d91: nil, depth: 0, id: "8"),          // header, no values
            row("0969 Ocean View Road", d91: 47_750, depth: 1, id: "9"),
            row("55 Twin Lane", d91: 8_500, depth: 1, id: "10"),
            row("Total Freeman Sporting Goods", d91: 273_211, depth: 0, summary: true),
            row("TOTAL", d91: 297_111, depth: 0, summary: true)
        ]
        let top = AgingSummary.topLevelRows(lines)
        #expect(top.map(\.label) == ["Amy's Bird Sanctuary", "Freeman Sporting Goods"])
        #expect(top.last?.days91AndOver == usd(273_211) && top.last?.entityID == "8")
        #expect(AgingSummary.bucketTotals(lines)?.days91AndOver == usd(297_111))
        let card = InsightCards.aging(lines, receivables: true, footnote: "")!
        #expect(card.recommendations.first?.contains("($2,971.11)") == true)
    }
}

@Suite("Balances read the way the Balance Sheet does")
struct PresentedBalanceTests {
    func usd(_ c: Int64) -> Money { Money(minorUnits: c, currency: .usd) }
    @Test("Liabilities stored negative are normal; spoken as owed")
    func signs() {
        #expect(ClientFacts.balanceSentence(name: "Mastercard", type: .creditCard, rawBalance: usd(-122_270)) == "We owe $1,222.70 on Mastercard.")
        #expect(ClientFacts.balanceSentence(name: "Checking", type: .bank, rawBalance: usd(1_440_803)) == "Checking has $14,408.03.")
        #expect(ClientFacts.balanceSentence(name: "Sweeper", type: .bank, rawBalance: usd(-329_302)) == "Sweeper is overdrawn by $3,293.02.")
        #expect(ClientFacts.balanceSentence(name: "Visa", type: .creditCard, rawBalance: usd(15_772)).contains("overpaid"))
        let card = InsightCards.account(LedgerAccount(id: "1", name: "Mastercard", accountType: .creditCard, currentBalance: usd(-122_270)), postings: [], footnote: "")
        #expect(card.headline == "$1,222.70" && card.recommendations.first?.hasPrefix("Normal balance") == true)
    }
}

@Suite("Statement cards (expenses, income vs expenses, financial health)")
struct StatementCardsTests {
    func usd(_ d: Int64) -> Money { Money(minorUnits: d * 100, currency: .usd) }
    let jul = AccountingPeriod(year: 2026, month: 7)
    var pl: [ReportLine] {
        [ReportLine(label: "Sales", amount: usd(10_000), depth: 1, isSummary: false),
         ReportLine(label: "Total Income", amount: usd(10_000), depth: 0, isSummary: true),
         ReportLine(label: "Gross Profit", amount: usd(10_000), depth: 0, isSummary: true),
         ReportLine(label: "Rent", amount: usd(3_000), depth: 1, isSummary: false, accountID: "50"),
         ReportLine(label: "Fuel", amount: usd(1_000), depth: 1, isSummary: false, accountID: "51"),
         ReportLine(label: "Reconciliation Discrepancies", amount: usd(2_000), depth: 1, isSummary: false, accountID: "52"),
         ReportLine(label: "Net Income", amount: usd(4_000), depth: 0, isSummary: true)]
    }
    var prior: [ReportLine] {
        [ReportLine(label: "Total Income", amount: usd(9_000), depth: 0, isSummary: true),
         ReportLine(label: "Gross Profit", amount: usd(9_000), depth: 0, isSummary: true),
         ReportLine(label: "Rent", amount: usd(3_000), depth: 1, isSummary: false),
         ReportLine(label: "Fuel", amount: usd(500), depth: 1, isSummary: false),
         ReportLine(label: "Net Income", amount: usd(5_500), depth: 0, isSummary: true)]
    }

    @Test("Expense card: category links open its largest transaction; holding accounts and big movers get advice")
    func expenses() {
        let t = [LedgerTransaction(id: "900", entityKind: .purchase, vendorName: "Chevron", txnDate: AccountingDate(year: 2026, month: 7, day: 3), totalAmount: usd(600),
                                   paymentAccountID: nil, docNumber: nil, isVoided: false, memo: nil, lineAccountIDs: ["51"], provenance: .qboAPI(readAt: Date())),
                 LedgerTransaction(id: "901", entityKind: .purchase, vendorName: "Shell", txnDate: AccountingDate(year: 2026, month: 7, day: 9), totalAmount: usd(400),
                                   paymentAccountID: nil, docNumber: nil, isVoided: false, memo: nil, lineAccountIDs: ["51"], provenance: .qboAPI(readAt: Date()))]
        let card = InsightCards.expenses(pl, prior: prior, transactions: t, pareto: false, period: jul, footnote: "f")!
        #expect(card.headline == "$6,000.00")
        let fuel = card.rows.first { $0.label == "Fuel" }!
        #expect(fuel.link == .transaction(id: "900", kind: .purchase))
        #expect(fuel.detail.contains("last month $500.00"))
        #expect(card.rows.first { $0.label == "Rent" }!.link == nil)        // no transactions loaded → no link, never a general page
        #expect(card.rows.first { $0.label == "Reconciliation Discrepancies" }!.warn)
        #expect(card.recommendations.contains { $0.contains("Reconciliation Discrepancies") && $0.contains("isn't real spending") })
        #expect(card.recommendations.contains { $0.contains("Fuel rose from $500.00 to $1,000.00") })
        let pareto = InsightCards.expenses(pl, prior: prior, transactions: t, pareto: true, period: jul, footnote: "f")!
        #expect(pareto.recommendations.contains { $0.contains("2 of 3 categories make up 80%") })
    }

    @Test("Income vs expenses: this month vs last, figures add up")
    func incomeVsExpenses() {
        let card = InsightCards.incomeVsExpenses(pl, prior: prior, period: jul, footnote: "f")!
        #expect(card.headline == "$4,000.00")
        #expect(card.rows.first { $0.id == "exp" }!.amountText == "$6,000.00")
        #expect(card.chart?.series.count == 2)
        #expect(card.recommendations.contains { $0.contains("fell from $5,500.00 to $4,000.00") })
    }

    @Test("Financial health: ratios computed by code, thresholds explained, register links on balance-sheet accounts")
    func health() {
        let bs = [ReportLine(label: "Total Bank Accounts", amount: usd(1_000), depth: 1, isSummary: true),
                  ReportLine(label: "Total Accounts Receivable", amount: usd(2_000), depth: 1, isSummary: true),
                  ReportLine(label: "Total Current Assets", amount: usd(3_000), depth: 0, isSummary: true),
                  ReportLine(label: "Total Accounts Payable", amount: usd(2_500), depth: 1, isSummary: true),
                  ReportLine(label: "Total Current Liabilities", amount: usd(4_000), depth: 0, isSummary: true)]
        let accounts = [LedgerAccount(id: "35", name: "Checking", accountType: .bank, currentBalance: usd(1_000))]
        let card = InsightCards.financialHealth(balanceSheet: bs, profitAndLoss: pl, accounts: accounts, focus: .currentRatio, period: jul, footnote: "f")!
        #expect(card.headline == "0.75 to 1")
        #expect(card.rows.first { $0.id == "wc" }!.amountText == "($1,000.00)")
        #expect(card.rows.first { $0.id == "cash" }!.link == .account("35"))
        #expect(card.recommendations.contains { $0.contains("exceed short-term assets") })
    }
}

@Suite("Spoken names match QuickBooks names")
struct NameMatchTests {
    @Test("& as 'and', punctuation and spaces ignored, case ignored")
    func matches() {
        #expect(ClientFacts.nameMatches("PG&E", "pg and e"))
        #expect(ClientFacts.nameMatches("PG&E", "pgande"))
        #expect(ClientFacts.nameMatches("Diego's Road Warrior Bodyshop", "diegos road warrior"))
        #expect(ClientFacts.nameMatches("VL Spike Permian Supply, Inc.", "permian supply inc"))
        #expect(!ClientFacts.nameMatches("Hicks Hardware", "norton"))
        #expect(!ClientFacts.nameMatches("Hicks Hardware", ""))
    }
}

@Suite("Balance-sheet rules read the reviewed month's ending balance, not today's")
struct PeriodEndBalanceTests {
    let realm = RealmID(rawValue: "9341456442848752")
    let jul = AccountingPeriod(year: 2026, month: 7)
    func usd(_ cents: Int64) -> Money { Money(minorUnits: cents, currency: .usd) }

    @Test("Live case 2026-10-02: OBE was $8,337.50 on July 31 while today's balance is $9,247.50; July's finding must say $8,337.50")
    func obeUsesJuly31() {
        let obe = LedgerAccount(id: "2", name: "Opening Balance Equity", accountType: .equity, accountSubType: "OpeningBalanceEquity", currentBalance: usd(924_750))
        let bs = [ReportLine(label: "Opening Balance Equity", amount: usd(-833_750), depth: 2, isSummary: false, accountID: "2")]
        let data = NormalizedDataSet(realmID: realm, period: jul, transactions: [], accounts: [obe], balanceSheetLines: bs,
                                     coverage: .complete, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false))
        #expect(data.periodEndBalance(of: obe) == usd(833_750))
        let ctx = RuleContext(period: jul, materiality: .defaultPolicy, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false))
        guard case .findings(let f) = OpeningBalanceEquityRule.evaluate(data, context: ctx) else { Issue.record("expected a finding"); return }
        #expect(f.first?.dollarExposure == usd(833_750))
    }

    @Test("Sign conventions: an asset reads as-is; a liability flips (A/P 3,913.76 on the report = -3,913.76 CurrentBalance); absent = zero")
    func signs() {
        let checking = LedgerAccount(id: "35", name: "Checking", accountType: .bank, currentBalance: usd(1_440_803))
        let ap = LedgerAccount(id: "33", name: "Accounts Payable (A/P)", accountType: .accountsPayable, currentBalance: usd(-352_360))
        let newer = LedgerAccount(id: "99", name: "Opened in September", accountType: .bank, currentBalance: usd(50_000))
        let bs = [ReportLine(label: "Checking", amount: usd(1_194_194), depth: 2, isSummary: false, accountID: "35"),
                  ReportLine(label: "Accounts Payable (A/P)", amount: usd(391_376), depth: 2, isSummary: false, accountID: "33")]
        let data = NormalizedDataSet(realmID: realm, period: jul, transactions: [], accounts: [checking, ap, newer], balanceSheetLines: bs,
                                     coverage: .complete, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false))
        #expect(data.periodEndBalance(of: checking) == usd(1_194_194))
        #expect(data.periodEndBalance(of: ap) == usd(-391_376))
        #expect(data.periodEndBalance(of: newer) == usd(0))
        let noReport = NormalizedDataSet(realmID: realm, period: jul, transactions: [], accounts: [checking], coverage: .complete, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false))
        #expect(noReport.periodEndBalance(of: checking) == usd(1_440_803))
    }
}

@Suite("Review month (was hard-coded to July 2026)")
struct ReviewPeriodTests {
    let oct2 = AccountingDate(year: 2026, month: 10, day: 2)
    @Test("Default is the last completed month; January rolls back a year")
    func defaults() {
        #expect(ReviewPeriod.lastCompleted(today: oct2) == AccountingPeriod(year: 2026, month: 9))
        #expect(ReviewPeriod.lastCompleted(today: AccountingDate(year: 2027, month: 1, day: 5)) == AccountingPeriod(year: 2026, month: 12))
        #expect(ReviewPeriod.choices(today: oct2).first == AccountingPeriod(year: 2026, month: 10))
        #expect(ReviewPeriod.choices(today: oct2).count == 13)
    }
    @Test("Spoken months resolve to the most recent one that isn't in the future")
    func spoken() {
        #expect(ReviewPeriod.spoken("september", today: oct2) == AccountingPeriod(year: 2026, month: 9))
        #expect(ReviewPeriod.spoken("sept", today: oct2) == AccountingPeriod(year: 2026, month: 9))
        #expect(ReviewPeriod.spoken("november", today: oct2) == AccountingPeriod(year: 2025, month: 11))
        #expect(ReviewPeriod.spoken("august 2025", today: oct2) == AccountingPeriod(year: 2025, month: 8))
        #expect(ReviewPeriod.spoken("mastercard", today: oct2) == nil)
        #expect(ReviewPeriod.spoken("may report", today: oct2) == nil)
        #expect(ReviewPeriod.parse(ReviewPeriod.key(AccountingPeriod(year: 2026, month: 9))) == AccountingPeriod(year: 2026, month: 9))
    }
}

@Suite("Cost lines: cost of goods and other expenses in, income out")
struct CostLinesTests {
    func usd(_ d: Double) -> Money { Money(minorUnits: Int64((d * 100).rounded()), currency: .usd) }
    @Test("Eval catch 2026-10-03: expense categories add up to revenue − net income + other income")
    func costLinesTie() {
        let pl = [ReportLine(label: "Sales", amount: usd(15_522.48), depth: 1, isSummary: false),
                  ReportLine(label: "Total Income", amount: usd(15_522.48), depth: 0, isSummary: true),
                  ReportLine(label: "Cost of Goods Sold", amount: nil, depth: 0, isSummary: false),
                  ReportLine(label: "Cost of Goods Sold", amount: usd(160), depth: 1, isSummary: false),
                  ReportLine(label: "Total Cost of Goods Sold", amount: usd(160), depth: 0, isSummary: true),
                  ReportLine(label: "Gross Profit", amount: usd(15_362.48), depth: 0, isSummary: true),
                  ReportLine(label: "Fuel", amount: usd(12_768.12), depth: 1, isSummary: false),
                  ReportLine(label: "Total Expenses", amount: usd(12_768.12), depth: 0, isSummary: true),
                  ReportLine(label: "Other Income", amount: nil, depth: 0, isSummary: false),
                  ReportLine(label: "Interest Earned", amount: usd(40), depth: 1, isSummary: false),
                  ReportLine(label: "Total Other Income", amount: usd(40), depth: 0, isSummary: true),
                  ReportLine(label: "Other Expenses", amount: nil, depth: 0, isSummary: false),
                  ReportLine(label: "Interest Paid", amount: usd(111.25), depth: 1, isSummary: false),
                  ReportLine(label: "Total Other Expenses", amount: usd(111.25), depth: 0, isSummary: true),
                  ReportLine(label: "Net Income", amount: usd(2_523.11), depth: 0, isSummary: true)]
        let costs = TopExpenseDrivers.costLines(pl)
        #expect(costs.map(\.label) == ["Cost of Goods Sold", "Cost of Goods Sold", "Fuel", "Other Expenses", "Interest Paid"])
        let total = costs.compactMap(\.amount).reduce(Money(minorUnits: 0, currency: .usd), +)
        #expect(total == usd(15_522.48 - 2_523.11 + 40))   // 13,039.37
        #expect(InsightCards.expenses(pl, prior: [], transactions: [], pareto: false, period: AccountingPeriod(year: 2026, month: 9), footnote: "")?.headline == "$13,039.37")
    }
}
