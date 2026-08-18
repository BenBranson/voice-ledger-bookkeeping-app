import Testing
import Foundation
@testable import Core

@Suite("ClientQuestionDrafter")
struct ClientQuestionDrafterTests {
    func sampleFinding(ruleID: String = "VL-CC-PAYMENT-001") -> Finding {
        Finding(
            id: "abc123",
            ruleID: RuleID(rawValue: ruleID),
            ruleVersion: RuleVersion(major: 1, minor: 0, patch: 0),
            realmID: RealmID(rawValue: "realm-a"),
            period: AccountingPeriod(year: 2026, month: 7),
            title: "Credit card payment coded to Office Supplies — $750.00",
            severity: .high,
            confidence: .high,
            dollarExposure: Money(minorUnits: 75_000, currency: .usd),
            evidence: [],
            proposedActions: [],
            provenance: []
        )
    }

    @Test("The draft includes the finding's title and dollar exposure")
    func draftIncludesFindingDetails() {
        let text = ClientQuestionDrafter.draft(finding: sampleFinding(), clientName: nil)
        #expect(text.contains("Credit card payment coded to Office Supplies — $750.00"))
        #expect(text.contains("2026-07"))
    }

    @Test("A client name, when given, is used in the greeting")
    func clientNameUsedInGreeting() {
        let text = ClientQuestionDrafter.draft(finding: sampleFinding(), clientName: "Amy")
        #expect(text.hasPrefix("Hi Amy,"))
    }

    @Test("With no client name, the greeting has no trailing space before the comma")
    func noClientNameOmitsExtraSpace() {
        let text = ClientQuestionDrafter.draft(finding: sampleFinding(), clientName: nil)
        #expect(text.hasPrefix("Hi,"))
    }

    @Test("A recognized rule's accountingPrinciple is included")
    func includesAccountingPrincipleForKnownRule() {
        let text = ClientQuestionDrafter.draft(finding: sampleFinding(ruleID: "VL-CC-PAYMENT-001"), clientName: nil)
        #expect(text.contains("Why this matters:"))
    }

    @Test("An unrecognized ruleID does not crash — the principle line is simply omitted")
    func unknownRuleIDOmitsPrincipleLine() {
        let text = ClientQuestionDrafter.draft(finding: sampleFinding(ruleID: "VL-NOT-A-REAL-RULE"), clientName: nil)
        #expect(!text.contains("Why this matters:"))
    }
}
