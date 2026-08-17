import Testing
@testable import Core
import Foundation

@Suite("VL-VENDCREDIT-UNAPPLIED-001 — UnappliedVendorCreditRule")
struct UnappliedVendorCreditRuleTests {
    let realm = RealmID(rawValue: "9341456442848752")
    let period = AccountingPeriod(year: 2026, month: 7)
    let asOfDate = AccountingDate(year: 2026, month: 8, day: 17)

    func context() -> RuleContext {
        RuleContext(period: period, materiality: .defaultPolicy, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false), asOfDate: asOfDate)
    }

    func credit(id: String, date: AccountingDate, balanceMinorUnits: Int64, totalMinorUnits: Int64? = nil, vendor: String = "VL Spike Permian Supply") -> LedgerVendorCredit {
        LedgerVendorCredit(
            id: id, vendorName: vendor, txnDate: date,
            totalAmount: Money(minorUnits: totalMinorUnits ?? balanceMinorUnits, currency: .usd),
            balance: Money(minorUnits: balanceMinorUnits, currency: .usd),
            provenance: .qboAPI(readAt: Date())
        )
    }

    func dataSet(vendorCredits: [LedgerVendorCredit], coverage: Coverage = .complete) -> NormalizedDataSet {
        NormalizedDataSet(
            realmID: realm, period: period, transactions: [], vendorCredits: vendorCredits,
            coverage: coverage, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false)
        )
    }

    @Test("A vendor credit aged past the threshold, still unapplied (nonzero balance), produces a .high-confidence finding")
    func agedUnappliedCreditProducesFinding() {
        // 2026-07-28 to 2026-08-17 asOfDate = well past 30 days? Let's use an older date.
        let old = credit(id: "vc1", date: AccountingDate(year: 2026, month: 6, day: 1), balanceMinorUnits: 5_000)
        let outcome = UnappliedVendorCreditRule.evaluate(dataSet(vendorCredits: [old]), context: context())

        guard case .findings(let findings) = outcome, findings.count == 1 else {
            Issue.record("expected one finding")
            return
        }
        #expect(findings[0].confidence == .high)
    }

    @Test("A fully applied credit (balance == 0) does not match, no matter how old")
    func fullyAppliedCreditDoesNotMatch() {
        let old = credit(id: "vc1", date: AccountingDate(year: 2026, month: 6, day: 1), balanceMinorUnits: 0, totalMinorUnits: 5_000)
        let outcome = UnappliedVendorCreditRule.evaluate(dataSet(vendorCredits: [old]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass — fully applied")
            return
        }
    }

    @Test("A recent credit (within the 30-day threshold) does not match")
    func recentCreditDoesNotMatch() {
        let recent = credit(id: "vc1", date: AccountingDate(year: 2026, month: 8, day: 10), balanceMinorUnits: 5_000) // 7 days before asOfDate
        let outcome = UnappliedVendorCreditRule.evaluate(dataSet(vendorCredits: [recent]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass — within the aging threshold")
            return
        }
    }

    @Test("A partially applied credit (balance < total, still nonzero) still matches once aged")
    func partiallyAppliedCreditStillMatches() {
        let old = credit(id: "vc1", date: AccountingDate(year: 2026, month: 6, day: 1), balanceMinorUnits: 3_000, totalMinorUnits: 5_000)
        let outcome = UnappliedVendorCreditRule.evaluate(dataSet(vendorCredits: [old]), context: context())

        guard case .findings(let findings) = outcome, findings.count == 1 else {
            Issue.record("expected one finding — partial balance is still unapplied")
            return
        }
        #expect(findings[0].dollarExposure == Money(minorUnits: 3_000, currency: .usd))
    }

    @Test("Below materiality floor produces no finding")
    func belowMaterialityFloorExcluded() {
        let old = credit(id: "vc1", date: AccountingDate(year: 2026, month: 6, day: 1), balanceMinorUnits: 500)
        let outcome = UnappliedVendorCreditRule.evaluate(dataSet(vendorCredits: [old]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass")
            return
        }
    }

    @Test("No vendor credits at all produces .pass with zero checked, not .cannotEvaluate")
    func noVendorCreditsAtAllIsPass() {
        let outcome = UnappliedVendorCreditRule.evaluate(dataSet(vendorCredits: []), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass")
            return
        }
    }

    @Test("The rule never claims .pass on incomplete coverage")
    func neverClaimsPassOnPartialCoverage() {
        let outcome = UnappliedVendorCreditRule.evaluate(
            dataSet(vendorCredits: [], coverage: .partial(reason: "sync incomplete")),
            context: context()
        )
        if case .pass = outcome {
            Issue.record("rule must not report .pass on partial coverage")
        }
    }
}
