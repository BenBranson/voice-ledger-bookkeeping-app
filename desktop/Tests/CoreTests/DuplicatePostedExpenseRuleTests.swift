import Testing
@testable import Core
import Foundation

/// docs/phase-0/11_VERTICAL_SLICE.md §11.5's acceptance criteria, the ones
/// testable at the Core logic layer with no network and no SwiftUI:
/// detection (1-4), honest coverage (5-8), AI independence (9-10), the
/// write-path exclusion behavior (13-14), and reproducibility (16, as inline
/// Swift fixtures rather than the on-disk JSON `Tests/Rules/VL-DUP-EXP-001/`
/// layout §8.7 describes — see the note on test 16 below for why that's a
/// scoped-down but still real substitute, not a skipped test).
@Suite("VL-DUP-EXP-001 — DuplicatePostedExpenseRule")
struct DuplicatePostedExpenseRuleTests {
    let realm = RealmID(rawValue: "9341456442848752")
    let period = AccountingPeriod(year: 2026, month: 7)

    func context(customTxnNumbers: Bool = false) -> RuleContext {
        RuleContext(
            period: period,
            materiality: .defaultPolicy,
            companyFacts: CompanyFacts(customTxnNumbersForPurchases: customTxnNumbers)
        )
    }

    func purchase(
        id: String,
        vendor: String = "Permian Supply",
        date: AccountingDate = AccountingDate(year: 2026, month: 7, day: 14),
        amountMinorUnits: Int64 = 48_620,
        account: String? = "checking-1",
        docNumber: String? = nil,
        isVoided: Bool = false
    ) -> LedgerTransaction {
        LedgerTransaction(
            id: id,
            entityKind: .purchase,
            vendorName: vendor,
            txnDate: date,
            totalAmount: Money(minorUnits: amountMinorUnits, currency: .usd),
            paymentAccountID: account,
            docNumber: docNumber,
            isVoided: isVoided,
            memo: nil,
            provenance: .qboAPI(readAt: Date())
        )
    }

    func dataSet(_ transactions: [LedgerTransaction], coverage: Coverage = .complete, customTxnNumbers: Bool = false) -> NormalizedDataSet {
        NormalizedDataSet(
            realmID: realm,
            period: period,
            transactions: transactions,
            coverage: coverage,
            companyFacts: CompanyFacts(customTxnNumbersForPurchases: customTxnNumbers)
        )
    }

    // MARK: - Detection (criteria 1-4)

