import Testing
import Foundation
@testable import Core

@Suite("ClientMemoryRule")
struct ClientMemoryRuleTests {
    @Test("Matches the same rule and vendor, case/whitespace-insensitive")
    func matchesSameRuleAndVendor() {
        let rule = ClientMemoryRule(ruleID: RuleID(rawValue: "VL-CC-PAYMENT-001"), vendorName: "VL Spike Amex", createdBy: "Test")
        #expect(rule.matches(ruleID: RuleID(rawValue: "VL-CC-PAYMENT-001"), findingVendorName: "  vl spike amex  "))
    }

    @Test("Does not match a different vendor")
    func doesNotMatchDifferentVendor() {
        let rule = ClientMemoryRule(ruleID: RuleID(rawValue: "VL-CC-PAYMENT-001"), vendorName: "VL Spike Amex", createdBy: "Test")
        #expect(!rule.matches(ruleID: RuleID(rawValue: "VL-CC-PAYMENT-001"), findingVendorName: "VL Spike Permian Supply"))
    }

    @Test("Does not match the same vendor under a different rule — no cross-rule suppression")
    func doesNotMatchDifferentRule() {
        let rule = ClientMemoryRule(ruleID: RuleID(rawValue: "VL-CC-PAYMENT-001"), vendorName: "VL Spike Amex", createdBy: "Test")
        #expect(!rule.matches(ruleID: RuleID(rawValue: "VL-PAYROLL-LUMP-001"), findingVendorName: "VL Spike Amex"))
    }

    @Test("Never matches a nil finding vendor name")
    func neverMatchesNilVendor() {
        let rule = ClientMemoryRule(ruleID: RuleID(rawValue: "VL-CC-PAYMENT-001"), vendorName: "VL Spike Amex", createdBy: "Test")
        #expect(!rule.matches(ruleID: RuleID(rawValue: "VL-CC-PAYMENT-001"), findingVendorName: nil))
    }
}
