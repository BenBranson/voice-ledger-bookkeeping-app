import Testing
@testable import Core
import Foundation

@Suite("VL-RECON-MISSING-001 — BankFeedMissingPostingRule")
struct BankFeedMissingPostingRuleTests {
    let realm = RealmID(rawValue: "9341456442848752")
    let period = AccountingPeriod(year: 2026, month: 7)

    func context() -> RuleContext {
        RuleContext(period: period, materiality: .defaultPolicy, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false))
    }

    func statementLine(id: String, account: String = "checking-1", date: AccountingDate = AccountingDate(year: 2026, month: 7, day: 14), amountMinorUnits: Int64 = 48_620) -> LedgerTransaction {
        LedgerTransaction(
            id: id, entityKind: .importedBankStatementLine, vendorName: "PERMIAN SUPPLY",
            txnDate: date, totalAmount: Money(minorUnits: amountMinorUnits, currency: .usd),
            paymentAccountID: account, docNumber: nil, isVoided: false, memo: nil,
            provenance: .importedFile(documentID: "doc-1", importedAt: Date(), extractionMethod: .deterministicParse, coverage: .complete)
        )
    }

    func posted(id: String, account: String = "checking-1", date: AccountingDate = AccountingDate(year: 2026, month: 7, day: 14), amountMinorUnits: Int64 = 48_620, isVoided: Bool = false) -> LedgerTransaction {
        LedgerTransaction(
            id: id, entityKind: .purchase, vendorName: "Permian Supply",
            txnDate: date, totalAmount: Money(minorUnits: amountMinorUnits, currency: .usd),
            paymentAccountID: account, docNumber: nil, isVoided: isVoided, memo: nil,
            provenance: .qboAPI(readAt: Date())
        )
    }

    func dataSet(_ transactions: [LedgerTransaction], coverage: Coverage = .complete) -> NormalizedDataSet {
        NormalizedDataSet(
            realmID: realm, period: period, transactions: transactions,
            coverage: coverage, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false)
        )
    }

    @Test("No statement imported at all — .cannotEvaluate, never a silent .pass (Page 4's Type B honest-state requirement)")
    func noStatementImportedCannotEvaluate() {
        let onlyPosted = posted(id: "1")
        let outcome = BankFeedMissingPostingRule.evaluate(dataSet([onlyPosted]), context: context())

        guard case .cannotEvaluate = outcome else {
            Issue.record("expected .cannotEvaluate — no statement line present")
            return
        }
    }

    @Test("A statement line with a matching posted Purchase (same account/amount/near-date) produces no finding")
    func matchedStatementLineProducesNoFinding() {
        let line = statementLine(id: "s1")
        let match = posted(id: "p1")
        let outcome = BankFeedMissingPostingRule.evaluate(dataSet([line, match]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass — matched")
            return
        }
    }

    @Test("A statement line with NO matching posted transaction produces a .high-confidence finding")
    func unmatchedStatementLineProducesFinding() {
        let line = statementLine(id: "s1")
        let outcome = BankFeedMissingPostingRule.evaluate(dataSet([line]), context: context())

        guard case .findings(let findings) = outcome, findings.count == 1 else {
            Issue.record("expected one finding")
            return
        }
        #expect(findings[0].confidence == .high)
    }

    @Test("A posted match on a DIFFERENT account does not count as a match")
    func differentAccountDoesNotMatch() {
        let line = statementLine(id: "s1", account: "checking-1")
        let wrongAccount = posted(id: "p1", account: "amex-1")
        let outcome = BankFeedMissingPostingRule.evaluate(dataSet([line, wrongAccount]), context: context())

        guard case .findings(let findings) = outcome, findings.count == 1 else {
            Issue.record("expected one finding — the posted transaction is on a different account")
            return
        }
    }

    @Test("A voided posted transaction does not count as a match")
    func voidedPostedDoesNotMatch() {
        let line = statementLine(id: "s1")
        let voidedMatch = posted(id: "p1", isVoided: true)
        let outcome = BankFeedMissingPostingRule.evaluate(dataSet([line, voidedMatch]), context: context())

        guard case .findings(let findings) = outcome, findings.count == 1 else {
            Issue.record("expected one finding — the only posted match is voided")
            return
        }
    }

    @Test("A match within the near-date window (5 days) still counts")
    func nearDateMatchCounts() {
        let line = statementLine(id: "s1", date: AccountingDate(year: 2026, month: 7, day: 14))
        let nearMatch = posted(id: "p1", date: AccountingDate(year: 2026, month: 7, day: 17))
        let outcome = BankFeedMissingPostingRule.evaluate(dataSet([line, nearMatch]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass — within the 5-day window")
            return
        }
    }

    @Test("Below materiality floor produces no finding")
    func belowMaterialityFloorExcluded() {
        let line = statementLine(id: "s1", amountMinorUnits: 500)
        let outcome = BankFeedMissingPostingRule.evaluate(dataSet([line]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass")
            return
        }
    }

    @Test("A voided statement line is excluded")
    func voidedStatementLineExcluded() {
        let voided = LedgerTransaction(
            id: "s1", entityKind: .importedBankStatementLine, vendorName: "X",
            txnDate: AccountingDate(year: 2026, month: 7, day: 14), totalAmount: Money(minorUnits: 48_620, currency: .usd),
            paymentAccountID: "checking-1", docNumber: nil, isVoided: true, memo: nil,
            provenance: .importedFile(documentID: "doc-1", importedAt: Date(), extractionMethod: .deterministicParse, coverage: .complete)
        )
        let outcome = BankFeedMissingPostingRule.evaluate(dataSet([voided]), context: context())

        guard case .cannotEvaluate = outcome else {
            Issue.record("expected .cannotEvaluate — the only statement line is voided, so no statement lines remain")
            return
        }
    }
}
