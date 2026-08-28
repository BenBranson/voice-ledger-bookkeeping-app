import Testing
@testable import Core

@Suite("AskAIContext.compose")
struct AskAIContextTests {
    func finding(narrative: String? = nil, riskIfIgnored: String? = nil, vendorName: String? = nil) -> Finding {
        Finding(
            id: "f1",
            ruleID: RuleID(rawValue: "VL-DUP-EXP-001"),
            ruleVersion: RuleVersion(major: 1, minor: 0, patch: 0),
            realmID: RealmID(rawValue: "realm-a"),
            period: AccountingPeriod(year: 2026, month: 7),
            title: "Possible duplicate expense",
            severity: .high,
            confidence: .high,
            dollarExposure: Money(minorUnits: 48_620, currency: .usd),
            evidence: [],
            proposedActions: [],
            provenance: [],
            vendorName: vendorName,
            narrative: narrative,
            riskIfIgnored: riskIfIgnored
        )
    }

    @Test("Includes the core deterministic fields every finding has")
    func includesCoreFields() {
        let context = AskAIContext.compose(finding: finding())
        #expect(context.contains("Possible duplicate expense"))
        #expect(context.contains("2026-07"))
        #expect(context.contains("high"))
        #expect(context.contains("USD 486.20") || context.contains("486.20"))
        #expect(context.contains("open"))
    }

    @Test("Includes narrative, riskIfIgnored, and vendorName when present")
    func includesOptionalFieldsWhenPresent() {
        let context = AskAIContext.compose(finding: finding(narrative: "A real narrative sentence.", riskIfIgnored: "A real risk sentence.", vendorName: "Permian Supply"))
        #expect(context.contains("A real narrative sentence."))
        #expect(context.contains("A real risk sentence."))
        #expect(context.contains("Permian Supply"))
    }

    @Test("Omits vendor/narrative/risk lines entirely when absent — never a placeholder")
    func omitsAbsentFieldsEntirely() {
        let context = AskAIContext.compose(finding: finding())
        #expect(!context.contains("Vendor:"))
        #expect(!context.contains("Narrative:"))
        #expect(!context.contains("Risk if left open:"))
    }

    @Test("Looks up the rule's real accountingPrinciple from RuleRegistry")
    func includesAccountingPrincipleFromRegistry() {
        let context = AskAIContext.compose(finding: finding())
        let expectedPrinciple = RuleRegistry.all.first { $0.identity.id == RuleID(rawValue: "VL-DUP-EXP-001") }!.identity.accountingPrinciple
        #expect(context.contains(expectedPrinciple))
    }
}
