import Testing
@testable import Core
import Foundation

/// A fixture-only relationship-class rule. Not a real rule (no such rule
/// ships in this phase — docs/phase-0/08_RULE_ENGINE.md §8.2a is design-only
/// until a real relationship rule exists, per `NEXT_INSTRUCTION.md` Part 3).
/// It exists so §8.2a's gating branch in `RuleEngineActor.evaluate` is
/// exercised by a real test instead of only existing as dead code with a
/// comment promising it works.
private enum FixtureRelationshipRule: Rule {
    static let identity = RuleIdentity(
        id: RuleID(rawValue: "FIXTURE-REL-001"),
        version: RuleVersion(major: 1, minor: 0, patch: 0),
        title: "Fixture relationship rule",
        category: .duplicateExpense,
        ruleClass: .relationship,
        page: .page3Transactions,
        accountingPrinciple: "Test fixture only.",
        sourceDependencies: [SourceDependency(entity: .purchase)]
    )
    static let requirements = DataRequirements(entities: [.purchase], requiredCoverage: .complete)

    /// Always fires exactly one finding when there is at least one purchase —
    /// simple enough to make the gating assertion unambiguous.
    static func evaluate(_ input: NormalizedDataSet, context: RuleContext) -> RuleOutcome {
        guard let first = input.transactions.first else {
            return .pass(coverage: input.coverage, checkedCount: 0)
        }
        let finding = Finding(
            id: "fixture-relationship-finding",
            ruleID: identity.id,
            ruleVersion: identity.version,
            realmID: input.realmID,
            period: input.period,
            title: "Fixture relationship finding",
            severity: .low,
            confidence: .high,
            dollarExposure: first.totalAmount,
            evidence: [EvidenceItem(transactionID: first.id, highlightedFields: [])],
            proposedActions: [],
            provenance: [first.provenance]
        )
        return .findings([finding])
    }
}

@Suite("RuleEngine — gating and coverage")
struct RuleEngineGatingTests {
    let realm = RealmID(rawValue: "9341456442848752")
    let period = AccountingPeriod(year: 2026, month: 7)

