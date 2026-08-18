import Testing
@testable import Core
import Foundation

@Suite("VL-FORCED-RECON-001 — ForcedReconciliationRule")
struct ForcedReconciliationRuleTests {
    let realm = RealmID(rawValue: "9341456442848752")
    let period = AccountingPeriod(year: 2026, month: 7)

    func context() -> RuleContext {
        RuleContext(period: period, materiality: .defaultPolicy, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false))
    }

    func dataSet(profitAndLossLines: [ReportLine], coverage: Coverage = .complete) -> NormalizedDataSet {
        NormalizedDataSet(
            realmID: realm, period: period, transactions: [],
            profitAndLossLines: profitAndLossLines,
            coverage: coverage, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false)
        )
    }

    @Test("An empty profitAndLossLines array is .cannotEvaluate, not .pass — 'not fetched' must never look like 'checked and clean'")
    func emptyReportIsCannotEvaluate() {
        let outcome = ForcedReconciliationRule.evaluate(dataSet(profitAndLossLines: []), context: context())
        guard case .cannotEvaluate = outcome else {
            Issue.record("expected .cannotEvaluate for an unfetched P&L report")
            return
        }
    }

    @Test("A real forced-reconciliation discrepancy line — the exact live-verified shape (Other Expenses, $4,264.76) — produces a .high-confidence finding")
    func realDiscrepancyLineProducesFinding() {
        let lines = [
            ReportLine(label: "Other Expenses", amount: nil, depth: 0, isSummary: false),
            ReportLine(label: "Reconciliation Discrepancies", amount: Money(minorUnits: 426_476, currency: .usd), depth: 1, isSummary: false),
            ReportLine(label: "Total Other Expenses", amount: Money(minorUnits: 426_476, currency: .usd), depth: 1, isSummary: true)
        ]
        let outcome = ForcedReconciliationRule.evaluate(dataSet(profitAndLossLines: lines), context: context())
        guard case .findings(let findings) = outcome, findings.count == 1 else {
            Issue.record("expected one finding")
            return
        }
        #expect(findings[0].confidence == .high)
        #expect(findings[0].dollarExposure == Money(minorUnits: 426_476, currency: .usd))
        #expect(findings[0].proposedActions.first?.resolution == .manualQBO)
    }

    @Test("No Reconciliation Discrepancies line at all produces .pass, not a finding")
    func noDiscrepancyLineProducesPass() {
        let lines = [
            ReportLine(label: "Net Income", amount: Money(minorUnits: 100_000, currency: .usd), depth: 0, isSummary: true)
        ]
        let outcome = ForcedReconciliationRule.evaluate(dataSet(profitAndLossLines: lines), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — no discrepancy line present")
            return
        }
    }

    @Test("A zero-balance Reconciliation Discrepancies line produces .pass — the account existing is not itself the problem")
    func zeroBalanceLineProducesPass() {
        let lines = [
            ReportLine(label: "Reconciliation Discrepancies", amount: Money(minorUnits: 0, currency: .usd), depth: 1, isSummary: false)
        ]
        let outcome = ForcedReconciliationRule.evaluate(dataSet(profitAndLossLines: lines), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — a $0.00 discrepancy line is not a real discrepancy")
            return
        }
    }

    @Test("Below materiality floor produces no finding")
    func belowMaterialityFloorExcluded() {
        let lines = [
            ReportLine(label: "Reconciliation Discrepancies", amount: Money(minorUnits: 500, currency: .usd), depth: 1, isSummary: false) // $5, below $25 floor
        ]
        let outcome = ForcedReconciliationRule.evaluate(dataSet(profitAndLossLines: lines), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — below materiality floor")
            return
        }
    }

    @Test("A negative-signed discrepancy amount is still flagged, using its absolute value as the dollar exposure")
    func negativeAmountUsesAbsoluteValue() {
        let lines = [
            ReportLine(label: "Reconciliation Discrepancies", amount: Money(minorUnits: -426_476, currency: .usd), depth: 1, isSummary: false)
        ]
        let outcome = ForcedReconciliationRule.evaluate(dataSet(profitAndLossLines: lines), context: context())
        guard case .findings(let findings) = outcome, findings.count == 1 else {
            Issue.record("expected one finding")
            return
        }
        #expect(findings[0].dollarExposure == Money(minorUnits: 426_476, currency: .usd))
    }

    @Test("The rule never claims .pass on incomplete coverage")
    func neverClaimsPassOnPartialCoverage() {
        let outcome = ForcedReconciliationRule.evaluate(
            dataSet(profitAndLossLines: [], coverage: .partial(reason: "sync incomplete")),
            context: context()
        )
        if case .pass = outcome {
            Issue.record("rule must not report .pass on partial coverage")
        }
    }
}
