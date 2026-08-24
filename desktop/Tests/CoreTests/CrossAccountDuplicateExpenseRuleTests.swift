import Testing
@testable import Core
import Foundation

@Suite("VL-DUP-EXP-002 — CrossAccountDuplicateExpenseRule")
struct CrossAccountDuplicateExpenseRuleTests {
    let realm = RealmID(rawValue: "9341456442848752")
    let period = AccountingPeriod(year: 2026, month: 7)

    func context() -> RuleContext {
        RuleContext(period: period, materiality: .defaultPolicy, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false))
    }

    func purchase(id: String, vendor: String = "Permian Supply", date: AccountingDate = AccountingDate(year: 2026, month: 7, day: 14), amountMinorUnits: Int64 = 48_620, account: String = "checking-1", isVoided: Bool = false) -> LedgerTransaction {
        LedgerTransaction(
            id: id,
            entityKind: .purchase,
            vendorName: vendor,
            txnDate: date,
            totalAmount: Money(minorUnits: amountMinorUnits, currency: .usd),
            paymentAccountID: account,
            docNumber: nil,
            isVoided: isVoided,
            memo: nil,
            provenance: .qboAPI(readAt: Date())
        )
    }

    func dataSet(_ transactions: [LedgerTransaction], coverage: Coverage = .complete) -> NormalizedDataSet {
        NormalizedDataSet(
            realmID: realm, period: period, transactions: transactions,
            coverage: coverage, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false)
        )
    }

    @Test("Same vendor/amount/near-date, DIFFERENT payment account, produces a .medium-confidence finding")
    func crossAccountMatchProducesFinding() {
        let a = purchase(id: "1", account: "checking-1")
        let b = purchase(id: "2", account: "amex-1")
        let outcome = CrossAccountDuplicateExpenseRule.evaluate(dataSet([a, b]), context: context())

        guard case .findings(let findings) = outcome, findings.count == 1 else {
            Issue.record("expected one finding")
            return
        }
        #expect(findings[0].confidence == .medium)
    }

    @Test("SAME payment account does NOT match — that's VL-DUP-EXP-001's territory, not this rule's")
    func samePaymentAccountDoesNotMatch() {
        let a = purchase(id: "1", account: "checking-1")
        let b = purchase(id: "2", account: "checking-1")
        let outcome = CrossAccountDuplicateExpenseRule.evaluate(dataSet([a, b]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass — same-account matches belong to VL-DUP-EXP-001")
            return
        }
    }

    @Test("More than 3 days apart does not match")
    func beyondNearDateWindowDoesNotMatch() {
        let a = purchase(id: "1", date: AccountingDate(year: 2026, month: 7, day: 1), account: "checking-1")
        let b = purchase(id: "2", date: AccountingDate(year: 2026, month: 7, day: 10), account: "amex-1")
        let outcome = CrossAccountDuplicateExpenseRule.evaluate(dataSet([a, b]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass — beyond the 3-day window")
            return
        }
    }

    @Test("A voided purchase is excluded")
    func voidedPurchaseExcluded() {
        let a = purchase(id: "1", account: "checking-1")
        let b = purchase(id: "2", account: "amex-1", isVoided: true)
        let outcome = CrossAccountDuplicateExpenseRule.evaluate(dataSet([a, b]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass")
            return
        }
    }

    @Test("Below materiality floor produces no finding")
    func belowMaterialityFloorExcluded() {
        let a = purchase(id: "1", amountMinorUnits: 500, account: "checking-1")
        let b = purchase(id: "2", amountMinorUnits: 500, account: "amex-1")
        let outcome = CrossAccountDuplicateExpenseRule.evaluate(dataSet([a, b]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass")
            return
        }
    }

    @Test("A Bill with the same vendor/date/amount as a Purchase does not trigger this rule — entity-scoped to Purchase")
    func billEntityDoesNotMatch() {
        let aPurchase = purchase(id: "1", account: "checking-1")
        let theBill = LedgerTransaction(
            id: "2", entityKind: .bill, vendorName: "Permian Supply",
            txnDate: AccountingDate(year: 2026, month: 7, day: 14),
            totalAmount: Money(minorUnits: 48_620, currency: .usd),
            paymentAccountID: "ap-1", docNumber: nil, isVoided: false, memo: nil,
            provenance: .qboAPI(readAt: Date())
        )
        let outcome = CrossAccountDuplicateExpenseRule.evaluate(dataSet([aPurchase, theBill]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass — a Bill must not pair with a Purchase in this rule")
            return
        }
    }

    // MARK: - Hardening carried over from VL-DUP-EXP-001's Gauntlet Loop pass
    // (2026-08-23) — same rule shape, same class of gaps found there first.

    @Test("GAUNTLET: Finding.vendorName is populated, so Client Memory's 'Always Dismiss for <vendor>' can match a VL-DUP-EXP-002 finding")
    func gauntletVendorNameIsPopulated() {
        let a = purchase(id: "1", vendor: "Permian Supply", account: "checking-1")
        let b = purchase(id: "2", vendor: "Permian Supply", account: "amex-1")
        let outcome = CrossAccountDuplicateExpenseRule.evaluate(dataSet([a, b]), context: context())
        guard case .findings(let findings) = outcome, let finding = findings.first else {
            Issue.record("expected a finding")
            return
        }
        #expect(finding.vendorName == "Permian Supply")
    }

    @Test("GAUNTLET: two entries sharing a literal id are excluded — a data-pipeline anomaly, never two distinct real records")
    func gauntletSameIDAnomalyExcluded() {
        let a = purchase(id: "999", account: "checking-1")
        let b = purchase(id: "999", account: "amex-1")
        let outcome = CrossAccountDuplicateExpenseRule.evaluate(dataSet([a, b]), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — a.id == b.id can never represent two distinct QBO records, got \(outcome)")
            return
        }
    }

    @Test("GAUNTLET: a large NEGATIVE-amount cross-account pair is compared on magnitude, not sign — it still fires and clears the materiality floor")
    func gauntletNegativeAmountComparedOnMagnitude() {
        let a = purchase(id: "1", amountMinorUnits: -500_000, account: "checking-1")
        let b = purchase(id: "2", amountMinorUnits: -500_000, account: "amex-1")
        let outcome = CrossAccountDuplicateExpenseRule.evaluate(dataSet([a, b]), context: context())
        guard case .findings(let findings) = outcome else {
            Issue.record("expected a finding for a $5,000-magnitude pair regardless of sign, got \(outcome)")
            return
        }
        #expect(findings.count == 1)
        #expect(findings[0].dollarExposure == Money(minorUnits: 500_000, currency: .usd))
        #expect(findings[0].title == "Possible duplicate expense across accounts — \(findings[0].dollarExposure)")
    }

    @Test("GAUNTLET: evidence never claims 'paymentAccount' as matched — this rule's own defining condition REQUIRES the two accounts to differ, so claiming it matched would be an outright false statement")
    func gauntletEvidenceDoesNotClaimPaymentAccountMatched() {
        let a = purchase(id: "1", account: "checking-1")
        let b = purchase(id: "2", account: "amex-1")
        let outcome = CrossAccountDuplicateExpenseRule.evaluate(dataSet([a, b]), context: context())
        guard case .findings(let findings) = outcome, let finding = findings.first else {
            Issue.record("expected a finding")
            return
        }
        #expect(finding.evidence.allSatisfy { !$0.highlightedFields.contains("paymentAccount") })
    }

    @Test("The rule never claims .pass on incomplete coverage")
    func neverClaimsPassOnPartialCoverage() {
        let outcome = CrossAccountDuplicateExpenseRule.evaluate(
            dataSet([], coverage: .partial(reason: "sync incomplete")),
            context: context()
        )
        if case .pass = outcome {
            Issue.record("rule must not report .pass on partial coverage")
        }
    }
}
