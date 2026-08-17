import Testing
@testable import Core
import Foundation

@Suite("VL-VENDOR-MISMATCH-001 — VendorDescriptionMismatchRule")
struct VendorDescriptionMismatchRuleTests {
    let realm = RealmID(rawValue: "9341456442848752")
    let period = AccountingPeriod(year: 2026, month: 7)

    func context() -> RuleContext {
        RuleContext(period: period, materiality: .defaultPolicy, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false))
    }

    func statementLine(id: String, description: String, account: String = "checking-1", date: AccountingDate = AccountingDate(year: 2026, month: 7, day: 14), amountMinorUnits: Int64 = 48_620) -> LedgerTransaction {
        LedgerTransaction(
            id: id, entityKind: .importedBankStatementLine, vendorName: description,
            txnDate: date, totalAmount: Money(minorUnits: amountMinorUnits, currency: .usd),
            paymentAccountID: account, docNumber: nil, isVoided: false, memo: nil,
            provenance: .importedFile(documentID: "doc-1", importedAt: Date(), extractionMethod: .deterministicParse, coverage: .complete)
        )
    }

    func posted(id: String, vendor: String, account: String = "checking-1", date: AccountingDate = AccountingDate(year: 2026, month: 7, day: 14), amountMinorUnits: Int64 = 48_620) -> LedgerTransaction {
        LedgerTransaction(
            id: id, entityKind: .purchase, vendorName: vendor,
            txnDate: date, totalAmount: Money(minorUnits: amountMinorUnits, currency: .usd),
            paymentAccountID: account, docNumber: nil, isVoided: false, memo: nil,
            provenance: .qboAPI(readAt: Date())
        )
    }

    func dataSet(_ transactions: [LedgerTransaction], coverage: Coverage = .complete) -> NormalizedDataSet {
        NormalizedDataSet(
            realmID: realm, period: period, transactions: transactions,
            coverage: coverage, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false)
        )
    }

    @Test("No statement imported — .cannotEvaluate")
    func noStatementCannotEvaluate() {
        let outcome = VendorDescriptionMismatchRule.evaluate(dataSet([posted(id: "p1", vendor: "Permian Supply")]), context: context())
        guard case .cannotEvaluate = outcome else {
            Issue.record("expected .cannotEvaluate")
            return
        }
    }

    @Test("Sharing at least one word (e.g. 'Amex') is NOT flagged — conservative by design")
    func sharedWordDoesNotMatch() {
        let line = statementLine(id: "s1", description: "AMEX EPAYMENT 8827")
        let match = posted(id: "p1", vendor: "VL Spike Amex")
        let outcome = VendorDescriptionMismatchRule.evaluate(dataSet([line, match]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass — shared word 'amex'")
            return
        }
    }

    @Test("Zero shared words between statement description and posted vendor produces a .medium-confidence finding")
    func noSharedWordsProducesFinding() {
        let line = statementLine(id: "s1", description: "SQ COFFEE SHOP DOWNTOWN")
        let match = posted(id: "p1", vendor: "Random Vendor LLC")
        let outcome = VendorDescriptionMismatchRule.evaluate(dataSet([line, match]), context: context())

        guard case .findings(let findings) = outcome, findings.count == 1 else {
            Issue.record("expected one finding")
            return
        }
        #expect(findings[0].confidence == .medium)
    }

    @Test("A statement line with NO matching posted transaction produces no finding — this rule only reviews matches, VL-RECON-MISSING-001 handles the unmatched case")
    func unmatchedStatementLineProducesNoFinding() {
        let line = statementLine(id: "s1", description: "SQ COFFEE SHOP DOWNTOWN")
        let outcome = VendorDescriptionMismatchRule.evaluate(dataSet([line]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass — no match to review")
            return
        }
    }

    @Test("Below materiality floor produces no finding")
    func belowMaterialityFloorExcluded() {
        let line = statementLine(id: "s1", description: "SQ COFFEE SHOP", amountMinorUnits: 500)
        let match = posted(id: "p1", vendor: "Random Vendor LLC", amountMinorUnits: 500)
        let outcome = VendorDescriptionMismatchRule.evaluate(dataSet([line, match]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass")
            return
        }
    }

    @Test("A shared common suffix alone (Inc/LLC/Company) does not count as a real match — those are stop words")
    func sharedStopWordAloneDoesNotPreventAFinding() {
        let line = statementLine(id: "s1", description: "JOES PRESSURE WASHING LLC")
        let match = posted(id: "p1", vendor: "Random Vendor Company LLC")
        let outcome = VendorDescriptionMismatchRule.evaluate(dataSet([line, match]), context: context())

        guard case .findings(let findings) = outcome, findings.count == 1 else {
            Issue.record("expected one finding — the only shared word ('LLC') is a stop word, not a real match")
            return
        }
    }

    @Test("The rule never claims .pass on incomplete coverage")
    func neverClaimsPassOnPartialCoverage() {
        let line = statementLine(id: "s1", description: "SQ COFFEE SHOP")
        let match = posted(id: "p1", vendor: "Random Vendor LLC")
        let outcome = VendorDescriptionMismatchRule.evaluate(
            dataSet([line, match], coverage: .partial(reason: "sync incomplete")),
            context: context()
        )
        if case .pass = outcome {
            Issue.record("rule must not report .pass on partial coverage")
        }
    }
}
