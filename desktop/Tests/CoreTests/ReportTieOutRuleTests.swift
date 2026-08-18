import Testing
@testable import Core
import Foundation

@Suite("VL-REPORT-TIE-001 — ReportTieOutRule")
struct ReportTieOutRuleTests {
    let realm = RealmID(rawValue: "9341456442848752")
    let period = AccountingPeriod(year: 2026, month: 7)

    func context() -> RuleContext {
        RuleContext(period: period, materiality: .defaultPolicy, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false))
    }

    let arAccount = LedgerAccount(id: "84", name: "Accounts Receivable (A/R)", accountType: .accountsReceivable)
    let apAccount = LedgerAccount(id: "33", name: "Accounts Payable (A/P)", accountType: .accountsPayable)

    func dataSet(
        accounts: [LedgerAccount] = [],
        balanceSheetLines: [ReportLine] = [],
        agedReceivablesLines: [AgingLine] = [],
        agedPayablesLines: [AgingLine] = [],
        coverage: Coverage = .complete
    ) -> NormalizedDataSet {
        NormalizedDataSet(
            realmID: realm, period: period, transactions: [], accounts: accounts,
            balanceSheetLines: balanceSheetLines,
            agedReceivablesLines: agedReceivablesLines,
            agedPayablesLines: agedPayablesLines,
            coverage: coverage, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false)
        )
    }

    @Test("No Balance Sheet loaded is .cannotEvaluate, not .pass")
    func noBalanceSheetIsCannotEvaluate() {
        let outcome = ReportTieOutRule.evaluate(dataSet(agedReceivablesLines: [AgingLine(label: "TOTAL", current: nil, days1to30: nil, days31to60: nil, days61to90: nil, days91AndOver: nil, total: .zero, depth: 0, isSummary: true)]), context: context())
        guard case .cannotEvaluate = outcome else {
            Issue.record("expected .cannotEvaluate — no Balance Sheet")
            return
        }
    }

    @Test("No aging report loaded is .cannotEvaluate, not .pass")
    func noAgingReportIsCannotEvaluate() {
        let outcome = ReportTieOutRule.evaluate(dataSet(balanceSheetLines: [ReportLine(label: "Accounts Receivable (A/R)", amount: .zero, depth: 0, isSummary: false)]), context: context())
        guard case .cannotEvaluate = outcome else {
            Issue.record("expected .cannotEvaluate — no aging report")
            return
        }
    }

    @Test("A/R matches exactly between Balance Sheet and Aged Receivables produces .pass")
    func matchingARProducesPass() {
        let bs = [ReportLine(label: "Accounts Receivable (A/R)", amount: Money(minorUnits: 548_152, currency: .usd), depth: 0, isSummary: false)]
        let ar = [AgingLine(label: "TOTAL", current: nil, days1to30: nil, days31to60: nil, days61to90: nil, days91AndOver: nil, total: Money(minorUnits: 548_152, currency: .usd), depth: 0, isSummary: true)]
        let outcome = ReportTieOutRule.evaluate(dataSet(accounts: [arAccount], balanceSheetLines: bs, agedReceivablesLines: ar), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — A/R ties out exactly")
            return
        }
    }

    @Test("A material A/R mismatch between Balance Sheet and Aged Receivables produces a finding")
    func mismatchedARProducesFinding() {
        let bs = [ReportLine(label: "Accounts Receivable (A/R)", amount: Money(minorUnits: 600_000, currency: .usd), depth: 0, isSummary: false)]
        let ar = [AgingLine(label: "TOTAL", current: nil, days1to30: nil, days31to60: nil, days61to90: nil, days91AndOver: nil, total: Money(minorUnits: 548_152, currency: .usd), depth: 0, isSummary: true)]
        let outcome = ReportTieOutRule.evaluate(dataSet(accounts: [arAccount], balanceSheetLines: bs, agedReceivablesLines: ar), context: context())
        guard case .findings(let findings) = outcome, findings.count == 1 else {
            Issue.record("expected one finding")
            return
        }
        #expect(findings[0].dollarExposure == Money(minorUnits: 51_848, currency: .usd))
        #expect(findings[0].confidence == .high)
    }

    @Test("A/P mismatch is checked independently of A/R — both can fire in the same evaluation")
    func bothARAndAPCanFireTogether() {
        let bs = [
            ReportLine(label: "Accounts Receivable (A/R)", amount: Money(minorUnits: 600_000, currency: .usd), depth: 0, isSummary: false),
            ReportLine(label: "Accounts Payable (A/P)", amount: Money(minorUnits: 100_000, currency: .usd), depth: 0, isSummary: false)
        ]
        let ar = [AgingLine(label: "TOTAL", current: nil, days1to30: nil, days31to60: nil, days61to90: nil, days91AndOver: nil, total: Money(minorUnits: 548_152, currency: .usd), depth: 0, isSummary: true)]
        let ap = [AgingLine(label: "TOTAL", current: nil, days1to30: nil, days31to60: nil, days61to90: nil, days91AndOver: nil, total: Money(minorUnits: 0, currency: .usd), depth: 0, isSummary: true)]
        let outcome = ReportTieOutRule.evaluate(dataSet(accounts: [arAccount, apAccount], balanceSheetLines: bs, agedReceivablesLines: ar, agedPayablesLines: ap), context: context())
        guard case .findings(let findings) = outcome else {
            Issue.record("expected findings for both A/R and A/P")
            return
        }
        #expect(findings.count == 2)
    }

    @Test("Below materiality floor produces no finding")
    func belowMaterialityFloorExcluded() {
        let bs = [ReportLine(label: "Accounts Receivable (A/R)", amount: Money(minorUnits: 548_652, currency: .usd), depth: 0, isSummary: false)] // $5 off, below $25 floor
        let ar = [AgingLine(label: "TOTAL", current: nil, days1to30: nil, days31to60: nil, days61to90: nil, days91AndOver: nil, total: Money(minorUnits: 548_152, currency: .usd), depth: 0, isSummary: true)]
        let outcome = ReportTieOutRule.evaluate(dataSet(accounts: [arAccount], balanceSheetLines: bs, agedReceivablesLines: ar), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — below materiality floor")
            return
        }
    }

    @Test("No account of the matching type in the chart of accounts skips that side silently, not a false finding")
    func noMatchingAccountTypeSkipsSilently() {
        let bs = [ReportLine(label: "Accounts Receivable (A/R)", amount: Money(minorUnits: 600_000, currency: .usd), depth: 0, isSummary: false)]
        let ar = [AgingLine(label: "TOTAL", current: nil, days1to30: nil, days31to60: nil, days61to90: nil, days91AndOver: nil, total: Money(minorUnits: 548_152, currency: .usd), depth: 0, isSummary: true)]
        // No accounts passed at all — the rule can't confirm which Balance
        // Sheet line is really the A/R account, so it must not guess by
        // matching the literal label text.
        let outcome = ReportTieOutRule.evaluate(dataSet(accounts: [], balanceSheetLines: bs, agedReceivablesLines: ar), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — no A/R-type account to anchor the comparison to")
            return
        }
    }

    @Test("The rule never claims .pass on incomplete coverage")
    func neverClaimsPassOnPartialCoverage() {
        let outcome = ReportTieOutRule.evaluate(
            dataSet(coverage: .partial(reason: "sync incomplete")),
            context: context()
        )
        if case .pass = outcome {
            Issue.record("rule must not report .pass on partial coverage")
        }
    }
}
