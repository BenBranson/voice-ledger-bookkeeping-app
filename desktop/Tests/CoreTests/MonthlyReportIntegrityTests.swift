import Testing
@testable import Core
import Foundation

/// The owner's review of the July 2026 sandbox report (2026-09-29): each
/// test pins one way the report used to mislead.
@Suite("Monthly report integrity")
struct MonthlyReportIntegrityTests {
    let realm = RealmID(rawValue: "r")
    let period = AccountingPeriod(year: 2026, month: 7)
    func usd(_ c: Int64) -> Money { Money(minorUnits: c, currency: .usd) }
    func sum(_ l: String, _ c: Int64) -> ReportLine { ReportLine(label: l, amount: usd(c), depth: 0, isSummary: true) }
    func line(_ l: String, _ c: Int64, id: String? = nil) -> ReportLine { ReportLine(label: l, amount: usd(c), depth: 1, isSummary: false, accountID: id) }

    func finding(_ id: String, rule: String, cents: Int64, account: String? = nil, status: FindingStatus = .open, confidence: Confidence = .high, title: String? = nil) -> Finding {
        var f = Finding(id: id, ruleID: RuleID(rawValue: rule), ruleVersion: RuleVersion(major: 1, minor: 0, patch: 0), realmID: realm, period: period,
                        title: title ?? "T\(id) — \(usd(cents))", severity: .high, confidence: confidence, dollarExposure: usd(cents),
                        evidence: account.map { [EvidenceItem(transactionID: $0, highlightedFields: [], fieldValues: [:])] } ?? [],
                        proposedActions: [], provenance: [], narrative: "N\(id) \(usd(cents)) as of the latest sync", riskIfIgnored: nil)
        f.status = status
        return f
    }

    /// July 2026 sandbox P&L: $1,000 revenue, $998.02 expenses (incl.
    /// $312.50 Ask My Accountant), $4,264.76 reconciliation discrepancy.
    var julyPnL: [ReportLine] {
        [line("Design income", 100_000, id: "i"), sum("Total Income", 100_000), sum("Gross Profit", 100_000),
         line("Ask My Accountant", 31_250, id: "a"), line("Supplies", 68_552, id: "s"), sum("Total Expenses", 99_802),
         sum("Net Operating Income", 198), line("Reconciliation Discrepancies", 426_476, id: "r"),
         sum("Total Other Expenses", 426_476), sum("Net Other Income", -426_476), sum("Net Income", -426_278)]
    }

    @Test("Engine text is polished for clients: USD amounts and raw dates")
    func polish() {
        #expect(ClientText.polish("Notes Payable — USD 25000.00") == "Notes Payable — $25,000.00")
        #expect(ClientText.polish("balance of -USD 3293.02") == "balance of ($3,293.02)")
        #expect(ClientText.polish("dated 2026-7-31 and 2026-07-26") == "dated Jul 31, 2026 and Jul 26, 2026")
    }

    @Test("A finding that just disappeared is not work and not 'corrected and verified'")
    func autoClearedIsNotWork() {
        let gone = finding("x", rule: "VL-DUP-EXP-001", cents: 31_500, status: .resolved)
        let log = [ActivityLogEntry(realmID: realm, recordedAt: Date(), actor: .system, kind: .findingResolved, findingID: "x", note: "No longer detected on this sync")]
        #expect(WorkLog.items(activityLog: log, findings: [gone], period: period).isEmpty)
        #expect(WorkLog.autoClearedCount(activityLog: log, findings: [gone], period: period) == 1)
    }

    @Test("Balance findings are re-checked at period end: dropped if normal then, re-amounted if different")
    func periodEndBalances() {
        let bs = [line("Notes Payable", 2_500_000, id: "np"), line("Opening Balance Equity", -833_750, id: "obe"), line("Checking", -306_376, id: "ck")]
        let findings = [
            finding("np", rule: "VL-BS-NEGBAL-001", cents: 2_500_000, account: "np"),   // owed on the BS → normal
            finding("obe", rule: "VL-OBE-BALANCE-001", cents: 924_750, account: "obe"), // live 9,247.50 vs 8,337.50 at period end
            finding("ck", rule: "VL-BS-NEGBAL-001", cents: 306_376, account: "ck"),
            finding("gone", rule: "VL-BS-SUSPENSE-001", cents: 10_000, account: "zz")    // not on the BS → zero then
        ]
        let result = ReportStatus.openItems(findings: findings, workItems: [], clientQuestions: [], balanceSheet: bs, periodEndLabel: "July 31, 2026")
        #expect(result.droppedAfterPeriod == 2)
        #expect(result.items.map(\.findingID).sorted() == ["ck", "obe"])
        let obe = result.items.first { $0.findingID == "obe" }!
        #expect(obe.amountText == "$8,337.50")
        #expect(obe.title == "Tobe — $8,337.50")
        #expect(obe.detail.contains("at July 31, 2026"))
    }

