import Testing
@testable import Core
import Foundation

@Suite("VL-TRANSPOSITION-001 — TransactionAmountTranspositionRule")
struct TransactionAmountTranspositionRuleTests {
    let realm = RealmID(rawValue: "9341456442848752")
    let period = AccountingPeriod(year: 2026, month: 7)

    func context() -> RuleContext {
        RuleContext(period: period, materiality: .defaultPolicy, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false))
    }

    func purchase(
        id: String,
        vendor: String?,
        amountMinorUnits: Int64,
        day: Int = 15,
        account: String? = "checking-1",
        isVoided: Bool = false
    ) -> LedgerTransaction {
        LedgerTransaction(
            id: id,
            entityKind: .purchase,
            vendorName: vendor,
            txnDate: AccountingDate(year: 2026, month: 7, day: day),
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

    @Test("A classic digit-transposition pair ($450 vs $540, same vendor/account, close dates) produces a finding")
    func classicTranspositionProducesFinding() {
        let txns = [
            purchase(id: "1", vendor: "Acme Supply", amountMinorUnits: 45_000, day: 10),
            purchase(id: "2", vendor: "Acme Supply", amountMinorUnits: 54_000, day: 12)
        ]
        let outcome = TransactionAmountTranspositionRule.evaluate(dataSet(txns), context: context())
        guard case .findings(let findings) = outcome, findings.count == 1 else {
            Issue.record("expected one finding")
            return
        }
        #expect(findings[0].confidence == .medium)
        #expect(findings[0].dollarExposure == Money(minorUnits: 9_000, currency: .usd))
        #expect(findings[0].evidence.count == 2)
    }

    @Test("Amounts differing by something NOT divisible by 9 do not produce a finding, even same vendor/account/date")
    func nonDivisibleBy9DifferenceProducesNoFinding() {
        let txns = [
            purchase(id: "1", vendor: "Acme Supply", amountMinorUnits: 10_000, day: 10),
            purchase(id: "2", vendor: "Acme Supply", amountMinorUnits: 10_500, day: 11) // diff = 500, not divisible by 9
        ]
        let outcome = TransactionAmountTranspositionRule.evaluate(dataSet(txns), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — 500 is not evenly divisible by 9")
            return
        }
    }

    @Test("Exact duplicate amounts (diff = 0) are not flagged — that's DuplicatePostedExpenseRule's job, not this rule's")
    func exactDuplicateAmountsAreNotFlagged() {
        let txns = [
            purchase(id: "1", vendor: "Acme Supply", amountMinorUnits: 45_000, day: 10),
            purchase(id: "2", vendor: "Acme Supply", amountMinorUnits: 45_000, day: 11)
        ]
        let outcome = TransactionAmountTranspositionRule.evaluate(dataSet(txns), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — identical amounts are not a transposition candidate")
            return
        }
    }

    @Test("Different vendors are never compared, even with a divisible-by-9 difference and close dates — this is exactly the noise the rule is scoped to avoid")
    func differentVendorsAreNeverCompared() {
        let txns = [
            purchase(id: "1", vendor: "Acme Supply", amountMinorUnits: 45_000, day: 10),
            purchase(id: "2", vendor: "Other Vendor", amountMinorUnits: 54_000, day: 11)
        ]
        let outcome = TransactionAmountTranspositionRule.evaluate(dataSet(txns), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — different vendors, never compared regardless of the amount math")
            return
        }
    }

    @Test("A pair more than 3 days apart is not compared, even same vendor/account with a divisible-by-9 difference")
    func farApartDatesAreNotCompared() {
        let txns = [
            purchase(id: "1", vendor: "Acme Supply", amountMinorUnits: 45_000, day: 1),
            purchase(id: "2", vendor: "Acme Supply", amountMinorUnits: 54_000, day: 20)
        ]
        let outcome = TransactionAmountTranspositionRule.evaluate(dataSet(txns), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — 19 days apart, outside the 3-day window")
            return
        }
    }

    @Test("Different payment accounts are not compared, even same vendor and close dates")
    func differentPaymentAccountsAreNotCompared() {
        let txns = [
            purchase(id: "1", vendor: "Acme Supply", amountMinorUnits: 45_000, day: 10, account: "checking-1"),
            purchase(id: "2", vendor: "Acme Supply", amountMinorUnits: 54_000, day: 11, account: "savings-1")
        ]
        let outcome = TransactionAmountTranspositionRule.evaluate(dataSet(txns), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — different payment accounts")
            return
        }
    }

    @Test("A voided transaction is excluded from comparison")
    func voidedTransactionsAreExcluded() {
        let txns = [
            purchase(id: "1", vendor: "Acme Supply", amountMinorUnits: 45_000, day: 10, isVoided: true),
            purchase(id: "2", vendor: "Acme Supply", amountMinorUnits: 54_000, day: 11)
        ]
        let outcome = TransactionAmountTranspositionRule.evaluate(dataSet(txns), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — one side is voided")
            return
        }
    }

    @Test("Below the materiality floor, no finding is produced even with a valid transposition signature")
    func belowMaterialityFloorProducesNoFinding() {
        let txns = [
            purchase(id: "1", vendor: "Acme Supply", amountMinorUnits: 100, day: 10),
            purchase(id: "2", vendor: "Acme Supply", amountMinorUnits: 190, day: 11) // diff = 90 minor units = $0.90
        ]
        let outcome = TransactionAmountTranspositionRule.evaluate(dataSet(txns), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — $0.90 difference is below the materiality floor")
            return
        }
    }

    @Test("A dismissed finding ID is not re-raised")
    func dismissedFindingIsNotReRaised() {
        let txns = [
            purchase(id: "1", vendor: "Acme Supply", amountMinorUnits: 45_000, day: 10),
            purchase(id: "2", vendor: "Acme Supply", amountMinorUnits: 54_000, day: 11)
        ]
        let findingID = FindingIDGenerator.makeID(
            ruleID: TransactionAmountTranspositionRule.identity.id,
            ruleVersion: TransactionAmountTranspositionRule.identity.version,
            realmID: realm, period: period,
            sortedAffectedIDs: ["1", "2"]
        )
        let dismissedContext = RuleContext(
            period: period, materiality: .defaultPolicy,
            companyFacts: CompanyFacts(customTxnNumbersForPurchases: false),
            dismissedFindingIDs: [findingID]
        )
        let outcome = TransactionAmountTranspositionRule.evaluate(dataSet(txns), context: dismissedContext)
        guard case .pass = outcome else {
            Issue.record("expected .pass — this exact finding was dismissed")
            return
        }
    }
}
