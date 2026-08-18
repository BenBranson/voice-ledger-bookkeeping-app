import Testing
@testable import Core
import Foundation

@Suite("VL-CC-PAYMENT-001 — CreditCardPaymentMiscodedRule")
struct CreditCardPaymentMiscodedRuleTests {
    let realm = RealmID(rawValue: "9341456442848752")
    let period = AccountingPeriod(year: 2026, month: 7)

    func context() -> RuleContext {
        RuleContext(period: period, materiality: .defaultPolicy, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false))
    }

    func purchase(
        id: String,
        vendor: String,
        amountMinorUnits: Int64 = 50_000,
        lineAccountIDs: [String],
        lines: [LedgerTransactionLine] = [],
        syncToken: String? = nil,
        isVoided: Bool = false
    ) -> LedgerTransaction {
        LedgerTransaction(
            id: id,
            entityKind: .purchase,
            vendorName: vendor,
            txnDate: AccountingDate(year: 2026, month: 7, day: 20),
            totalAmount: Money(minorUnits: amountMinorUnits, currency: .usd),
            paymentAccountID: "checking-1",
            docNumber: nil,
            isVoided: isVoided,
            memo: nil,
            lineAccountIDs: lineAccountIDs,
            lines: lines,
            syncToken: syncToken,
            provenance: .qboAPI(readAt: Date())
        )
    }

    func dataSet(_ transactions: [LedgerTransaction], accounts: [LedgerAccount], coverage: Coverage = .complete) -> NormalizedDataSet {
        NormalizedDataSet(
            realmID: realm, period: period, transactions: transactions, accounts: accounts,
            coverage: coverage, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false)
        )
    }

    @Test("Structural match: vendor name exactly matches a real Credit Card account, line coded to Expense — .high confidence")
    func structuralMatchIsHighConfidence() {
        let accounts = [
            LedgerAccount(id: "cc-1", name: "Amex", accountType: .creditCard),
            LedgerAccount(id: "exp-1", name: "Office Supplies", accountType: .expense)
        ]
        let txn = purchase(id: "1", vendor: "Amex", lineAccountIDs: ["exp-1"])
        let outcome = CreditCardPaymentMiscodedRule.evaluate(dataSet([txn], accounts: accounts), context: context())

        guard case .findings(let findings) = outcome, findings.count == 1 else {
            Issue.record("expected one finding")
            return
        }
        #expect(findings[0].confidence == .high)
    }

    @Test("Keyword-only match: vendor name contains a card-issuer keyword but no matching Account exists — .medium confidence")
    func keywordOnlyMatchIsMediumConfidence() {
        let accounts = [LedgerAccount(id: "exp-1", name: "Office Supplies", accountType: .expense)]
        let txn = purchase(id: "1", vendor: "American Express", lineAccountIDs: ["exp-1"])
        let outcome = CreditCardPaymentMiscodedRule.evaluate(dataSet([txn], accounts: accounts), context: context())

        guard case .findings(let findings) = outcome, findings.count == 1 else {
            Issue.record("expected one finding")
            return
        }
        #expect(findings[0].confidence == .medium)
    }

    @Test("A payment coded to the credit card's OWN liability account (correct treatment) produces no finding")
    func correctlyCodedPaymentProducesNoFinding() {
        let accounts = [LedgerAccount(id: "cc-1", name: "Amex", accountType: .creditCard)]
        let txn = purchase(id: "1", vendor: "Amex", lineAccountIDs: ["cc-1"]) // coded to the liability account itself
        let outcome = CreditCardPaymentMiscodedRule.evaluate(dataSet([txn], accounts: accounts), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass — this is the CORRECT treatment, not a finding")
            return
        }
    }

    @Test("A non-card vendor coded to an expense account produces no finding — the whole point is specificity")
    func unrelatedVendorProducesNoFinding() {
        let accounts = [LedgerAccount(id: "exp-1", name: "Office Supplies", accountType: .expense)]
        let txn = purchase(id: "1", vendor: "Permian Supply", lineAccountIDs: ["exp-1"])
        let outcome = CreditCardPaymentMiscodedRule.evaluate(dataSet([txn], accounts: accounts), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass")
            return
        }
    }

    @Test("A transaction with no line-account data is excluded, not guessed at")
    func missingLineAccountDataIsExcludedNotGuessed() {
        let accounts = [LedgerAccount(id: "exp-1", name: "Office Supplies", accountType: .expense)]
        let txn = purchase(id: "1", vendor: "Visa", lineAccountIDs: [])
        let outcome = CreditCardPaymentMiscodedRule.evaluate(dataSet([txn], accounts: accounts), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass — missing line data must not be treated as a match")
            return
        }
    }

    @Test("Below materiality floor produces no finding")
    func belowMaterialityFloorExcluded() {
        let accounts = [LedgerAccount(id: "exp-1", name: "Office Supplies", accountType: .expense)]
        let txn = purchase(id: "1", vendor: "Visa", amountMinorUnits: 500, lineAccountIDs: ["exp-1"]) // $5, below $25 floor
        let outcome = CreditCardPaymentMiscodedRule.evaluate(dataSet([txn], accounts: accounts), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass — below the materiality floor")
            return
        }
    }

    @Test("A voided transaction is excluded")
    func voidedTransactionExcluded() {
        let accounts = [LedgerAccount(id: "exp-1", name: "Office Supplies", accountType: .expense)]
        let txn = purchase(id: "1", vendor: "Visa", lineAccountIDs: ["exp-1"], isVoided: true)
        let outcome = CreditCardPaymentMiscodedRule.evaluate(dataSet([txn], accounts: accounts), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass — voided transactions are excluded")
            return
        }
    }

    @Test("The rule never claims .pass on incomplete coverage")
    func neverClaimsPassOnPartialCoverage() {
        let outcome = CreditCardPaymentMiscodedRule.evaluate(
            dataSet([], accounts: [], coverage: .partial(reason: "sync incomplete")),
            context: context()
        )
        if case .pass = outcome {
            Issue.record("rule must not report .pass on partial coverage")
        }
    }

    @Test("Structural match + single line + SyncToken + a real matching Credit Card account -> .stagedAPI with fix details")
    func structuralMatchSingleLineWithSyncTokenGetsStagedFix() {
        let accounts = [
            LedgerAccount(id: "cc-1", name: "Amex", accountType: .creditCard),
            LedgerAccount(id: "exp-1", name: "Office Supplies", accountType: .expense)
        ]
        let txn = purchase(
            id: "1", vendor: "Amex", lineAccountIDs: ["exp-1"],
            lines: [LedgerTransactionLine(id: "0", accountID: "exp-1")],
            syncToken: "3"
        )
        let outcome = CreditCardPaymentMiscodedRule.evaluate(dataSet([txn], accounts: accounts), context: context())

        guard case .findings(let findings) = outcome, findings.count == 1,
              let action = findings[0].proposedActions.first else {
            Issue.record("expected one finding with one action")
            return
        }
        #expect(action.resolution == .stagedAPI)
        guard let details = action.apiWriteDetails else {
            Issue.record("expected apiWriteDetails to be populated")
            return
        }
        #expect(details.purchaseID == "1")
        #expect(details.lineID == "0")
        #expect(details.expectedSyncToken == "3")
        #expect(details.currentAccountID == "exp-1")
        #expect(details.currentAccountName == "Office Supplies")
        #expect(details.suggestedAccountID == "cc-1")
        #expect(details.suggestedAccountName == "Amex")
    }

    @Test("Structural match without a SyncToken (e.g. not yet populated by sync) stays .manualQBO — no fix details")
    func structuralMatchMissingSyncTokenStaysManual() {
        let accounts = [
            LedgerAccount(id: "cc-1", name: "Amex", accountType: .creditCard),
            LedgerAccount(id: "exp-1", name: "Office Supplies", accountType: .expense)
        ]
        let txn = purchase(
            id: "1", vendor: "Amex", lineAccountIDs: ["exp-1"],
            lines: [LedgerTransactionLine(id: "0", accountID: "exp-1")],
            syncToken: nil
        )
        let outcome = CreditCardPaymentMiscodedRule.evaluate(dataSet([txn], accounts: accounts), context: context())

        guard case .findings(let findings) = outcome, let action = findings.first?.proposedActions.first else {
            Issue.record("expected one finding with one action")
            return
        }
        #expect(action.resolution == .manualQBO)
        #expect(action.apiWriteDetails == nil)
    }

    @Test("A dismissed finding ID is never reproduced — dismissedFindingIDs is a real suppression, not just a UI filter")
    func dismissedFindingIsNotReproduced() {
        let accounts = [
            LedgerAccount(id: "cc-1", name: "Amex", accountType: .creditCard),
            LedgerAccount(id: "exp-1", name: "Office Supplies", accountType: .expense)
        ]
        let txn = purchase(id: "1", vendor: "Amex", lineAccountIDs: ["exp-1"])
        let firstRun = CreditCardPaymentMiscodedRule.evaluate(dataSet([txn], accounts: accounts), context: context())
        guard case .findings(let findings) = firstRun, let findingID = findings.first?.id else {
            Issue.record("expected a finding on the first run")
            return
        }

        let dismissedContext = RuleContext(
            period: period, materiality: .defaultPolicy,
            companyFacts: CompanyFacts(customTxnNumbersForPurchases: false),
            dismissedFindingIDs: [findingID]
        )
        let secondRun = CreditCardPaymentMiscodedRule.evaluate(dataSet([txn], accounts: accounts), context: dismissedContext)
        guard case .pass = secondRun else {
            Issue.record("expected .pass — the dismissed finding must not be reproduced")
            return
        }
    }

    @Test("Keyword-only match never gets a staged fix even with lines and a SyncToken present — only structural matches qualify")
    func keywordOnlyMatchNeverGetsStagedFix() {
        let accounts = [LedgerAccount(id: "exp-1", name: "Office Supplies", accountType: .expense)]
        let txn = purchase(
            id: "1", vendor: "American Express", lineAccountIDs: ["exp-1"],
            lines: [LedgerTransactionLine(id: "0", accountID: "exp-1")],
            syncToken: "1"
        )
        let outcome = CreditCardPaymentMiscodedRule.evaluate(dataSet([txn], accounts: accounts), context: context())

        guard case .findings(let findings) = outcome, let action = findings.first?.proposedActions.first else {
            Issue.record("expected one finding with one action")
            return
        }
        #expect(action.resolution == .manualQBO)
        #expect(action.apiWriteDetails == nil)
    }
}