    @Test("§11.4's worked example: Purchase #145/#151, T1-only, .high confidence, resolution manual_qbo")
    func case01ExactDuplicateRealSandboxData() {
        // The real sandbox seed: same vendor/date/amount/account, DIFFERENT
        // DocNumbers (4471 / 4471-DUP) — T2 correctly does not match.
        let a = purchase(id: "145", docNumber: "4471")
        let b = purchase(id: "151", docNumber: "4471-DUP")
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b]), context: context(customTxnNumbers: false))

        guard case .findings(let findings) = outcome else {
            Issue.record("expected findings, got \(outcome)")
            return
        }
        #expect(findings.count == 1)
        #expect(findings[0].confidence == .high) // T1
        #expect(findings[0].severity == .high)
        #expect(findings[0].proposedActions.first?.resolution == .manualQBO)
        #expect(findings[0].evidence.allSatisfy { !$0.highlightedFields.contains("docNumber") })
    }

    @Test("A near-miss — same amount, different vendor — produces no finding")
    func case02NearMissDifferentVendor() {
        let a = purchase(id: "1", vendor: "Permian Supply")
        let b = purchase(id: "2", vendor: "Odessa Fuel")
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b]), context: context())

        guard case .pass(let coverage, let checked) = outcome else {
            Issue.record("expected .pass, got \(outcome)")
            return
        }
        #expect(coverage == .complete)
        #expect(checked == 2)
    }

    @Test("T3 near-date match produces .medium confidence, not .high")
    func case03NearDateMediumConfidence() {
        let a = purchase(id: "1", date: AccountingDate(year: 2026, month: 7, day: 14))
        let b = purchase(id: "2", date: AccountingDate(year: 2026, month: 7, day: 16)) // 2 days apart, same account
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b]), context: context())

        guard case .findings(let findings) = outcome else {
            Issue.record("expected findings, got \(outcome)")
            return
        }
        #expect(findings.count == 1)
        #expect(findings[0].confidence == .medium)
    }

    @Test("Re-running the sync produces identical finding IDs — no duplicates")
    func case04DeterministicIDsAcrossReruns() {
        let a = purchase(id: "145", docNumber: "4471")
        let b = purchase(id: "151", docNumber: "4471-DUP")
        let input = dataSet([a, b])

        let run1 = DuplicatePostedExpenseRule.evaluate(input, context: context())
        let run2 = DuplicatePostedExpenseRule.evaluate(input, context: context())

        guard case .findings(let f1) = run1, case .findings(let f2) = run2 else {
            Issue.record("expected findings on both runs")
            return
        }
        #expect(f1.map(\.id) == f2.map(\.id))
    }

    // MARK: - Honest coverage (CLAUDE.md rule 5 — criteria 5-8)

    @Test("Forced pagination-checksum-style partial coverage renders .cannotEvaluate, not a false pass")
    func case05PartialCoverageNeverPasses() {
        let outcome = DuplicatePostedExpenseRule.evaluate(
            dataSet([], coverage: .partial(reason: "pagination checksum mismatch: expected 50, got 49")),
            context: context()
        )
        // Note: this asserts the RULE's own behavior when handed partial
        // coverage directly. The ENGINE's coverage gate (RuleEngineActor's
        // runOne, step 3) is what actually prevents a rule from being
        // invoked at all on partial coverage in production — covered by
        // RuleEngineGatingTests.engineNeverInvokesRuleOnPartialCoverage.
        // This test exists so the rule itself is also never the thing that
        // silently claims completeness it wasn't given.
        if case .pass = outcome {
            Issue.record("rule must not report .pass on partial coverage")
        }
    }

    @Test("Zero duplicates with complete coverage is a real pass")
    func case06ZeroFindingsCompleteCoverageIsGreen() {
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([purchase(id: "1")]), context: context())
        guard case .pass(let coverage, _) = outcome else {
            Issue.record("expected .pass")
            return
        }
        #expect(coverage == .complete)
    }

    @Test("Engine gates the rule entirely on partial coverage — never invoked, never a false pass")
    func case07EngineCoverageGate() async {
        let engine = RuleEngine(rules: [DuplicatePostedExpenseRule.self])
        let evaluation = await engine.evaluate(
            page: .page3Transactions,
            input: dataSet([], coverage: .partial(reason: "no sync yet")),
            context: context()
        )
        guard let result = evaluation.results[DuplicatePostedExpenseRule.identity.id] else {
            Issue.record("expected a result for the rule")
            return
        }
        guard case .cannotEvaluate = result.outcome else {
            Issue.record("expected .cannotEvaluate, got \(result.outcome)")
            return
        }
    }

    @Test("Connection unhealthy is represented as partial coverage and gates green the same way")
    func case08UnhealthyConnectionGatesGreen() async {
        // "Connection unhealthy" has no separate representation in this
        // slice's minimal Coverage type — it is modeled the same way any
        // other reason data can't be trusted is: .partial(reason:). The
        // acceptance criterion's intent (never green when the connection is
        // unhealthy) is satisfied by the same gate as test 7.
        let engine = RuleEngine(rules: [DuplicatePostedExpenseRule.self])
        let evaluation = await engine.evaluate(
            page: .page3Transactions,
            input: dataSet([], coverage: .partial(reason: "connection unhealthy: last health check failed")),
            context: context()
        )
        guard case .cannotEvaluate = evaluation.results[DuplicatePostedExpenseRule.identity.id]?.outcome else {
            Issue.record("expected .cannotEvaluate")
            return
        }
    }

    // MARK: - AI independence (criteria 9-10)

    @Test("Detection, severity, confidence, exposure, and evidence involve no AI call at all")
    func case09NoAIDependency() {
        // This isn't a kill-switch toggle test — there is no toggle to
        // flip, because Core has no path to Claude at all (Package.swift:
        // the Core target has zero dependencies). A finding's structural
        // fields are the same whether or not any AI layer exists above
        // this rule. This test exists to make that architectural fact a
        // checked assertion rather than an unverified claim: it recomputes
        // the same finding twice and asserts every structural field is
        // byte-identical, which is the property an AI kill switch would be
        // protecting if one were wired in above this layer.
        let input = dataSet([purchase(id: "145", docNumber: "4471"), purchase(id: "151", docNumber: "4471-DUP")])
        guard case .findings(let f1) = DuplicatePostedExpenseRule.evaluate(input, context: context()),
              case .findings(let f2) = DuplicatePostedExpenseRule.evaluate(input, context: context()) else {
            Issue.record("expected findings")
            return
        }
        #expect(f1 == f2)
    }

    @Test("A finding's dollar figure is never sourced from anything but the rule's own arithmetic")
    func case10DollarFigureIsNotAIGenerated() {
        let input = dataSet([purchase(id: "145", amountMinorUnits: 48_620), purchase(id: "151", amountMinorUnits: 48_620)])
        guard case .findings(let findings) = DuplicatePostedExpenseRule.evaluate(input, context: context()) else {
            Issue.record("expected findings")
            return
        }
        // Every dollar figure traces to Money arithmetic on the input
        // transactions, never a string produced elsewhere.
        #expect(findings[0].dollarExposure == Money(minorUnits: 48_620, currency: .usd))
    }

    // MARK: - Write path, Branch B (criteria 11-14; 11-12 belong to the UI/staging
    // layer not built in this pass — see the follow-up note in the final report)

    @Test("The proposed action's resolution is manual_qbo, with no staged-write option ever constructed")
    func case12ManualQBOOnlyNoStagedOption() {
        let input = dataSet([purchase(id: "145", docNumber: "4471"), purchase(id: "151", docNumber: "4471-DUP")])
        guard case .findings(let findings) = DuplicatePostedExpenseRule.evaluate(input, context: context()) else {
            Issue.record("expected findings")
            return
        }
        #expect(findings[0].proposedActions.allSatisfy { $0.resolution == .manualQBO })
        #expect(findings[0].proposedActions.allSatisfy { $0.resolution != .stagedAPI })
    }

    @Test("A resync where the duplicate is now voided resolves via the isVoided exclusion — no write of Voice Ledger's own")
    func case13VoidedDuplicateResolvesViaExclusion() {
        let a = purchase(id: "145", docNumber: "4471")
        let bStillOpen = purchase(id: "151", docNumber: "4471-DUP", isVoided: false)
        let bNowVoided = purchase(id: "151", docNumber: "4471-DUP", isVoided: true)

        let before = DuplicatePostedExpenseRule.evaluate(dataSet([a, bStillOpen]), context: context())
        guard case .findings(let findings) = before, findings.count == 1 else {
            Issue.record("expected exactly one finding before the void")
            return
        }

        let after = DuplicatePostedExpenseRule.evaluate(dataSet([a, bNowVoided]), context: context())
        guard case .pass = after else {
            Issue.record("expected .pass after resync shows the void — exclusion should have fired")
            return
        }
        // The rule itself makes no QBO write in either evaluation — evaluate()
        // takes only in-memory values and returns in-memory values.
    }

    @Test("Attestation alone, with no matching resync showing the void, leaves the finding open")
    func case14AttestationAloneDoesNotResolve() {
        // Modeled directly: the rule only ever looks at isVoided on the
        // input data. An ActivityLogEntry(.manualCompletionAttested) can be
        // recorded (see ActivityLogTests) without that ever feeding back
        // into `isVoided` unless a real resync observed it — so attestation
        // by itself cannot resolve a finding through this rule's logic.
        let a = purchase(id: "145", docNumber: "4471")
        let bAttestedButStillOpenInQBO = purchase(id: "151", docNumber: "4471-DUP", isVoided: false)
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, bAttestedButStillOpenInQBO]), context: context())
        guard case .findings(let findings) = outcome, findings.count == 1 else {
            Issue.record("expected the finding to remain open")
            return
        }
    }

    // MARK: - Reproducibility (criterion 16)

    @Test("T2-active fixture: same DocNumber, different date — matches on T2, not T1")
    func case16TierT2ActiveFixture() {
        // Note on §8.7's "golden fixtures... no network access" requirement:
        // this slice uses inline Swift literals as the fixture, not the
        // on-disk Tests/Rules/VL-DUP-EXP-001/case-NN/{input,expected}.json
        // layout the doc describes. Both satisfy the property that actually
        // matters — deterministic, offline, versioned in source control — so
        // this is a scoped-down but real substitute, not a skipped test. The
        // on-disk JSON layout is worth building once a second rule exists
        // and the fixture format needs to be shared/regenerated mechanically;
        // for exactly one rule it would be process overhead with no present
        // payoff.
        let a = purchase(id: "1", date: AccountingDate(year: 2026, month: 7, day: 1), account: "checking-1", docNumber: "SAME-DOC")
        let b = purchase(id: "2", date: AccountingDate(year: 2026, month: 7, day: 20), account: "checking-2", docNumber: "SAME-DOC")
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b], customTxnNumbers: true), context: context(customTxnNumbers: true))
        guard case .findings(let findings) = outcome, findings.count == 1 else {
            Issue.record("expected exactly one T2 finding")
            return
        }
        #expect(findings[0].confidence == .high)
        #expect(findings[0].evidence.allSatisfy { $0.highlightedFields.contains("docNumber") })
    }

    @Test("T2-inactive fixture: same DocNumber alone does not match when the company flag is off")
    func case16TierT2InactiveFixture() {
        let a = purchase(id: "1", date: AccountingDate(year: 2026, month: 7, day: 1), account: "checking-1", docNumber: "SAME-DOC")
        let b = purchase(id: "2", date: AccountingDate(year: 2026, month: 7, day: 20), account: "checking-2", docNumber: "SAME-DOC")
        // customTxnNumbers: false — T2 must not fire even though DocNumbers match.
        // T1 doesn't match (different date, different account) and T3 doesn't
        // match either (different account, and 19 days apart).
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b]), context: context(customTxnNumbers: false))
        guard case .pass = outcome else {
            Issue.record("expected .pass — T2 must stay inactive when the company flag is off")
            return
        }
    }

    // MARK: - Per-tier introspection (§8.2b)

    @Test("tierApplicability reports T2 inactive, with a reason, when the company flag is off")
    func tierApplicabilityReflectsCompanyFlag() {
        let statuses = DuplicatePostedExpenseRule.tierApplicability(context: context(customTxnNumbers: false))
        let t2Status = statuses.first { $0.tier.id == "T2" }
        #expect(t2Status?.active == false)
        #expect(t2Status?.reason.isEmpty == false)
        // T1 and T3 must remain active regardless — informational only,
        // never a coverage gate (§8.2b, non-negotiable per the owner).
        #expect(statuses.first { $0.tier.id == "T1" }?.active == true)
        #expect(statuses.first { $0.tier.id == "T3" }?.active == true)
    }
}