    @Test("Possible vs confirmed; awaiting verification counted once; same-amount items linked")
    func statusesAndCounts() {
        let findings = [
            finding("dup", rule: "VL-DUP-INV-001", cents: 50_000),
            finding("recon", rule: "VL-FORCED-RECON-001", cents: 426_476),
            finding("payee", rule: "VL-MISSING-PAYEE-001", cents: 426_476)
        ]
        let work = [WorkItem(findingID: "payee", title: "", found: "", action: "", doneBy: "", doneAtLabel: "", affectedPeriodLabel: "", status: .awaitingVerification, statusLabel: "", impact: "", amountText: "")]
        let items = ReportStatus.openItems(findings: findings, workItems: work, clientQuestions: [], balanceSheet: [], periodEndLabel: "").items
        let kinds = Dictionary(uniqueKeysWithValues: items.map { ($0.findingID, $0.kind) })
        #expect(kinds == ["dup": .possible, "recon": .confirmed, "payee": .awaitingVerification])
        #expect(items.first { $0.findingID == "recon" }!.related.count == 1)
        let summary = Dictionary(uniqueKeysWithValues: ReportStatus.summary(workItems: work, openItems: items).map { ($0.label, $0.valueText) })
        #expect(summary["Awaiting verification"] == "1")
        #expect(summary["Confirmed issues open"] == "1")
        #expect(summary["Possible issues to review"] == "1")
    }

    @Test("The reconciliation adjustment is separated from the operating result, and it ties")
    func bridge() throws {
        let b = try #require(PerformanceAnalysis.bridge(julyPnL))
        #expect(b.beforeAdjustmentsText == "$1.98")
        #expect(b.adjustmentsText == "$4,264.76")
        #expect(b.reportedText == "($4,262.78)")
        #expect(b.note?.contains("$312.50") == true)
        let waterfall = try #require(ChartData.waterfall(from: julyPnL))
        #expect(waterfall.reconciles)
        #expect(waterfall.steps.map(\.id) == ["revenue", "expenses", "adjustment", "net"])
    }

    @Test("No adjustment: the bridge keeps the holding-account note but says there is nothing to adjust")
    func bridgeWithoutAdjustment() throws {
        let pnl = [line("Design income", 100_000, id: "i"), sum("Total Income", 100_000), sum("Gross Profit", 100_000),
                   line("Ask My Accountant", 12_999, id: "a"), line("Supplies", 50_000, id: "s"), sum("Total Expenses", 62_999),
                   sum("Net Operating Income", 37_001), sum("Net Income", 37_001)]
        let b = try #require(PerformanceAnalysis.bridge(pnl))
        #expect(b.hasAdjustment == false)
        #expect(b.note?.contains("$129.99") == true)
        #expect(try #require(PerformanceAnalysis.bridge(julyPnL)).hasAdjustment == true)
    }

