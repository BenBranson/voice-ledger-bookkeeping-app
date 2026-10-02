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
