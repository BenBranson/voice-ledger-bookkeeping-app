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

    func purchase(id: String) -> LedgerTransaction {
        LedgerTransaction(
            id: id,
            entityKind: .purchase,
            vendorName: "Permian Supply",
            txnDate: AccountingDate(year: 2026, month: 7, day: 14),
            totalAmount: Money(minorUnits: 48_620, currency: .usd),
            paymentAccountID: "checking-1",
            docNumber: "4471",
            isVoided: false,
            memo: nil,
            provenance: .qboAPI(readAt: Date())
        )
    }

    @Test("§8.2a: a fired relationship-class rule gates categorization-class rules for the same page, and the gate is recorded, not silent")
    func relationshipRuleGatesCategorizationRule() async {
        let engine = RuleEngine(rules: [FixtureRelationshipRule.self, DuplicatePostedExpenseRule.self])
        let input = NormalizedDataSet(
            realmID: realm, period: period,
            transactions: [purchase(id: "145"), purchase(id: "151")],
            coverage: .complete,
            companyFacts: CompanyFacts(customTxnNumbersForPurchases: false)
        )
        let evaluation = await engine.evaluate(page: .page3Transactions, input: input, context: context())

        // The relationship rule ran and fired.
        guard case .findings(let relFindings) = evaluation.results[FixtureRelationshipRule.identity.id]?.outcome,
              relFindings.count == 1 else {
            Issue.record("expected the fixture relationship rule to fire")
            return
        }

        // The categorization rule (VL-DUP-EXP-001) was gated — no result at
        // all is recorded for it under `results`, and the gate itself is
        // recorded under `gating`, not silently dropped.
        #expect(evaluation.results[DuplicatePostedExpenseRule.identity.id] == nil)
        #expect(evaluation.gating.contains { $0.suppressedRuleID == DuplicatePostedExpenseRule.identity.id })
        #expect(evaluation.gating.first?.gatingFindingID == "fixture-relationship-finding")
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
        let evaluation = await engine.evaluate(page: .page3Transactions, input: input, context: context())
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