    @Test("A possible personal expense or uncategorized spending becomes a question for the client")
    func clientOnlyQuestions() {
        let input = MonthlyReportInputs(clientName: "A", period: period, today: AccountingDate(year: 2026, month: 9, day: 1), generatedAt: Date(), accountingBasis: "Accrual", environment: "sandbox",
                                        monthlyProfitAndLoss: [MonthlyReport(period: period, lines: julyPnL)], balanceSheet: [], cashFlow: [], agedReceivables: [], accountTypes: [:],
                                        findings: [finding("p", rule: "VL-PERSONAL-001", cents: 18_640, title: "Lone Star Fuel, $186.40"),
                                                   finding("u", rule: "VL-CAT-UNCAT-001", cents: 12_999, title: "Amazon Business, $129.99"),
                                                   finding("d", rule: "VL-DUP-INV-001", cents: 22_000)], coverage: .complete)
        let q = MonthlyReportBuilder.build(input).questionsForClient
        #expect(q == ["Lone Star Fuel, $186.40: was this a business cost, or personal (an owner draw)?",
                      "Amazon Business, $129.99: what was this for, so it can go in the right category?"])
    }

    @Test("From sales to profit: plain names, minus signs, profit per dollar")
    func moneySteps() throws {
        let pnl = [line("Sales", 1_552_248, id: "i"), sum("Total Income", 1_552_248), line("Materials", 16_000, id: "c"), sum("Total Cost of Goods Sold", 16_000),
                   sum("Gross Profit", 1_536_248), line("Fuel", 1_276_812, id: "e"), sum("Total Expenses", 1_276_812),
                   line("Interest", 11_125, id: "x"), sum("Total Other Expenses", 11_125), sum("Net Income", 248_311)]
        let list = try #require(ChartData.moneySteps(from: pnl))
        #expect(list.steps.map(\.name) == ["Money in (sales)", "Cost of goods sold", "Costs of running the business", "Other costs (interest, fees)", "Money left over (profit)"])
        #expect(list.steps.map(\.amountText) == ["+$15,522.48", "-$160.00", "-$12,768.12", "-$111.25", "$2,483.11"])
        #expect(list.steps.first?.barFraction == 1)
        #expect(list.perDollarSentence == "Out of every $1 in sales, 16¢ was left over as profit.")
        #expect(list.tieNote.hasPrefix("Each line is a QuickBooks total"))
        let loss = try #require(ChartData.moneySteps(from: julyPnL))
        #expect(loss.steps.last?.name == "Money lost this month")
        #expect(loss.steps.last?.amountText == "-$4,262.78")
        #expect(loss.steps.last?.kind == .loss)
    }

    @Test("Bank + undeposited funds ties to the cash-flow statement's ending cash")
    func cashTie() throws {
        let bs = [sum("Total Bank Accounts", -455_678), line("Undeposited Funds", 286_252)]
        let tie = try #require(CashTie.rows(balanceSheet: bs, cashFlow: [sum("Cash at end of period", -169_426)]))
        #expect(tie.ties)
        let off = try #require(CashTie.rows(balanceSheet: bs, cashFlow: [sum("Cash at end of period", -100_000)]))
        #expect(!off.ties)
        #expect(off.rows.last?.label == "Not explained by the accounts above")
    }

    @Test("A negative aging bucket is credits, not money owed and not 'old'")
    func agingCredits() {
        let total = AgingLine(label: "TOTAL", current: .zero, days1to30: .zero, days31to60: usd(100_000), days61to90: usd(-80_000), days91AndOver: usd(528_152), total: usd(548_152), depth: 0, isSummary: true)
        let split = AgingSplit(total)
        #expect(split.owed == usd(628_152))
        #expect(split.credits == usd(-80_000))
        #expect(split.over60Owed == usd(528_152))
        #expect(split.creditsProseText == "$800.00")
    }

    @Test("July sandbox shape: confidence Low, no Sankey in a loss month, takeaway leads with the adjustment")
    func julyReport() {
        let input = MonthlyReportInputs(clientName: "A", period: period, today: AccountingDate(year: 2026, month: 9, day: 1), generatedAt: Date(), accountingBasis: "Accrual", environment: "sandbox",
                                        monthlyProfitAndLoss: [MonthlyReport(period: period, lines: julyPnL)], balanceSheet: [], cashFlow: [], agedReceivables: [], accountTypes: [:], findings: [], coverage: .complete)
        let report = MonthlyReportBuilder.build(input)
        #expect(report.reportingConfidence == "Low")
        #expect(report.moneyFlow == nil)
        #expect(report.takeaways.first?.contains("net loss of $4,262.78, but $4,264.76 of that is a reconciliation adjustment") == true)
        #expect(report.healthChecks.first?.detail.hasPrefix("About break-even ($1.98)") == true)
        #expect(report.priorities.first?.action == "Trace the reconciliation adjustment to the bank statement")
        #expect(report.kpis.first { $0.id == "net" }?.detail == "Before the $4,264.76 reconciliation adjustment: $1.98")
    }
}