    func context() -> RuleContext {
        RuleContext(period: period, materiality: .defaultPolicy, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false))
    }

    func purchase(id: String, vendor: String = "Permian Supply", amountMinorUnits: Int64 = 48_620) -> LedgerTransaction {
        LedgerTransaction(
            id: id,
            entityKind: .purchase,
            vendorName: vendor,
            txnDate: AccountingDate(year: 2026, month: 7, day: 14),
            totalAmount: Money(minorUnits: amountMinorUnits, currency: .usd),
            paymentAccountID: "checking-1",
            docNumber: "4471",
            isVoided: false,
            memo: nil,
            provenance: .qboAPI(readAt: Date())
        )
    }

    @Test("§8.2a: a fired relationship-class rule gates only the SPECIFIC transaction it explains — not the whole categorization rule, and not unrelated transactions")
    func relationshipRuleGatesOnlyTheAffectedTransaction() async {
        // FixtureRelationshipRule always fires on transactions.first — with
        // "145" first, it gates 145 only. 145/151 would otherwise be a T1
        // duplicate match; 200/201 is a second, unrelated T1 duplicate pair
        // that should NOT be gated by an unrelated relationship finding.
        let engine = RuleEngine(rules: [FixtureRelationshipRule.self, DuplicatePostedExpenseRule.self])
        let input = NormalizedDataSet(
            realmID: realm, period: period,
            transactions: [
                purchase(id: "145"), purchase(id: "151"),
                purchase(id: "200", vendor: "Odessa Water", amountMinorUnits: 12_000),
                purchase(id: "201", vendor: "Odessa Water", amountMinorUnits: 12_000)
            ],
            coverage: .complete,
            companyFacts: CompanyFacts(customTxnNumbersForPurchases: false)
        )
        let evaluation = await engine.evaluate(pages: [.page3Transactions], input: input, context: context())

        // The relationship rule ran and fired on 145.
        guard case .findings(let relFindings) = evaluation.results[FixtureRelationshipRule.identity.id]?.outcome,
              relFindings.count == 1, relFindings[0].evidence.first?.transactionID == "145" else {
            Issue.record("expected the fixture relationship rule to fire on transaction 145")
            return
        }

        // The categorization rule STILL RAN — it is not absent from
        // results — but the 145/151 pair is gone (145 was gated) while the
        // unrelated 200/201 pair still fired normally.
        guard case .findings(let catFindings) = evaluation.results[DuplicatePostedExpenseRule.identity.id]?.outcome else {
            Issue.record("expected the categorization rule to have run and produced findings for the ungated pair")
            return
        }
        #expect(catFindings.count == 1)
        #expect(catFindings.first?.evidence.contains { $0.transactionID == "200" } == true)
        #expect(catFindings.first?.evidence.contains { $0.transactionID == "145" } == false)

        // The gate is recorded, not silent, and scoped to the specific
        // transaction — not the whole rule.
        #expect(evaluation.gating.contains { $0.transactionID == "145" && $0.gatingRuleID == FixtureRelationshipRule.identity.id })
        #expect(evaluation.gating.first?.gatingFindingID == "fixture-relationship-finding")
    }

    @Test("Real rules: VL-CC-PAYMENT-001 (relationship) gates a specific transaction from VL-DUP-EXP-001 (categorization), other transactions unaffected")
    func realRelationshipRuleGatesRealCategorizationRule() async {
        let ccPurchase = LedgerTransaction(
            id: "cc-payment-1",
            entityKind: .purchase,
            vendorName: "Amex",
            txnDate: AccountingDate(year: 2026, month: 7, day: 20),
            totalAmount: Money(minorUnits: 50_000, currency: .usd),
            paymentAccountID: "checking-1",
            docNumber: nil,
            isVoided: false,
            memo: nil,
            lineAccountIDs: ["expense-account-1"],
            provenance: .qboAPI(readAt: Date())
        )
        let creditCardAccount = LedgerAccount(id: "cc-liability-1", name: "Amex", accountType: .creditCard)
        let expenseAccount = LedgerAccount(id: "expense-account-1", name: "Office Supplies", accountType: .expense)

        let engine = RuleEngine(rules: [CreditCardPaymentMiscodedRule.self, DuplicatePostedExpenseRule.self])
        let input = NormalizedDataSet(
            realmID: realm, period: period,
            transactions: [purchase(id: "145"), purchase(id: "151"), ccPurchase],
            accounts: [creditCardAccount, expenseAccount],
            coverage: .complete,
            companyFacts: CompanyFacts(customTxnNumbersForPurchases: false)
        )
        let evaluation = await engine.evaluate(pages: [.page3Transactions, .cleanupAssessment], input: input, context: context())

        guard case .findings(let ccFindings) = evaluation.results[CreditCardPaymentMiscodedRule.identity.id]?.outcome,
              ccFindings.count == 1 else {
            Issue.record("expected VL-CC-PAYMENT-001 to fire")
            return
        }
        // VL-DUP-EXP-001 still runs on this page and still finds the
        // unrelated 145/151 pair — the CC finding doesn't touch it.
        guard case .findings(let dupFindings) = evaluation.results[DuplicatePostedExpenseRule.identity.id]?.outcome,
              dupFindings.count == 1 else {
            Issue.record("expected VL-DUP-EXP-001 to still find the unrelated 145/151 pair")
            return
        }
        #expect(evaluation.gating.contains { $0.transactionID == "cc-payment-1" })
    }

    @Test("The engine never invokes a rule at all when coverage is partial")
    func engineNeverInvokesRuleOnPartialCoverage() async {
        let engine = RuleEngine(rules: [DuplicatePostedExpenseRule.self])
        let input = NormalizedDataSet(
            realmID: realm, period: period,
            transactions: [purchase(id: "145"), purchase(id: "151")], // would otherwise produce a finding
            coverage: .partial(reason: "pagination checksum mismatch"),
            companyFacts: CompanyFacts(customTxnNumbersForPurchases: false)
        )
        let evaluation = await engine.evaluate(pages: [.page3Transactions], input: input, context: context())
        guard case .cannotEvaluate = evaluation.results[DuplicatePostedExpenseRule.identity.id]?.outcome else {
            Issue.record("expected .cannotEvaluate — the rule must be gated before it ever sees the data")
            return
        }
    }

    @Test("Isolation: two realms with deliberately identical data produce findings scoped to their own realm only (§7.8 test 1)")
    func isolationAcrossTwoRealms() async {
        let realmA = RealmID(rawValue: "9341456442848752")
        let realmB = RealmID(rawValue: "9999999999999999")

        let inputA = NormalizedDataSet(
            realmID: realmA, period: period,
            transactions: [purchase(id: "145"), purchase(id: "151")],
            coverage: .complete,
            companyFacts: CompanyFacts(customTxnNumbersForPurchases: false)
        )
        let inputB = NormalizedDataSet(
            realmID: realmB, period: period,
            transactions: [purchase(id: "145"), purchase(id: "151")], // same IDs, deliberately
            coverage: .complete,
            companyFacts: CompanyFacts(customTxnNumbersForPurchases: false)
        )

        guard case .findings(let findingsA) = DuplicatePostedExpenseRule.evaluate(inputA, context: context()),
              case .findings(let findingsB) = DuplicatePostedExpenseRule.evaluate(inputB, context: context()) else {
            Issue.record("expected findings from both realms")
            return
        }

        #expect(findingsA.count == 1)
        #expect(findingsB.count == 1)
        // Same source data, different realm → different finding IDs. A
        // cross-realm ID collision would mean realm isn't actually part of
        // the finding's identity, which is exactly the isolation bug §7
        // exists to prevent.
        #expect(findingsA[0].id != findingsB[0].id)
        #expect(findingsA[0].realmID == realmA)
        #expect(findingsB[0].realmID == realmB)
    }
}
