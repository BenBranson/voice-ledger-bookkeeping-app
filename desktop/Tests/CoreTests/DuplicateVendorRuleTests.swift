import Testing
@testable import Core
import Foundation

@Suite("VL-DUP-VEND-001 — DuplicateVendorRule")
struct DuplicateVendorRuleTests {
    let realm = RealmID(rawValue: "9341456442848752")
    let period = AccountingPeriod(year: 2026, month: 7)

    func context() -> RuleContext {
        RuleContext(period: period, materiality: .defaultPolicy, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false))
    }

    func dataSet(_ vendors: [LedgerVendor], coverage: Coverage = .complete) -> NormalizedDataSet {
        NormalizedDataSet(
            realmID: realm, period: period, transactions: [], vendors: vendors,
            coverage: coverage, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false)
        )
    }

    @Test("Normalization strips case, punctuation, whitespace, and a common suffix")
    func normalizationCollapsesVariants() {
        #expect(DuplicateVendorRule.normalize("ABC Plumbing, Inc.") == DuplicateVendorRule.normalize("abc plumbing inc"))
        #expect(DuplicateVendorRule.normalize("ABC Plumbing") != DuplicateVendorRule.normalize("ABC Plumbing Services"))
    }

    @Test("Two vendors that normalize identically produce one finding")
    func normalizedExactMatchProducesFinding() {
        let a = LedgerVendor(id: "1", displayName: "ABC Plumbing, Inc.")
        let b = LedgerVendor(id: "2", displayName: "abc plumbing inc")
        let outcome = DuplicateVendorRule.evaluate(dataSet([a, b]), context: context())

        guard case .findings(let findings) = outcome, findings.count == 1 else {
            Issue.record("expected one finding")
            return
        }
        #expect(findings[0].confidence == .high)
        #expect(findings[0].evidence.count == 2)
    }

    @Test("Two similarly-but-not-identically-named vendors produce no finding — conservative by design")
    func similarButNotIdenticalProducesNoFinding() {
        let a = LedgerVendor(id: "1", displayName: "ABC Plumbing")
        let b = LedgerVendor(id: "2", displayName: "ABC Plumbing Services")
        let outcome = DuplicateVendorRule.evaluate(dataSet([a, b]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass — this rule deliberately does not fuzzy-match")
            return
        }
    }

    @Test("An inactive vendor does not pair with an active one — assumed already handled/merged")
    func inactiveVendorExcluded() {
        let a = LedgerVendor(id: "1", displayName: "ABC Plumbing", isActive: true)
        let b = LedgerVendor(id: "2", displayName: "ABC Plumbing", isActive: false)
        let outcome = DuplicateVendorRule.evaluate(dataSet([a, b]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass — inactive vendors are excluded")
            return
        }
    }

    @Test("Three vendors normalizing identically produce one finding covering all three")
    func threeWayDuplicateProducesOneFinding() {
        let vendors = [
            LedgerVendor(id: "1", displayName: "ABC Plumbing"),
            LedgerVendor(id: "2", displayName: "ABC Plumbing LLC"),
            LedgerVendor(id: "3", displayName: "abc plumbing")
        ]
        let outcome = DuplicateVendorRule.evaluate(dataSet(vendors), context: context())

        guard case .findings(let findings) = outcome, findings.count == 1 else {
            Issue.record("expected one finding covering all three")
            return
        }
        #expect(findings[0].evidence.count == 3)
    }

    @Test("The rule never claims .pass on incomplete coverage")
    func neverClaimsPassOnPartialCoverage() {
        let outcome = DuplicateVendorRule.evaluate(
            dataSet([], coverage: .partial(reason: "sync incomplete")),
            context: context()
        )
        if case .pass = outcome {
            Issue.record("rule must not report .pass on partial coverage")
        }
    }
}
