import Testing
import Foundation
@testable import Core

@Suite("Business Diagnosis: each item fires exactly at its threshold, with exact numbers")
struct BusinessDiagnosisTests {
    func usd(_ d: Double) -> Money { Money(minorUnits: Int64((d * 100).rounded()), currency: .usd) }
    /// A month: income, an expense split into categories; net = income − expenses.
    func month(_ y: Int, _ m: Int, income: Double, _ expenses: [String: Double]) -> MonthlyReport {
        let total = expenses.values.reduce(0, +)
        var lines = [ReportLine(label: "Total Income", amount: usd(income), depth: 0, isSummary: true),
                     ReportLine(label: "Gross Profit", amount: usd(income), depth: 0, isSummary: true)]
        for (k, v) in expenses.sorted(by: { $0.key < $1.key }) { lines.append(ReportLine(label: k, amount: usd(v), depth: 1, isSummary: false)) }
        lines += [ReportLine(label: "Total Expenses", amount: usd(total), depth: 0, isSummary: true),
                  ReportLine(label: "Net Income", amount: usd(income - total), depth: 0, isSummary: true)]
        return MonthlyReport(period: AccountingPeriod(year: y, month: m), lines: lines)
    }
    /// 24 months Oct 2024 – Sep 2026.
    func history(income: (Int) -> Double, expenses: (Int) -> [String: Double]) -> [MonthlyReport] {
        var p = AccountingPeriod(year: 2024, month: 10); var out: [MonthlyReport] = []
        for i in 0..<24 { out.append(month(p.year, p.month, income: income(i), expenses(i))); p = AccountingPeriod(year: p.month == 12 ? p.year + 1 : p.year, month: p.month % 12 + 1) }
        return out
    }
    func input(_ monthly: [MonthlyReport], bs: [ReportLine] = [], ar: [AgingLine] = [], tx: [LedgerTransaction] = [], tie: [TieOut.Check] = []) -> BusinessDiagnosis.Input {
        BusinessDiagnosis.Input(period: AccountingPeriod(year: 2026, month: 9), monthly: monthly, currentProfitAndLoss: [], balanceSheet: bs,
                                agedReceivables: ar, agedPayables: [], transactions: tx, openFindings: [], tieOut: tie, forecast: nil)
    }

    @Test("Strong margin and growth: 20% margin, revenue up 25% year over year")
    func strengths() {
        let h = history(income: { $0 < 12 ? 8_000 : 10_000 }, expenses: { $0 < 12 ? ["Rent": 6_400] : ["Rent": 8_000] })
        let r = BusinessDiagnosis.build(input(h))
        let margin = r.items.first { $0.id == "margin" }
        #expect(margin?.quadrant == .strength)
        #expect(margin?.detail.contains("20.0%") == true)
        #expect(margin?.detail.contains("$24,000.00 kept from $120,000.00") == true)
        let growth = r.items.first { $0.id == "growth" }
        #expect(growth?.quadrant == .strength)
        #expect(growth?.detail.contains("+25%") == true)
        #expect(growth?.amount == usd(6_000))
    }

    @Test("Thin margin and shrinking revenue; 2 losses in 3 months is a threat")
    func weaknesses() {
        let h = history(income: { $0 < 21 ? 10_000 : 7_000 }, expenses: { _ in ["Rent": 9_800] })
        let r = BusinessDiagnosis.build(input(h))
        #expect(r.items.first { $0.id == "margin" }?.quadrant == .weakness)
        #expect(r.items.first { $0.id == "growth" }?.quadrant == .weakness)
        #expect(r.items.first { $0.id == "losses" }?.quadrant == .threat)
    }

