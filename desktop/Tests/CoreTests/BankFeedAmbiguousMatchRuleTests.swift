import Testing
@testable import Core
import Foundation

@Suite("VL-RECON-AMBIGUOUS-001 — BankFeedAmbiguousMatchRule")
struct BankFeedAmbiguousMatchRuleTests {
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

    @Test("No statement imported at all — .cannotEvaluate")
    func noStatementImportedCannotEvaluate() {
        let outcome = BankFeedAmbiguousMatchRule.evaluate(dataSet([posted(id: "p1")]), context: context())
        guard case .cannotEvaluate = outcome else {
            Issue.record("expected .cannotEvaluate — no statement line present")
            return
        }
    }

    @Test("A statement line matching exactly one posted transaction produces no finding")
    func singleMatchProducesNoFinding() {
        let line = statementLine(id: "s1")
        let match = posted(id: "p1")
        let outcome = BankFeedAmbiguousMatchRule.evaluate(dataSet([line, match]), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — exactly one match, unambiguous")
            return
        }
    }

    @Test("A statement line matching TWO posted transactions equally well produces a .medium-confidence finding")
    func twoMatchesProducesFinding() {
        let line = statementLine(id: "s1")
        let matchA = posted(id: "p1")
        let matchB = posted(id: "p2")
        let outcome = BankFeedAmbiguousMatchRule.evaluate(dataSet([line, matchA, matchB]), context: context())
        guard case .findings(let findings) = outcome, findings.count == 1 else {
            Issue.record("expected one finding")
            return
        }
        #expect(findings[0].confidence == .medium)
    }

    @Test("A voided posted transaction does not count toward the match count")
    func voidedPostedExcludedFromCount() {
        let line = statementLine(id: "s1")
        let realMatch = posted(id: "p1")
        let voidedMatch = posted(id: "p2", isVoided: true)
        let outcome = BankFeedAmbiguousMatchRule.evaluate(dataSet([line, realMatch, voidedMatch]), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — only one non-voided match")
            return
        }
    }

    @Test("A statement line with no matches at all produces no finding (that's VL-RECON-MISSING-001's job)")
    func noMatchesProducesNoFinding() {
        let line = statementLine(id: "s1")
        let outcome = BankFeedAmbiguousMatchRule.evaluate(dataSet([line]), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — zero matches is not this rule's concern")
            return
        }
    }

    @Test("Below materiality floor produces no finding")
    func belowMaterialityFloorExcluded() {
        let line = statementLine(id: "s1", amountMinorUnits: 500)
        let matchA = posted(id: "p1", amountMinorUnits: 500)
        let matchB = posted(id: "p2", amountMinorUnits: 500)
        let outcome = BankFeedAmbiguousMatchRule.evaluate(dataSet([line, matchA, matchB]), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass")
            return
        }
    }
}
