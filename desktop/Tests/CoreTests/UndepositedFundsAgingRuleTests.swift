import Testing
@testable import Core
import Foundation

@Suite("VL-BS-UNDEP-001 — UndepositedFundsAgingRule")
struct UndepositedFundsAgingRuleTests {
    let realm = RealmID(rawValue: "9341456442848752")
    let period = AccountingPeriod(year: 2026, month: 7)
    let asOfDate = AccountingDate(year: 2026, month: 8, day: 17)

    func context() -> RuleContext {
        RuleContext(period: period, materiality: .defaultPolicy, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false), asOfDate: asOfDate)
    }

    func undepositedFundsAccount(id: String = "4") -> LedgerAccount {
        LedgerAccount(id: id, name: "Undeposited Funds", accountType: .otherCurrentAsset, accountSubType: "UndepositedFunds", currentBalance: .zero)
    }

    func payment(id: String, date: AccountingDate, account: String = "4", amountMinorUnits: Int64 = 40_000, isVoided: Bool = false) -> LedgerTransaction {
        LedgerTransaction(
            id: id, entityKind: .payment, vendorName: "Cool Cars",
            txnDate: date, totalAmount: Money(minorUnits: amountMinorUnits, currency: .usd),
            paymentAccountID: account, docNumber: nil, isVoided: isVoided, memo: nil,
            provenance: .qboAPI(readAt: Date())
        )
    }

    func dataSet(transactions: [LedgerTransaction], accounts: [LedgerAccount], deposits: [LedgerDeposit] = [], coverage: Coverage = .complete) -> NormalizedDataSet {
        NormalizedDataSet(
            realmID: realm, period: period, transactions: transactions, accounts: accounts, deposits: deposits,
            coverage: coverage, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false)
        )
    }

    @Test("A Payment aged past the threshold, never swept by any Deposit, produces a .high-confidence finding")
    func agedUnsweptPaymentProducesFinding() {
        let old = payment(id: "p1", date: AccountingDate(year: 2026, month: 7, day: 27)) // 21 days before asOfDate
        let outcome = UndepositedFundsAgingRule.evaluate(dataSet(transactions: [old], accounts: [undepositedFundsAccount()]), context: context())

        guard case .findings(let findings) = outcome, findings.count == 1 else {
            Issue.record("expected one finding")
            return
        }
        #expect(findings[0].confidence == .high)
    }

    @Test("A Payment swept by a real Deposit does NOT match, no matter how old — the exact false-positive this rule was built to avoid")
    func sweptPaymentDoesNotMatch() {
        let old = payment(id: "p1", date: AccountingDate(year: 2026, month: 7, day: 27))
        let deposit = LedgerDeposit(id: "d1", linkedPaymentIDs: ["p1"])
        let outcome = UndepositedFundsAgingRule.evaluate(dataSet(transactions: [old], accounts: [undepositedFundsAccount()], deposits: [deposit]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass — payment was swept by a real deposit")
            return
        }
    }

    @Test("A recent Payment (within the aging threshold) does not match")
    func recentPaymentDoesNotMatch() {
        let recent = payment(id: "p1", date: AccountingDate(year: 2026, month: 8, day: 15)) // 2 days before asOfDate
        let outcome = UndepositedFundsAgingRule.evaluate(dataSet(transactions: [recent], accounts: [undepositedFundsAccount()]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass — within the aging threshold")
            return
        }
    }

    @Test("A Payment deposited straight to a real bank account (not Undeposited Funds) does not match")
    func paymentToRealAccountDoesNotMatch() {
        let old = payment(id: "p1", date: AccountingDate(year: 2026, month: 7, day: 27), account: "checking-1")
        let outcome = UndepositedFundsAgingRule.evaluate(dataSet(transactions: [old], accounts: [undepositedFundsAccount()]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass — not deposited to Undeposited Funds")
            return
        }
    }

    @Test("No Undeposited Funds account in the chart of accounts at all — .pass, not an error")
    func noUndepositedFundsAccountAtAllIsPass() {
        let realAccount = LedgerAccount(id: "50", name: "Office Supplies", accountType: .expense, accountSubType: nil, currentBalance: .zero)
        let old = payment(id: "p1", date: AccountingDate(year: 2026, month: 7, day: 27), account: "checking-1")
        let outcome = UndepositedFundsAgingRule.evaluate(dataSet(transactions: [old], accounts: [realAccount]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass")
            return
        }
    }

    @Test("A voided payment is excluded")
    func voidedPaymentExcluded() {
        let old = payment(id: "p1", date: AccountingDate(year: 2026, month: 7, day: 27), isVoided: true)
        let outcome = UndepositedFundsAgingRule.evaluate(dataSet(transactions: [old], accounts: [undepositedFundsAccount()]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass")
            return
        }
    }

    @Test("Below materiality floor produces no finding")
    func belowMaterialityFloorExcluded() {
        let old = payment(id: "p1", date: AccountingDate(year: 2026, month: 7, day: 27), amountMinorUnits: 500)
        let outcome = UndepositedFundsAgingRule.evaluate(dataSet(transactions: [old], accounts: [undepositedFundsAccount()]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass")
            return
        }
    }

    @Test("The rule never claims .pass on incomplete coverage")
    func neverClaimsPassOnPartialCoverage() {
        let outcome = UndepositedFundsAgingRule.evaluate(
            dataSet(transactions: [], accounts: [], coverage: .partial(reason: "sync incomplete")),
            context: context()
        )
        if case .pass = outcome {
            Issue.record("rule must not report .pass on partial coverage")
        }
    }

    @Test("Two same-day payments of the same amount from one customer read as two findings, not one printed twice")
    func samePaymentsAreDistinguishable() {
        let a = payment(id: "157", date: AccountingDate(year: 2026, month: 7, day: 27))
        let b = payment(id: "158", date: AccountingDate(year: 2026, month: 7, day: 27))
        guard case .findings(let findings) = UndepositedFundsAgingRule.evaluate(dataSet(transactions: [a, b], accounts: [undepositedFundsAccount()]), context: context()) else {
            Issue.record("expected findings"); return
        }
        #expect(findings.count == 2)
        #expect(Set(findings.map(\.title)).count == 2)
        #expect(findings.contains { $0.title.hasSuffix("(QuickBooks payment 157)") })
        #expect(findings.allSatisfy { $0.narrative?.contains("(QuickBooks payment") == true })
    }
}
