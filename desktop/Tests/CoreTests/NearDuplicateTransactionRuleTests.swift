import Testing
@testable import Core
import Foundation

@Suite("VL-DUP-NEAR-001 — NearDuplicateTransactionRule")
struct NearDuplicateTransactionRuleTests {
    let realm = RealmID(rawValue: "9341456442848752")
    let period = AccountingPeriod(year: 2026, month: 7)

    func context(dismissed: Set<String> = []) -> RuleContext {
        RuleContext(period: period, materiality: .defaultPolicy, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false), dismissedFindingIDs: dismissed)
    }

    func txn(_ id: String, _ kind: QBOEntityKind = .bill, vendor: String = "Home Depot", day: Int = 10, cents: Int64 = 48_620, voided: Bool = false) -> LedgerTransaction {
        LedgerTransaction(
            id: id, entityKind: kind, vendorName: vendor,
            txnDate: AccountingDate(year: 2026, month: 7, day: day),
            totalAmount: Money(minorUnits: cents, currency: .usd),
            paymentAccountID: "acct-1", docNumber: nil, isVoided: voided, memo: nil,
            provenance: .qboAPI(readAt: Date())
        )
    }

    func evaluate(_ txns: [LedgerTransaction], coverage: Coverage = .complete, context ctx: RuleContext? = nil) -> RuleOutcome {
        NearDuplicateTransactionRule.evaluate(
            NormalizedDataSet(realmID: realm, period: period, transactions: txns, coverage: coverage, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false)),
            context: ctx ?? context()
        )
    }

    func findings(_ outcome: RuleOutcome) -> [Finding] {
        if case .findings(let f) = outcome { return f }
        return []
    }

    @Test("Payee spelled differently, same amount, 2 days apart → one low-confidence finding")
    func nameVariantMatches() {
        let f = findings(evaluate([txn("1", vendor: "Home Depot"), txn("2", vendor: "HOME DEPOT, Inc.", day: 12)]))
        #expect(f.count == 1)
        #expect(f.first?.confidence == .low)
    }

    @Test("Same payee 5 days apart is caught; 6 days apart is not")
    func windowIsFiveDays() {
        #expect(findings(evaluate([txn("1", day: 10), txn("2", day: 15)])).count == 1)
        guard case .pass = evaluate([txn("1", day: 10), txn("2", day: 16)]) else {
            Issue.record("6 days apart must pass"); return
        }
    }

    @Test("Pairs the exact rules already report are not double-flagged")
    func skipsExactRuleTerritory() {
        guard case .pass = evaluate([txn("1", .bill, day: 10), txn("2", .bill, day: 10)]) else {
            Issue.record("same-day same-name bills belong to VL-DUP-BILL-001"); return
        }
        guard case .pass = evaluate([txn("1", .purchase, day: 10), txn("2", .purchase, day: 13)]) else {
            Issue.record("same-name purchases within 3 days belong to VL-DUP-EXP rules"); return
        }
        #expect(findings(evaluate([txn("1", .purchase, day: 10), txn("2", .purchase, day: 14)])).count == 1)
    }

    @Test("Different transaction types, amounts, or genuinely different payees never pair")
    func noCrossTypeOrDifferentPayee() {
        guard case .pass = evaluate([txn("1", .bill), txn("2", .invoice, day: 11)]) else { Issue.record("cross-type"); return }
        guard case .pass = evaluate([txn("1"), txn("2", day: 11, cents: 48_621)]) else { Issue.record("amount"); return }
        guard case .pass = evaluate([txn("1", vendor: "Home Depot"), txn("2", vendor: "Home Goods", day: 11)]) else { Issue.record("payee"); return }
    }

    @Test("Voided transactions and dismissed findings are excluded")
    func exclusions() {
        guard case .pass = evaluate([txn("1", vendor: "ACME LLC"), txn("2", vendor: "Acme", day: 11, voided: true)]) else { Issue.record("voided"); return }
        let id = findings(evaluate([txn("1", vendor: "ACME LLC"), txn("2", vendor: "Acme", day: 11)])).first!.id
        guard case .pass = evaluate([txn("1", vendor: "ACME LLC"), txn("2", vendor: "Acme", day: 11)], context: context(dismissed: [id])) else { Issue.record("dismissed"); return }
    }

    @Test("Partial coverage with nothing found is cannotEvaluate, never a green pass")
    func partialCoverageNeverPasses() {
        guard case .cannotEvaluate = evaluate([txn("1")], coverage: .partial(reason: "page 2 not loaded")) else {
            Issue.record("expected cannotEvaluate"); return
        }
    }
}