    @Test("A cost up 25%+ and $300+ is a weakness with a saving opportunity; a holding account gets no 'rein in'")
    func risingCosts() {
        let h = history(income: { _ in 20_000 }, expenses: { i in i >= 21 ? ["Fuel": 1_300, "Reconciliation Discrepancies": 900] : ["Fuel": 1_000, "Reconciliation Discrepancies": 500] })
        let r = BusinessDiagnosis.build(input(h))
        let fuel = r.items.first { $0.id == "rise-Fuel" }
        #expect(fuel?.detail.contains("up 30%") == true)
        #expect(fuel?.amount == usd(900))
        #expect(r.items.first { $0.id == "trim-Fuel" }?.detail.contains("$300.00 a month") == true)
        #expect(r.items.contains { $0.id == "rise-Reconciliation Discrepancies" })
        #expect(!r.items.contains { $0.id == "trim-Reconciliation Discrepancies" })
        // Fuel +29.9% but only $299 a quarter would not fire:
        let small = history(income: { _ in 20_000 }, expenses: { i in i >= 21 ? ["Fuel": 433] : ["Fuel": 333.34] })
        #expect(!BusinessDiagnosis.build(input(small)).items.contains { $0.id == "rise-Fuel" })
    }

    @Test("Where the money goes: shares add to 100% and match the 12-month totals")
    func whereMoneyGoes() {
        let h = history(income: { _ in 20_000 }, expenses: { _ in ["Rent": 2_000, "Fuel": 1_000, "Labor": 7_000] })
        let r = BusinessDiagnosis.build(input(h))
        #expect(r.whereMoneyGoes.first?.label == "Labor")
        #expect(r.whereMoneyGoes.first?.amount == usd(84_000))
        #expect(abs(r.whereMoneyGoes.reduce(0) { $0 + $1.share } - 100) < 0.0001)
    }

    @Test("Cash runway: under one month is a threat; 3+ months a strength")
    func runway() {
        let h = history(income: { _ in 10_000 }, expenses: { _ in ["Rent": 8_000] })
        let low = BusinessDiagnosis.build(input(h, bs: [ReportLine(label: "Total Bank Accounts", amount: usd(5_000), depth: 1, isSummary: true)]))
        #expect(low.items.first { $0.id == "runway" }?.quadrant == .threat)
        #expect(low.items.first { $0.id == "runway" }?.detail.contains("0.6 months") == true)
        let high = BusinessDiagnosis.build(input(h, bs: [ReportLine(label: "Total Bank Accounts", amount: usd(30_000), depth: 1, isSummary: true)]))
        #expect(high.items.first { $0.id == "runway" }?.quadrant == .strength)
    }

    @Test("One customer at 30%+ of sales billed is a threat")
    func concentration() {
        let h = history(income: { _ in 10_000 }, expenses: { _ in ["Rent": 5_000] })
        func inv(_ id: String, _ who: String, _ amt: Double) -> LedgerTransaction {
            LedgerTransaction(id: id, entityKind: .invoice, vendorName: who, txnDate: AccountingDate(year: 2026, month: 5, day: 1), totalAmount: usd(amt),
                              paymentAccountID: nil, docNumber: nil, isVoided: false, memo: nil, provenance: .qboAPI(readAt: Date()))
        }
        let r = BusinessDiagnosis.build(input(h, tx: [inv("1", "Big Co", 4_000), inv("2", "Small A", 3_000), inv("3", "Small B", 3_000)]))
        #expect(r.items.first { $0.id == "concentration" }?.detail.contains("Big Co is 40%") == true)
        let even = BusinessDiagnosis.build(input(h, tx: [inv("1", "A", 2_500), inv("2", "B", 2_500), inv("3", "C", 2_500), inv("4", "D", 2_500)]))
        #expect(!even.items.contains { $0.id == "concentration" })
    }

    @Test("Without 12 months of history it says so instead of judging")
    func shortHistory() {
        let r = BusinessDiagnosis.build(input(Array(history(income: { _ in 1 }, expenses: { _ in [:] }).suffix(5))))
        #expect(!r.items.contains { $0.id == "margin" })
        #expect(r.notJudged.first?.contains("5 loaded") == true)
    }

    @Test("Months after the reviewed one are ignored")
    func noFutureMonths() {
        var h = history(income: { _ in 10_000 }, expenses: { _ in ["Rent": 5_000] })
        h.append(month(2026, 10, income: 999_999, ["Rent": 1]))
        #expect(BusinessDiagnosis.build(input(h)).trend.last?.0 == "Sep '26")
    }
}
