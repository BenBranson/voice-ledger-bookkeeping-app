import Testing
@testable import Core
import Foundation

@Suite("QBO links for account-evidence findings")
struct QBOWebLinkAccountEvidenceTests {
    func finding(_ rule: String, evidenceID: String) -> Finding {
        Finding(id: "f", ruleID: RuleID(rawValue: rule), ruleVersion: RuleVersion(major: 1, minor: 0, patch: 0), realmID: RealmID(rawValue: "r"),
                period: AccountingPeriod(year: 2026, month: 7), title: "t", severity: .high, confidence: .high,
                dollarExposure: Money(minorUnits: 100, currency: .usd), evidence: [EvidenceItem(transactionID: evidenceID, highlightedFields: [], fieldValues: [:])],
                proposedActions: [], provenance: [], narrative: nil, riskIfIgnored: nil)
    }

    @Test("A balance finding links to the account register even before accounts are loaded")
    func registerWithoutAccounts() {
        let url = QBOWebLink.url(for: finding("VL-OBE-BALANCE-001", evidenceID: "34"), transactions: [], accounts: [], isSandbox: true)
        #expect(url?.absoluteString == "https://app.sandbox.qbo.intuit.com/app/register?accountId=34")
    }

    @Test("A missing bank line links to QBO's new-expense form")
    func missingLine() {
        let url = QBOWebLink.url(for: finding("VL-RECON-MISSING-001", evidenceID: "file.csv-row1"), transactions: [], accounts: [], isSandbox: false)
        #expect(url?.absoluteString == "https://app.qbo.intuit.com/app/expense")
    }
}
