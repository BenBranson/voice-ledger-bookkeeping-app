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

    @Test("The adjustment transaction QBO posted (live 2026-10-02: Purchase 228, memo 'Reconcile Adjustment') leads the evidence, so the link opens it")
    func adjustmentTransactionIsEvidence() {
        let adj = LedgerTransaction(id: "228", entityKind: .purchase, vendorName: nil, txnDate: AccountingDate(year: 2026, month: 7, day: 31),
                                    totalAmount: Money(minorUnits: 426_476, currency: .usd), paymentAccountID: "35", docNumber: "ADJ", isVoided: false,
                                    memo: "Reconcile Adjustment", lineAccountIDs: ["91"], provenance: .qboAPI(readAt: Date()))
        let other = LedgerTransaction(id: "300", entityKind: .purchase, vendorName: "Chevron", txnDate: AccountingDate(year: 2026, month: 7, day: 3),
                                      totalAmount: Money(minorUnits: 5_000, currency: .usd), paymentAccountID: "35", docNumber: nil, isVoided: false,
                                      memo: nil, lineAccountIDs: ["60"], provenance: .qboAPI(readAt: Date()))
        let data = NormalizedDataSet(realmID: realm, period: period, transactions: [adj, other],
                                     profitAndLossLines: [ReportLine(label: "Reconciliation Discrepancies", amount: Money(minorUnits: 426_476, currency: .usd), depth: 1, isSummary: false, accountID: "91")],
                                     coverage: .complete, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false))
        guard case .findings(let findings) = ForcedReconciliationRule.evaluate(data, context: context()), let f = findings.first else {
            Issue.record("expected one finding"); return
        }
        #expect(f.evidence.map(\.transactionID) == ["228", "Reconciliation Discrepancies"])
        // Identity unchanged by the new evidence: same ID as a data set with no transactions.
        guard case .findings(let bare) = ForcedReconciliationRule.evaluate(dataSet(profitAndLossLines: data.profitAndLossLines), context: context()) else { return }
        #expect(bare.first?.id == f.id)
    }
}
