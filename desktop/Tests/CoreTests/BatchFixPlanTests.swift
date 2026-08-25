import Testing
import Foundation
@testable import Core

@Suite("BatchFixPlan")
struct BatchFixPlanTests {
    func stagedFinding(id: String, exposureMinorUnits: Int64 = 10_000, currentAccountName: String = "Meals & Entertainment", suggestedAccountName: String = "Credit Card Payable") -> Finding {
        let details = StagedAPIWriteDetails(
            purchaseID: "purchase-\(id)",
            lineID: "line-\(id)",
            expectedSyncToken: "0",
            currentAccountID: "acct-current",
            currentAccountName: currentAccountName,
            suggestedAccountID: "acct-suggested",
            suggestedAccountName: suggestedAccountName
        )
        let action = ProposedAction(
            id: "reclassify",
            title: "Reclassify",
            resolution: .stagedAPI,
            guidedProcedure: nil,
            consequences: [.reporting("expenses decrease"), .reconciliation("card balance corrected")],
            reversal: .reversibleManually(procedure: "Change the category back in QBO if done in error"),
            apiWriteDetails: details
        )
        return Finding(
            id: id,
            ruleID: RuleID(rawValue: "VL-CC-PAYMENT-001"),
            ruleVersion: RuleVersion(major: 1, minor: 0, patch: 0),
            realmID: RealmID(rawValue: "realm-a"),
            period: AccountingPeriod(year: 2026, month: 7),
            title: "Credit card payment miscoded",
            severity: .high,
            confidence: .high,
            dollarExposure: Money(minorUnits: exposureMinorUnits, currency: .usd),
            evidence: [],
            proposedActions: [action],
            provenance: []
        )
    }

    func manualOnlyFinding(id: String) -> Finding {
        let action = ProposedAction(
            id: "manual-fix",
            title: "Fix manually",
            resolution: .manualQBO,
            guidedProcedure: GuidedProcedure(steps: ["Open QBO"], pitfalls: [], doneCriteria: "Done"),
            consequences: [],
            reversal: .reversibleManually(procedure: "Undo in QBO")
        )
        return Finding(
            id: id,
            ruleID: RuleID(rawValue: "VL-DUP-EXP-001"),
            ruleVersion: RuleVersion(major: 1, minor: 0, patch: 0),
            realmID: RealmID(rawValue: "realm-a"),
            period: AccountingPeriod(year: 2026, month: 7),
            title: "Possible duplicate expense",
            severity: .high,
            confidence: .high,
            dollarExposure: Money(minorUnits: 5_000, currency: .usd),
            evidence: [],
            proposedActions: [action],
            provenance: []
        )
    }

    @Test("A finding with real apiWriteDetails produces one BatchFixItem")
    func stagedFindingProducesItem() {
        let items = BatchFixPlan.preview(findings: [stagedFinding(id: "f1")])
        #expect(items.count == 1)
        #expect(items[0].findingID == "f1")
        #expect(items[0].currentAccountName == "Meals & Entertainment")
        #expect(items[0].suggestedAccountName == "Credit Card Payable")
    }

    @Test("A finding whose only action is manualQBO (no apiWriteDetails) is excluded")
    func manualOnlyFindingExcluded() {
        let items = BatchFixPlan.preview(findings: [manualOnlyFinding(id: "f2")])
        #expect(items.isEmpty)
    }

    @Test("A finding with no proposed actions at all is excluded")
    func noActionsExcluded() {
        let finding = Finding(
            id: "f3",
            ruleID: RuleID(rawValue: "VL-DUP-EXP-001"),
            ruleVersion: RuleVersion(major: 1, minor: 0, patch: 0),
            realmID: RealmID(rawValue: "realm-a"),
            period: AccountingPeriod(year: 2026, month: 7),
            title: "No actions",
            severity: .low,
            confidence: .medium,
            dollarExposure: Money(minorUnits: 100, currency: .usd),
            evidence: [],
            proposedActions: [],
            provenance: []
        )
        #expect(BatchFixPlan.preview(findings: [finding]).isEmpty)
    }

    @Test("Mixed staged and manual findings only keep the staged ones, order preserved")
    func mixedFindingsKeepOnlyStaged() {
        let items = BatchFixPlan.preview(findings: [stagedFinding(id: "f1"), manualOnlyFinding(id: "f2"), stagedFinding(id: "f4")])
        #expect(items.map(\.findingID) == ["f1", "f4"])
    }

    @Test("totalExposure sums each item's dollarExposure")
    func totalExposureSums() {
        let items = BatchFixPlan.preview(findings: [
            stagedFinding(id: "f1", exposureMinorUnits: 10_000),
            stagedFinding(id: "f2", exposureMinorUnits: 2_500)
        ])
        #expect(BatchFixPlan.totalExposure(items) == Money(minorUnits: 12_500, currency: .usd))
    }

    @Test("totalExposure is nil for an empty list — no zero-with-a-currency-guess")
    func totalExposureNilWhenEmpty() {
        #expect(BatchFixPlan.totalExposure([]) == nil)
    }
}
