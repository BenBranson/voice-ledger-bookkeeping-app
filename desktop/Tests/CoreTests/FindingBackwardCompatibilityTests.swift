import Testing
import Foundation
@testable import Core

/// Gauntlet Loop, Gauntlet B round 7 (2026-08-24): a real, severe
/// backward-compatibility gap. `Finding.preApprovalChecklist` and
/// `EvidenceItem.fieldValues` are non-optional `[String]`/`[String: String]`
/// with a default only on their custom `init(...)` parameter — Swift's
/// synthesized `Decodable` does NOT fall back to that default for a missing
/// JSON key on a non-optional property (it only does that automatically for
/// `Optional` properties, which is why `vendorName`/`narrative`/
/// `riskIfIgnored` needed no fix). Any client with a `findings.json` written
/// before these fields existed would have `ClientStore.loadFindings()`
/// throw `DecodingError.keyNotFound`, silently failing the whole findings
/// list with no error ever surfaced in the UI (`AppState.loadState`'s
/// `.failed` case is read in exactly one place, only to disable a button).
/// `Finding`/`EvidenceItem` now have manual `init(from:)` implementations
/// using `decodeIfPresent(...) ?? default` for exactly these two fields.
@Suite("Finding backward compatibility")
struct FindingBackwardCompatibilityTests {
    static let oldFormatFindingJSON = """
    [
      {
        "id": "abc123",
        "ruleID": "VL-DUP-EXP-001",
        "ruleVersion": { "major": 1, "minor": 0, "patch": 0 },
        "realmID": "9999",
        "period": { "year": 2026, "month": 7 },
        "title": "Possible duplicate expense",
        "severity": "high",
        "confidence": "high",
        "dollarExposure": { "minorUnits": 48620, "currency": "USD" },
        "evidence": [
          { "transactionID": "145", "highlightedFields": ["amount", "date", "paymentAccount"] },
          { "transactionID": "151", "highlightedFields": ["amount", "date", "paymentAccount"] }
        ],
        "proposedActions": [],
        "provenance": [{ "qboAPI": { "readAt": 780000000 } }],
        "status": "open"
      }
    ]
    """

    @Test("A findings.json written before fieldValues/preApprovalChecklist existed decodes without throwing, defaulting the missing fields to empty")
    func decodesOldFormatFindingJSON() throws {
        let findings = try JSONDecoder().decode([Finding].self, from: Data(Self.oldFormatFindingJSON.utf8))
        let finding = findings[0]
        #expect(finding.preApprovalChecklist == [])
        #expect(finding.riskIfIgnored == nil)
        #expect(finding.vendorName == nil)
        #expect(finding.narrative == nil)
        #expect(finding.evidence[0].fieldValues == [:])
        #expect(finding.id == "abc123")
    }

    static let midFormatFindingJSON = """
    [
      {
        "id": "abc123",
        "ruleID": "VL-DUP-EXP-001",
        "ruleVersion": { "major": 1, "minor": 0, "patch": 0 },
        "realmID": "9999",
        "period": { "year": 2026, "month": 7 },
        "title": "Possible duplicate expense",
        "severity": "high",
        "confidence": "high",
        "dollarExposure": { "minorUnits": 48620, "currency": "USD" },
        "evidence": [
          { "transactionID": "145", "highlightedFields": ["amount"], "fieldValues": {"amount": "USD 486.20"} }
        ],
        "proposedActions": [],
        "provenance": [{ "qboAPI": { "readAt": 780000000 } }],
        "status": "open",
        "vendorName": "Permian Supply",
        "narrative": "Two purchases..."
      }
    ]
    """

    @Test("A findings.json from between the two Gauntlet B additions (fieldValues present, preApprovalChecklist absent) also decodes cleanly — confirms the fix isn't tied to one specific field")
    func decodesMidFormatFindingJSON() throws {
        let findings = try JSONDecoder().decode([Finding].self, from: Data(Self.midFormatFindingJSON.utf8))
        #expect(findings[0].preApprovalChecklist == [])
        #expect(findings[0].evidence[0].fieldValues == ["amount": "USD 486.20"])
        #expect(findings[0].vendorName == "Permian Supply")
    }

    @Test("A Finding encoded with the current init and re-decoded round-trips every Gauntlet B field exactly")
    func currentFormatRoundTrips() throws {
        let finding = Finding(
            id: "abc123",
            ruleID: RuleID(rawValue: "VL-DUP-EXP-001"),
            ruleVersion: RuleVersion(major: 1, minor: 0, patch: 0),
            realmID: RealmID(rawValue: "realm-a"),
            period: AccountingPeriod(year: 2026, month: 7),
            title: "Possible duplicate expense — Permian Supply, USD 486.20",
            severity: .high,
            confidence: .high,
            dollarExposure: Money(minorUnits: 48_620, currency: .usd),
            evidence: [EvidenceItem(transactionID: "145", highlightedFields: ["amount"], fieldValues: ["amount": "USD 486.20"])],
            proposedActions: [],
            provenance: [],
            vendorName: "Permian Supply",
            narrative: "Two purchases from Permian Supply...",
            preApprovalChecklist: ["Pull up the bank statement."],
            riskIfIgnored: "This will keep reappearing."
        )
        let data = try JSONEncoder().encode(finding)
        let decoded = try JSONDecoder().decode(Finding.self, from: data)
        #expect(decoded == finding)
    }
}
