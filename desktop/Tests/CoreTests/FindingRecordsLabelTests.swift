import Testing
@testable import Core

@Suite("Finding records label")
struct FindingRecordsLabelTests {
    func finding(_ rule: String, ids: [String]) -> Finding {
        Finding(id: "f", ruleID: RuleID(rawValue: rule), ruleVersion: RuleVersion(major: 1, minor: 0, patch: 0), realmID: RealmID(rawValue: "r"),
                period: AccountingPeriod(year: 2026, month: 7), title: "t", severity: .high, confidence: .high,
                dollarExposure: Money(minorUnits: 100, currency: .usd), evidence: ids.map { EvidenceItem(transactionID: $0, highlightedFields: [], fieldValues: [:]) },
                proposedActions: [], provenance: [], narrative: nil, riskIfIgnored: nil)
    }
    @Test("Duplicate pairs say so; single-record findings say nothing")
    func labels() {
        #expect(FindingRecordsLabel.text(for: finding("VL-DUP-INV-001", ids: ["220", "221"])) == "2 records (a duplicate pair)")
        #expect(FindingRecordsLabel.text(for: finding("VL-DUP-VEND-001", ids: ["a", "b"])) == "2 vendor records")
        #expect(FindingRecordsLabel.text(for: finding("VL-BS-NEGBAL-001", ids: ["35"])) == nil)
        #expect(FindingRecordsLabel.text(for: finding("VL-DUP-INV-001", ids: ["220", "220"])) == nil)
    }
}
