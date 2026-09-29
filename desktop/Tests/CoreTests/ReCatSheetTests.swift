import Testing
@testable import Core
import Foundation

@Suite("ReCatSheet")
struct ReCatSheetTests {
    let realm = RealmID(rawValue: "1")
    func finding(_ id: String, rule: String = "VL-CAT-UNCAT-001") -> Finding {
        Finding(id: id, ruleID: RuleID(rawValue: rule), ruleVersion: RuleVersion(major: 1, minor: 0, patch: 0), realmID: realm,
                period: AccountingPeriod(year: 2026, month: 7), title: "t", severity: .high, confidence: .high,
                dollarExposure: Money(minorUnits: 31_250, currency: .usd),
                evidence: [EvidenceItem(transactionID: "232", highlightedFields: [], fieldValues: ["date": "2026-7-9", "vendor": "Home Depot", "lineAccount": "Ask My Accountant"])],
                proposedActions: [], provenance: [], vendorName: "Home Depot", narrative: nil, riskIfIgnored: nil)
    }

    @Test("Only open uncategorized items are exported, with a blank column for the client")
    func export() {
        let table = ReCatSheet.export(findings: [finding("a"), finding("b", rule: "VL-DUP-BILL-001")], companyName: "Acme")
        #expect(table.rows.count == 1)
        #expect(table.rows[0].map(\.text) == ["a", "2026-7-9", "Home Depot", "$312.50", "Ask My Accountant", "", ""])
    }

    @Test("Filled-in rows come back as answers; blank rows and unknown IDs are skipped")
    func importAnswers() {
        let rows = [
            ReCatSheet.columns,
            ["a", "2026-7-9", "Home Depot", "$312.50", "Ask My Accountant", "Drywall for Project X", "y"],
            ["b", "", "", "", "", "Not ours", ""],
            ["c", "", "", "", "", "", ""]
        ]
        let answers = ReCatSheet.answers(fromRows: rows, openFindings: [finding("a"), finding("c")])
        #expect(answers == [ReCatSheet.Answer(findingID: "a", text: "Drywall for Project X (client says a receipt is attached)")])
    }
}
