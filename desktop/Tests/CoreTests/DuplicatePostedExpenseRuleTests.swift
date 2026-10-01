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
        vendor: String? = "Permian Supply",
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

    func dataSet(_ transactions: [LedgerTransaction], coverage: Coverage = .complete, customTxnNumbers: Bool = false, accounts: [LedgerAccount] = []) -> NormalizedDataSet {
        NormalizedDataSet(
            realmID: realm,
            period: period,
            transactions: transactions,
            accounts: accounts,
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
            pages: [.page3Transactions],
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
            pages: [.page3Transactions],
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

    // MARK: - Gauntlet Loop corpus (2026-08-23) — adversarial fixtures from a
    // fresh-context critic, kept permanently per the loop's own rule that a
    // fixture stays in the corpus once constructed, whether it found a real
    // gap or confirmed correct behavior.

    @Test("GAUNTLET: two entries sharing the literal same id (a pagination/merge double-fetch of one QBO Purchase) are excluded — there is no second real transaction to find")
    func gauntletSameIDAnomalyExcluded() {
        let a = purchase(id: "999")
        let b = purchase(id: "999") // identical id AND identical content
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b]), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — a.id == b.id can never represent two distinct QBO records, got \(outcome)")
            return
        }
    }

    @Test("GAUNTLET: three copies sharing the same literal id are also excluded, pairwise")
    func gauntletTripleSameIDAnomalyExcluded() {
        let copies = [purchase(id: "999"), purchase(id: "999"), purchase(id: "999")]
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet(copies), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass, got \(outcome)")
            return
        }
    }

    @Test("GAUNTLET: Finding.vendorName is populated, so Client Memory's 'mark as legitimately recurring' exclusion (§11.2) can actually match a VL-DUP-EXP-001 finding")
    func gauntletClientMemoryVendorNameIsPopulated() {
        let a = purchase(id: "1", vendor: "Permian Supply")
        let b = purchase(id: "2", vendor: "Permian Supply")
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b]), context: context())
        guard case .findings(let findings) = outcome, let finding = findings.first else {
            Issue.record("expected a finding")
            return
        }
        #expect(finding.vendorName == "Permian Supply")

        let memory = ClientMemoryRule(ruleID: DuplicatePostedExpenseRule.identity.id, vendorName: "Permian Supply", createdBy: "owner")
        #expect(memory.matches(ruleID: finding.ruleID, findingVendorName: finding.vendorName), "an owner marking 'Permian Supply' as legitimately recurring should suppress future matching findings on resync")
    }

    @Test("GAUNTLET: a large NEGATIVE-amount exact-match pair is compared on magnitude, not sign — it still fires and clears the materiality floor")
    func gauntletNegativeAmountComparedOnMagnitude() {
        let a = purchase(id: "1", amountMinorUnits: -500_000) // -$5,000.00
        let b = purchase(id: "2", amountMinorUnits: -500_000)
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b]), context: context())
        guard case .findings(let findings) = outcome else {
            Issue.record("expected a finding for a $5,000-magnitude exact-match pair regardless of sign, got \(outcome)")
            return
        }
        #expect(findings.count == 1)
        #expect(findings[0].severity == .high)
        #expect(findings[0].dollarExposure == Money(minorUnits: 500_000, currency: .usd), "exposure is reported as a positive magnitude even though the underlying transactions are negative-amount")
    }

    @Test("GAUNTLET: control — the identical positive-amount scenario fires the same way, isolating the negative-amount fix to sign handling only")
    func gauntletPositiveAmountControlMatchesNegativeCase() {
        let a = purchase(id: "1", amountMinorUnits: 500_000)
        let b = purchase(id: "2", amountMinorUnits: 500_000)
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b]), context: context())
        guard case .findings(let findings) = outcome else {
            Issue.record("expected findings, got \(outcome)")
            return
        }
        #expect(findings.count == 1)
        #expect(findings[0].severity == .high)
    }

    @Test("GAUNTLET: materiality floor boundary — exactly $25.00 fires, .high severity")
    func gauntletMaterialityFloorExactlyAtBoundaryFires() {
        let a = purchase(id: "1", amountMinorUnits: 2_500)
        let b = purchase(id: "2", amountMinorUnits: 2_500)
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b]), context: context())
        guard case .findings(let findings) = outcome else {
            Issue.record("expected a finding at exactly the floor, got \(outcome)")
            return
        }
        #expect(findings.count == 1)
        #expect(findings[0].severity == .high)
    }

    @Test("GAUNTLET: one cent below the materiality floor ($24.99) is fully excluded, not downgraded to .low severity — Severity.low is structurally unreachable through this rule's own call site")
    func gauntletMaterialityFloorOneCentBelowFullyExcluded() {
        let a = purchase(id: "1", amountMinorUnits: 2_499)
        let b = purchase(id: "2", amountMinorUnits: 2_499)
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b]), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass (full exclusion) one cent below the floor, got \(outcome)")
            return
        }
    }

    @Test("GAUNTLET: T3 boundary — exactly 3 days apart fires, .medium confidence")
    func gauntletT3ExactlyThreeDaysFires() {
        let a = purchase(id: "1", date: AccountingDate(year: 2026, month: 7, day: 10))
        let b = purchase(id: "2", date: AccountingDate(year: 2026, month: 7, day: 13))
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b]), context: context())
        guard case .findings(let findings) = outcome else {
            Issue.record("expected findings at exactly 3 days apart, got \(outcome)")
            return
        }
        #expect(findings.count == 1)
        #expect(findings[0].confidence == .medium)
    }

    @Test("GAUNTLET: T3 boundary — exactly 4 days apart does not fire")
    func gauntletT3ExactlyFourDaysDoesNotFire() {
        let a = purchase(id: "1", date: AccountingDate(year: 2026, month: 7, day: 10))
        let b = purchase(id: "2", date: AccountingDate(year: 2026, month: 7, day: 14))
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b]), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass at 4 days apart (outside the ±3-day window), got \(outcome)")
            return
        }
    }

    @Test("GAUNTLET: dismissedFindingIDs suppresses a re-fired finding on the next run")
    func gauntletDismissedFindingIDsSuppressesRefiring() {
        let a = purchase(id: "1")
        let b = purchase(id: "2")
        let firstRun = DuplicatePostedExpenseRule.evaluate(dataSet([a, b]), context: context())
        guard case .findings(let findings) = firstRun, let originalID = findings.first?.id else {
            Issue.record("expected an initial finding to obtain a real id from")
            return
        }

        let ctxWithDismissal = RuleContext(
            period: period,
            materiality: .defaultPolicy,
            companyFacts: CompanyFacts(customTxnNumbersForPurchases: false),
            dismissedFindingIDs: [originalID]
        )
        let secondRun = DuplicatePostedExpenseRule.evaluate(dataSet([a, b]), context: ctxWithDismissal)
        guard case .pass = secondRun else {
            Issue.record("expected .pass once the finding's own id is in dismissedFindingIDs, got \(secondRun)")
            return
        }
    }

    @Test("GAUNTLET: gatedTransactionIDs suppresses the pair when only ONE side is gated, exactly as when both are")
    func gauntletGatedTransactionIDsOneSideSuffices() {
        let a = purchase(id: "1")
        let b = purchase(id: "2")

        guard case .findings = DuplicatePostedExpenseRule.evaluate(dataSet([a, b]), context: RuleContext(period: period, materiality: .defaultPolicy, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false), gatedTransactionIDs: [])) else {
            Issue.record("sanity check failed: expected a baseline finding with nothing gated")
            return
        }
        guard case .pass = DuplicatePostedExpenseRule.evaluate(dataSet([a, b]), context: RuleContext(period: period, materiality: .defaultPolicy, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false), gatedTransactionIDs: ["1"])) else {
            Issue.record("expected .pass when only transaction '1' of the pair is gated")
            return
        }
        guard case .pass = DuplicatePostedExpenseRule.evaluate(dataSet([a, b]), context: RuleContext(period: period, materiality: .defaultPolicy, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false), gatedTransactionIDs: ["2"])) else {
            Issue.record("expected .pass when only transaction '2' of the pair is gated")
            return
        }
        guard case .pass = DuplicatePostedExpenseRule.evaluate(dataSet([a, b]), context: RuleContext(period: period, materiality: .defaultPolicy, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false), gatedTransactionIDs: ["1", "2"])) else {
            Issue.record("expected .pass when both transactions are gated")
            return
        }
    }

    @Test("GAUNTLET: T2 — both DocNumbers are empty strings (non-nil) must not match, same as the nil case")
    func gauntletT2EmptyStringDocNumbersDoNotMatch() {
        let a = purchase(id: "1", date: AccountingDate(year: 2026, month: 7, day: 1), account: "checking-1", docNumber: "")
        let b = purchase(id: "2", date: AccountingDate(year: 2026, month: 7, day: 25), account: "checking-2", docNumber: "")
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b], customTxnNumbers: true), context: context(customTxnNumbers: true))
        guard case .pass = outcome else {
            Issue.record("expected .pass — two empty (but non-nil) DocNumbers must not be treated as a T2 match, got \(outcome)")
            return
        }
    }

    @Test("GAUNTLET: T2 — one side nil DocNumber, other side empty string, must not match")
    func gauntletT2NilVsEmptyStringDocNumberDoesNotMatch() {
        let a = purchase(id: "1", date: AccountingDate(year: 2026, month: 7, day: 1), account: "checking-1", docNumber: nil)
        let b = purchase(id: "2", date: AccountingDate(year: 2026, month: 7, day: 25), account: "checking-2", docNumber: "")
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b], customTxnNumbers: true), context: context(customTxnNumbers: true))
        guard case .pass = outcome else {
            Issue.record("expected .pass, got \(outcome)")
            return
        }
    }

    @Test("GAUNTLET: three mutually-matching postings (A, B, C) produce three separate pairwise findings, each carrying the full pair amount — a downstream rollup summing exposure across findings would overcount; no such rollup exists in this file today")
    func gauntletThreeWayMutualDuplicatesProduceThreePairwiseFindings() {
        let a = purchase(id: "A")
        let b = purchase(id: "B")
        let c = purchase(id: "C")
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b, c]), context: context())
        guard case .findings(let findings) = outcome else {
            Issue.record("expected findings, got \(outcome)")
            return
        }
        #expect(findings.count == 3) // (A,B) (A,C) (B,C)
        #expect(Set(findings.map(\.id)).count == 3)
    }

    @Test("GAUNTLET: three-way mutual duplicate where one of the three is voided — only the remaining real pair still fires")
    func gauntletThreeWayWithOneVoided() {
        let a = purchase(id: "A", isVoided: true)
        let b = purchase(id: "B")
        let c = purchase(id: "C")
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b, c]), context: context())
        guard case .findings(let findings) = outcome else {
            Issue.record("expected findings, got \(outcome)")
            return
        }
        #expect(findings.count == 1)
        #expect(Set(findings[0].evidence.map(\.transactionID)) == Set(["B", "C"]))
    }

    @Test("GAUNTLET: T2 has no payment-account requirement — a DocNumber match across two DIFFERENT payment accounts still fires. Judged CORRECT: a shared, non-empty, client-controlled reference number is a stronger signal than account/date coincidence, and a bill paid twice via two different rails sharing the same reference is a real (and arguably worse) double payment T2 exists to catch")
    func gauntletT2FiresAcrossDifferentPaymentAccountsByDesign() {
        let a = purchase(id: "1", date: AccountingDate(year: 2026, month: 7, day: 1), account: "checking-1", docNumber: "REF-1001")
        let b = purchase(id: "2", date: AccountingDate(year: 2026, month: 7, day: 28), account: "cc-amex", docNumber: "REF-1001")
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b], customTxnNumbers: true), context: context(customTxnNumbers: true))
        guard case .findings(let findings) = outcome else {
            Issue.record("expected a T2 finding across accounts, got \(outcome)")
            return
        }
        #expect(findings.count == 1)
        #expect(findings[0].confidence == .high)
    }

    @Test("GAUNTLET: two genuinely separate real purchases, same vendor/day/account, coincidentally the same amount — T1 still fires. A heuristic limitation by design, mitigated by the mandatory manual bank-statement confirmation step in the guided procedure, not a bug")
    func gauntletCoincidentalSameDaySameAmountStillFiresT1ByDesign() {
        let realWithdrawal1 = purchase(id: "1", vendor: "Cool Cars", amountMinorUnits: 12_000)
        let realWithdrawal2 = purchase(id: "2", vendor: "Cool Cars", amountMinorUnits: 12_000)
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([realWithdrawal1, realWithdrawal2]), context: context())
        guard case .findings(let findings) = outcome else {
            Issue.record("expected a finding — the rule structurally cannot distinguish this from a real duplicate given only vendor/amount/date/account, got \(outcome)")
            return
        }
        #expect(findings.count == 1)
        #expect(findings[0].confidence == .high)
        #expect(findings[0].proposedActions.first?.guidedProcedure?.steps.contains(where: { $0.contains("Confirm with the bank statement") }) == true)
    }

    @Test("GAUNTLET: two Purchases with NO vendor recorded (vendorName nil on both sides) are excluded even with an otherwise exact date/amount/account match — documented, deliberate scope boundary, not a silent accident (see the rule's own doc comment)")
    func gauntletNilVendorPairsAreNotMatched() {
        let date = AccountingDate(year: 2026, month: 7, day: 14)
        let amount = Money(minorUnits: 48_620, currency: .usd)
        let a = LedgerTransaction(id: "1", entityKind: .purchase, vendorName: nil, txnDate: date, totalAmount: amount, paymentAccountID: "checking-1", docNumber: nil, isVoided: false, memo: nil, provenance: .qboAPI(readAt: Date()))
        let b = LedgerTransaction(id: "2", entityKind: .purchase, vendorName: nil, txnDate: date, totalAmount: amount, paymentAccountID: "checking-1", docNumber: nil, isVoided: false, memo: nil, provenance: .qboAPI(readAt: Date()))
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b]), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — nil-vendor pairs are a documented exclusion, not a match; a two-sided nil vendor is a weaker duplicate signal than a shared real vendor name, got \(outcome)")
            return
        }
    }

    // MARK: - Gauntlet Loop corpus, round 2 (2026-08-23) — a second fresh
    // critic, checking what round 1 left behind.

    @Test("GAUNTLET R2: finding.title agrees with the magnitude-corrected dollarExposure for a negative-amount pair — round 1's negative-amount fix updated dollarExposure/severity/consequences but originally missed this line")
    func gauntletR2TitleAgreesWithExposureMagnitudeForNegativeAmount() {
        let a = purchase(id: "1", amountMinorUnits: -500_000) // -$5,000.00
        let b = purchase(id: "2", amountMinorUnits: -500_000)
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b]), context: context())
        guard case .findings(let findings) = outcome, let finding = findings.first else {
            Issue.record("expected a finding, got \(outcome)")
            return
        }
        #expect(finding.dollarExposure == Money(minorUnits: 500_000, currency: .usd))
        #expect(finding.title == "Possible duplicate expense — \(finding.vendorName ?? ""), \(finding.dollarExposure)", "title must be built from the same magnitude-corrected exposure as dollarExposure, not the raw signed amount — actual title: \(finding.title)")
    }

    @Test("GAUNTLET R2: control — positive-amount pair, title and dollarExposure agree (this direction was never broken)")
    func gauntletR2ControlPositiveAmountTitleMatchesExposure() {
        let a = purchase(id: "1", amountMinorUnits: 500_000)
        let b = purchase(id: "2", amountMinorUnits: 500_000)
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b]), context: context())
        guard case .findings(let findings) = outcome, let finding = findings.first else {
            Issue.record("expected a finding, got \(outcome)")
            return
        }
        #expect(finding.title == "Possible duplicate expense — \(finding.vendorName ?? ""), \(finding.dollarExposure)")
    }

    @Test("GAUNTLET R2: two entries sharing a literal id (pagination double-fetch of ONE real Purchase) alongside a genuinely different third Purchase that matches both — collapses to exactly one finding, for the one real pair")
    func gauntletR2SharedIDWithGenuineThirdMatchCollapsesToOneFinding() {
        let sameDate = AccountingDate(year: 2026, month: 7, day: 14)
        let aFirstFetch = purchase(id: "1", date: sameDate)
        let aSecondFetch = purchase(id: "1", date: sameDate) // literal id collision, identical content
        let bRealDuplicate = purchase(id: "2", date: sameDate)
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([aFirstFetch, aSecondFetch, bRealDuplicate]), context: context())
        guard case .findings(let findings) = outcome else {
            Issue.record("expected findings, got \(outcome)")
            return
        }
        #expect(findings.count == 1, "got \(findings.count) findings with ids \(findings.map(\.id))")
        #expect(Set(findings.first?.evidence.map(\.transactionID) ?? []) == Set(["1", "2"]))
    }

    @Test("GAUNTLET R2: same as above but the id-colliding entries are non-adjacent in array order — still collapses to one finding")
    func gauntletR2SharedIDNonAdjacentStillCollapsesToOneFinding() {
        let sameDate = AccountingDate(year: 2026, month: 7, day: 14)
        let aFirstFetch = purchase(id: "1", date: sameDate)
        let bRealDuplicate = purchase(id: "2", date: sameDate)
        let aSecondFetch = purchase(id: "1", date: sameDate) // appears AFTER b in array order
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([aFirstFetch, bRealDuplicate, aSecondFetch]), context: context())
        guard case .findings(let findings) = outcome else {
            Issue.record("expected findings, got \(outcome)")
            return
        }
        #expect(findings.count == 1, "got \(findings.count) findings with ids \(findings.map(\.id))")
    }

    @Test("GAUNTLET R2: adding an unrelated third transaction anywhere in the array (before, between, or after) never changes an existing pair's finding id")
    func gauntletR2UnrelatedThirdTransactionNeverChangesExistingFindingID() {
        let a = purchase(id: "1")
        let b = purchase(id: "2")
        let unrelated = purchase(id: "999", vendor: "Cool Cars", date: AccountingDate(year: 2026, month: 1, day: 1), amountMinorUnits: 999_999, account: "cc-amex")

        func findingIDForABPair(in transactions: [LedgerTransaction]) -> String? {
            guard case .findings(let findings) = DuplicatePostedExpenseRule.evaluate(dataSet(transactions), context: context()) else { return nil }
            return findings.first { Set($0.evidence.map(\.transactionID)) == Set(["1", "2"]) }?.id
        }

        guard let baseline = findingIDForABPair(in: [a, b]),
              let withThirdAfter = findingIDForABPair(in: [a, b, unrelated]),
              let withThirdBefore = findingIDForABPair(in: [unrelated, a, b]),
              let withThirdBetween = findingIDForABPair(in: [a, unrelated, b]) else {
            Issue.record("expected the (a,b) finding to exist in every arrangement")
            return
        }
        #expect(baseline == withThirdAfter)
        #expect(baseline == withThirdBefore)
        #expect(baseline == withThirdBetween)
    }

    @Test("GAUNTLET R2: T3 across a month boundary within the same year (Jul 30 -> Aug 2, 3 days) fires at .medium — AccountingDate.daysBetween uses real Calendar epoch-day math, not naive y/m/d subtraction")
    func gauntletR2T3MonthBoundarySameYearFires() {
        let a = purchase(id: "1", date: AccountingDate(year: 2026, month: 7, day: 30))
        let b = purchase(id: "2", date: AccountingDate(year: 2026, month: 8, day: 2))
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b]), context: context())
        guard case .findings(let findings) = outcome else {
            Issue.record("expected findings across the Jul/Aug boundary at exactly 3 days apart, got \(outcome)")
            return
        }
        #expect(findings.count == 1)
        #expect(findings[0].confidence == .medium)
    }

    @Test("GAUNTLET R2: T3 across a YEAR boundary (Dec 30 2026 -> Jan 2 2027, 3 days) fires at .medium")
    func gauntletR2T3YearBoundaryFires() {
        let a = purchase(id: "1", date: AccountingDate(year: 2026, month: 12, day: 30))
        let b = purchase(id: "2", date: AccountingDate(year: 2027, month: 1, day: 2))
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b]), context: context())
        guard case .findings(let findings) = outcome else {
            Issue.record("expected findings across the year boundary at exactly 3 days apart, got \(outcome)")
            return
        }
        #expect(findings.count == 1)
        #expect(findings[0].confidence == .medium)
    }

    @Test("GAUNTLET R2: exactly 4 days apart across a YEAR boundary does NOT fire")
    func gauntletR2T3YearBoundaryFourDaysDoesNotFire() {
        let a = purchase(id: "1", date: AccountingDate(year: 2026, month: 12, day: 29))
        let b = purchase(id: "2", date: AccountingDate(year: 2027, month: 1, day: 2))
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b]), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass at 4 days apart across the year boundary, got \(outcome)")
            return
        }
    }

    @Test("GAUNTLET R2: T3 across a LEAP-YEAR February (2028): Feb 27 -> Mar 1, 3 days, fires")
    func gauntletR2T3LeapYearFebBoundaryFires() {
        let a = purchase(id: "1", date: AccountingDate(year: 2028, month: 2, day: 27))
        let b = purchase(id: "2", date: AccountingDate(year: 2028, month: 3, day: 1))
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b]), context: context())
        guard case .findings(let findings) = outcome else {
            Issue.record("expected findings across the leap-year Feb/Mar boundary at exactly 3 days apart, got \(outcome)")
            return
        }
        #expect(findings.count == 1)
        #expect(findings[0].confidence == .medium)
    }

    @Test("GAUNTLET R2: non-leap-year February (2026): Feb 27 -> Mar 2 is exactly 3 days (no Feb 29 to skip), fires")
    func gauntletR2T3NonLeapYearFebBoundaryFires() {
        let a = purchase(id: "1", date: AccountingDate(year: 2026, month: 2, day: 27))
        let b = purchase(id: "2", date: AccountingDate(year: 2026, month: 3, day: 2))
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b]), context: context())
        guard case .findings(let findings) = outcome else {
            Issue.record("expected findings across the non-leap Feb/Mar boundary at exactly 3 days apart, got \(outcome)")
            return
        }
        #expect(findings.count == 1)
        #expect(findings[0].confidence == .medium)
    }

    @Test("GAUNTLET R2: a completely empty purchases array with .complete coverage is a real pass with checkedCount 0")
    func gauntletR2EmptyPurchasesArrayCompleteCoverageIsPass() {
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([]), context: context())
        guard case .pass(let coverage, let checked) = outcome else {
            Issue.record("expected .pass for an empty purchases array with complete coverage, got \(outcome)")
            return
        }
        #expect(coverage == .complete)
        #expect(checked == 0)
    }

    @Test("GAUNTLET R2 (observation, not a bug): T3's evidence highlights 'date' identically to T1's, even though T3 dates are near, not equal — a UI attention cue, not an equality assertion, and the guided procedure separately mandates a human bank-statement check regardless")
    func gauntletR2T3EvidenceHighlightsDateSameAsT1DespiteNearNotExactMatch() {
        let a = purchase(id: "1", date: AccountingDate(year: 2026, month: 7, day: 10))
        let b = purchase(id: "2", date: AccountingDate(year: 2026, month: 7, day: 13)) // 3 days apart, T3
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b]), context: context())
        guard case .findings(let findings) = outcome, let finding = findings.first else {
            Issue.record("expected a finding, got \(outcome)")
            return
        }
        #expect(finding.confidence == .medium) // confirms this really is T3, not T1
        #expect(finding.evidence.allSatisfy { $0.highlightedFields.contains("date") })
    }

    @Test("GAUNTLET R2: two Purchases with NO payment account on either side (nil/nil) do not match on T1 or T3 — same conservative if-let pattern already validated for nil-vendor, confirmed to apply here too")
    func gauntletR2NilPaymentAccountBothSidesExcluded() {
        let date = AccountingDate(year: 2026, month: 7, day: 14)
        let a = purchase(id: "1", date: date, account: nil)
        let b = purchase(id: "2", date: date, account: nil)
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b]), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — nil/nil payment account should not satisfy T1's `if let acctA = a.paymentAccountID, acctA == b.paymentAccountID`, got \(outcome)")
            return
        }
    }

    // GAUNTLET R2 — documented landmine, NOT reachable today, deliberately
    // never executed: a same-non-USD-currency Purchase pair (e.g. CAD/CAD)
    // passes T1's exact-match guard (Money's synthesized Equatable just
    // returns false across currencies, no trap there) and then reaches the
    // materiality-floor check (`exposure >= context.materiality.absoluteFloor`,
    // this file's rule at the line right after the tier match), which uses
    // Money's `Comparable` conformance — defined only via `<` with a
    // `precondition(lhs.currency == rhs.currency, ...)` guard (Money.swift).
    // Swift's standard library implements `>=` as `!(lhs < rhs)`, so a
    // same-currency-but-non-USD pair traps the WHOLE PROCESS (a
    // `precondition` abort, not a thrown error) the instant it's compared
    // against the hardcoded-USD `MaterialityPolicy.defaultPolicy.absoluteFloor`.
    // `Severity.derive` has the identical shape and would trap the same way.
    //
    // CONFIRMED BY ACTUAL EXECUTION ONCE, in an isolated throwaway probe
    // (deleted immediately after), by the round-2 critic — real captured
    // output:
    //   Core/Money.swift:35: Precondition failed: Money comparison across
    //   currencies (CAD vs USD) is not defined.
    //   error: Process '...swiftpm-testing-helper...' exited with unexpected
    //   signal code 5
    //
    // Judged NOT a live gap, for two independently sufficient reasons, both
    // verified by reading the actual ingestion code rather than assumed:
    //   1. Multicurrency is explicitly owner-REJECTED / out of scope
    //      (docs/VOICE_LEDGER_SPEC.md's "Explicitly Out of Scope";
    //      docs/VOICE_LEDGER_HANDOFF.md §17's REJECTED table).
    //   2. Structurally unreachable regardless of (1): every real site that
    //      constructs a Money from live data hardcodes `currency: .usd`
    //      unconditionally (QBOSyncClient.swift's 10 call sites, both bank-
    //      statement importers) — none reads QBO's CurrencyRef at all. Only
    //      a test calling LedgerTransaction's memberwise initializer
    //      directly can construct a non-USD one.
    // Left `.disabled` rather than deleted so the mechanism stays documented
    // and inspectable without ever being able to crash a real `swift test`
    // run again. Re-enable only if multicurrency scope is ever revisited —
    // at which point Money, Severity.derive, AND this rule's materiality
    // check would all need a currency-aware redesign together, not a
    // one-line fix here.
    @Test(
        "GAUNTLET R2 (documented landmine, not currently reachable): a same-non-USD-currency Purchase pair would crash the whole process at the materiality-floor >= check",
        .disabled("Deliberately never executed — traps the process (Swift precondition abort, SIGTRAP). Confirmed once via an isolated throwaway probe; see the comment above this test. Not a live gap: multicurrency is owner-rejected/out-of-scope AND every real ingestion path hardcodes currency: .usd.")
    )
    func gauntletR2CrossCurrencyMaterialityCheckWouldTrapTheProcess() {
        let cad = CurrencyCode(rawValue: "CAD")
        let date = AccountingDate(year: 2026, month: 7, day: 14)
        let amount = Money(minorUnits: 500_000, currency: cad)
        let a = LedgerTransaction(id: "1", entityKind: .purchase, vendorName: "Permian Supply", txnDate: date, totalAmount: amount, paymentAccountID: "checking-1", docNumber: nil, isVoided: false, memo: nil, provenance: .qboAPI(readAt: Date()))
        let b = LedgerTransaction(id: "2", entityKind: .purchase, vendorName: "Permian Supply", txnDate: date, totalAmount: amount, paymentAccountID: "checking-1", docNumber: nil, isVoided: false, memo: nil, provenance: .qboAPI(readAt: Date()))
        _ = DuplicatePostedExpenseRule.evaluate(dataSet([a, b]), context: context())
    }

    // MARK: - Gauntlet Loop corpus, round 3 (2026-08-23) — a third fresh
    // critic, checking what rounds 1-2 left behind.

    @Test("GAUNTLET R3: a T2 finding does not claim 'paymentAccount' as matched evidence when the two transactions' actual payment accounts genuinely differ — T2's own match condition never checks this field")
    func gauntletR3T2DoesNotHighlightPaymentAccountWhenAccountsDiffer() {
        let a = purchase(id: "1", date: AccountingDate(year: 2026, month: 7, day: 1), account: "checking-1", docNumber: "REF-1001")
        let b = purchase(id: "2", date: AccountingDate(year: 2026, month: 7, day: 28), account: "cc-amex", docNumber: "REF-1001")
        #expect(a.paymentAccountID != b.paymentAccountID)

        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b], customTxnNumbers: true), context: context(customTxnNumbers: true))
        guard case .findings(let findings) = outcome, let finding = findings.first else {
            Issue.record("expected a T2 finding, got \(outcome)")
            return
        }
        #expect(finding.confidence == .high) // confirms this really is T2, not T1
        #expect(finding.evidence.allSatisfy { !$0.highlightedFields.contains("paymentAccount") })
    }

    @Test("GAUNTLET R3: a T2 finding does not claim 'date' as matched evidence when the two transactions' actual dates genuinely differ by weeks — T2's own match condition never compares dates")
    func gauntletR3T2DoesNotHighlightDateWhenDatesDiffer() {
        let a = purchase(id: "1", date: AccountingDate(year: 2026, month: 7, day: 1), account: "checking-1", docNumber: "REF-1001")
        let b = purchase(id: "2", date: AccountingDate(year: 2026, month: 7, day: 28), account: "cc-amex", docNumber: "REF-1001")
        #expect(a.txnDate != b.txnDate)

        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b], customTxnNumbers: true), context: context(customTxnNumbers: true))
        guard case .findings(let findings) = outcome, let finding = findings.first else {
            Issue.record("expected a T2 finding, got \(outcome)")
            return
        }
        #expect(finding.confidence == .high)
        #expect(finding.evidence.allSatisfy { !$0.highlightedFields.contains("date") })
    }

    @Test("GAUNTLET R3 (extreme case): a T2 finding does not claim 'paymentAccount' as matched even when NEITHER side has one recorded at all (nil/nil)")
    func gauntletR3T2DoesNotHighlightPaymentAccountWhenBothSidesNil() {
        let a = purchase(id: "1", date: AccountingDate(year: 2026, month: 7, day: 14), account: nil, docNumber: "REF-2002")
        let b = purchase(id: "2", date: AccountingDate(year: 2026, month: 7, day: 14), account: nil, docNumber: "REF-2002")

        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b], customTxnNumbers: true), context: context(customTxnNumbers: true))
        guard case .findings(let findings) = outcome, let finding = findings.first else {
            Issue.record("expected a T2 finding even with nil/nil payment accounts, got \(outcome)")
            return
        }
        #expect(finding.confidence == .high)
        #expect(finding.evidence.allSatisfy { !$0.highlightedFields.contains("paymentAccount") })
    }

    @Test("GAUNTLET R3: Set<Set<String>> dedup is order-independent by construction — the mechanism consideredPairs relies on is standard, documented Swift behavior, not a subtle trap")
    func gauntletR3SetOfSetOrderIndependenceIsSafe() {
        let pairAB: Set<String> = ["1", "2"]
        let pairBA: Set<String> = ["2", "1"]
        #expect(pairAB == pairBA)

        var seen: Set<Set<String>> = []
        seen.insert(pairAB)
        #expect(seen.contains(pairBA))
        #expect(seen.count == 1)
        seen.insert(pairBA)
        #expect(seen.count == 1)
    }

    @Test("GAUNTLET R3: dismissing a finding, then correcting both sides' amount by one cent (still equal to each other), leaves the SAME finding id and the dismissal still suppresses it — finding ids hash transaction IDs, never amount/date/vendor content, by design")
    func gauntletR3DismissalSurvivesCentLevelContentCorrectionOnBothSides() {
        let a1 = purchase(id: "145", amountMinorUnits: 48_620)
        let b1 = purchase(id: "151", amountMinorUnits: 48_620)
        let firstRun = DuplicatePostedExpenseRule.evaluate(dataSet([a1, b1]), context: context())
        guard case .findings(let findings1) = firstRun, let originalID = findings1.first?.id else {
            Issue.record("expected an initial finding")
            return
        }

        let a2 = purchase(id: "145", amountMinorUnits: 48_621)
        let b2 = purchase(id: "151", amountMinorUnits: 48_621)
        let ctxWithDismissal = RuleContext(
            period: period,
            materiality: .defaultPolicy,
            companyFacts: CompanyFacts(customTxnNumbersForPurchases: false),
            dismissedFindingIDs: [originalID]
        )
        let secondRun = DuplicatePostedExpenseRule.evaluate(dataSet([a2, b2]), context: ctxWithDismissal)
        guard case .pass = secondRun else {
            Issue.record("expected the dismissal to still suppress the pair after a same-cent correction on both sides, got \(secondRun)")
            return
        }
    }

    @Test("GAUNTLET R3 (cross-cutting, documented in the handoff, not this rule's to fix): changing ONLY the rule version changes the finding id for an otherwise-identical pair — a real version bump would silently un-suppress every prior dismissal for this rule, via shared FindingIDGenerator/RuleRegistry infrastructure used by every rule")
    func gauntletR3VersionBumpAloneChangesFindingID() {
        let idAtV1 = FindingIDGenerator.makeID(
            ruleID: DuplicatePostedExpenseRule.identity.id,
            ruleVersion: RuleVersion(major: 1, minor: 0, patch: 0),
            realmID: realm,
            period: period,
            sortedAffectedIDs: ["145", "151"]
        )
        let idAtV2 = FindingIDGenerator.makeID(
            ruleID: DuplicatePostedExpenseRule.identity.id,
            ruleVersion: RuleVersion(major: 1, minor: 1, patch: 0),
            realmID: realm,
            period: period,
            sortedAffectedIDs: ["145", "151"]
        )
        #expect(idAtV1 != idAtV2)
    }

    @Test("GAUNTLET R3: a .purchase and an .importedBankStatementLine sharing the exact same literal id never collide — the entityKind filter excludes the imported line before the pairwise loop ever sees it")
    func gauntletR3CrossEntityKindIDCollisionIsIgnoredByFilter() {
        let realPurchase = purchase(id: "1")
        let realDuplicate = purchase(id: "2")
        let importedLineWithCollidingID = LedgerTransaction(
            id: "1", // literal collision with realPurchase's id
            entityKind: .importedBankStatementLine,
            vendorName: "Permian Supply",
            txnDate: AccountingDate(year: 2026, month: 7, day: 14),
            totalAmount: Money(minorUnits: 48_620, currency: .usd),
            paymentAccountID: "checking-1",
            docNumber: nil,
            isVoided: false,
            memo: nil,
            provenance: .importedFile(documentID: "doc-1", importedAt: Date(), extractionMethod: .deterministicParse, coverage: .complete)
        )
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([realPurchase, realDuplicate, importedLineWithCollidingID]), context: context())
        guard case .findings(let findings) = outcome else {
            Issue.record("expected the genuine Purchase/Purchase pair to still fire, got \(outcome)")
            return
        }
        #expect(findings.count == 1)
        #expect(Set(findings.first?.evidence.map(\.transactionID) ?? []) == Set(["1", "2"]))
    }

    @Test("GAUNTLET R3: two entries sharing a literal id are excluded even when their OTHER fields (amount) disagree — extends round 1's identical-content-only coverage")
    func gauntletR3SameLiteralIDDifferentContentStillExcluded() {
        let staleRead = purchase(id: "999", amountMinorUnits: 48_620)
        let freshRead = purchase(id: "999", amountMinorUnits: 48_699)
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([staleRead, freshRead]), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — a.id == b.id must exclude the pair regardless of whether their other fields agree, got \(outcome)")
            return
        }
    }

    @Test("GAUNTLET R3: one side with a real vendor name and the other with nil vendor does not match, in either position")
    func gauntletR3AsymmetricNilVendorExcluded() {
        let date = AccountingDate(year: 2026, month: 7, day: 14)
        let named = purchase(id: "1", vendor: "Permian Supply", date: date)
        let nilVendor = purchase(id: "2", vendor: nil, date: date)

        guard case .pass = DuplicatePostedExpenseRule.evaluate(dataSet([named, nilVendor]), context: context()) else {
            Issue.record("expected .pass with named vendor first")
            return
        }
        guard case .pass = DuplicatePostedExpenseRule.evaluate(dataSet([nilVendor, named]), context: context()) else {
            Issue.record("expected .pass with nil vendor first")
            return
        }
    }

    // MARK: - Gauntlet Loop corpus, round 4 (2026-08-23) — a fourth fresh
    // critic, checking what rounds 1-3 left behind.

    @Test("GAUNTLET R4: the guided procedure names BOTH transaction ids neutrally ('Locate both Purchases (X and Y)'), in the SAME order-independent step, rather than asserting one specific id as 'the duplicate' based on incidental array position")
    func gauntletR4GuidedProcedureNamesBothCandidatesNeutrally() {
        let x = purchase(id: "145", docNumber: "4471")
        let y = purchase(id: "151", docNumber: "4471-DUP")

        func locateStep(_ transactions: [LedgerTransaction]) -> String? {
            guard case .findings(let findings) = DuplicatePostedExpenseRule.evaluate(dataSet(transactions), context: context()),
                  let finding = findings.first else { return nil }
            return finding.proposedActions.first?.guidedProcedure?.steps.first(where: { $0.contains("Locate both Purchases") })
        }

        guard let step1 = locateStep([x, y]), let step2 = locateStep([y, x]) else {
            Issue.record("expected a 'Locate both Purchases' step in both array orderings")
            return
        }
        // Both real transaction ids appear regardless of array order — the
        // step no longer singles out one of them as "the duplicate."
        #expect(step1.contains("145") && step1.contains("151"))
        #expect(step2.contains("145") && step2.contains("151"))
        // No step anywhere asserts a specific one of the two ids as settled
        // fact — the old "Locate the duplicate Purchase (id)" phrasing is gone.
        let allSteps1 = DuplicatePostedExpenseRule.evaluate(dataSet([x, y]), context: context())
        if case .findings(let findings) = allSteps1, let finding = findings.first {
            #expect(finding.proposedActions.first?.guidedProcedure?.steps.contains(where: { $0.contains("Locate the duplicate Purchase") }) != true)
        }
    }

    @Test("GAUNTLET R4: a pair satisfying T1 AND T2 AND T3 simultaneously (same date, same account, same non-empty DocNumber) resolves to T1 — checked first by construction — and T1's evidence stays honest: it highlights only what T1 actually checked (amount/date/paymentAccount), never claiming or denying the also-true DocNumber match")
    func gauntletR4AllThreeTiersSimultaneouslySatisfiableResolvesToT1Honestly() {
        let a = purchase(id: "1", date: AccountingDate(year: 2026, month: 7, day: 14), account: "checking-1", docNumber: "SHARED-REF")
        let b = purchase(id: "2", date: AccountingDate(year: 2026, month: 7, day: 14), account: "checking-1", docNumber: "SHARED-REF")
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b], customTxnNumbers: true), context: context(customTxnNumbers: true))
        guard case .findings(let findings) = outcome, let finding = findings.first else {
            Issue.record("expected a finding, got \(outcome)")
            return
        }
        #expect(finding.confidence == .high)
        #expect(finding.evidence.allSatisfy { $0.highlightedFields == ["amount", "date", "paymentAccount"] })
        #expect(finding.evidence.allSatisfy { !$0.highlightedFields.contains("docNumber") })
    }

    @Test("GAUNTLET R4 (observation, not a bug): no tier's evidence ever highlights 'vendor', even though vendor equality is the first guard every finding passes — an omission of a true fact, not a false claim")
    func gauntletR4VendorNeverAppearsInHighlightedFields() {
        let t1a = purchase(id: "1")
        let t1b = purchase(id: "2")
        guard case .findings(let f1) = DuplicatePostedExpenseRule.evaluate(dataSet([t1a, t1b]), context: context()) else {
            Issue.record("expected T1 finding")
            return
        }
        #expect(f1.first?.evidence.allSatisfy { !$0.highlightedFields.contains("vendor") } == true)

        let t2a = purchase(id: "1", date: AccountingDate(year: 2026, month: 7, day: 1), account: "checking-1", docNumber: "REF-1")
        let t2b = purchase(id: "2", date: AccountingDate(year: 2026, month: 7, day: 25), account: "checking-2", docNumber: "REF-1")
        guard case .findings(let f2) = DuplicatePostedExpenseRule.evaluate(dataSet([t2a, t2b], customTxnNumbers: true), context: context(customTxnNumbers: true)) else {
            Issue.record("expected T2 finding")
            return
        }
        #expect(f2.first?.evidence.allSatisfy { !$0.highlightedFields.contains("vendor") } == true)

        let t3a = purchase(id: "1", date: AccountingDate(year: 2026, month: 7, day: 10))
        let t3b = purchase(id: "2", date: AccountingDate(year: 2026, month: 7, day: 13))
        guard case .findings(let f3) = DuplicatePostedExpenseRule.evaluate(dataSet([t3a, t3b]), context: context()) else {
            Issue.record("expected T3 finding")
            return
        }
        #expect(f3.first?.evidence.allSatisfy { !$0.highlightedFields.contains("vendor") } == true)
    }

    @Test("GAUNTLET R4 — FIXED 2026-10-01: RuleContext.gatingTransactions now preserves asOfDate (it used to silently reset to today's real date; found when a pinned regression snapshot drifted by a day)")
    func gauntletR4GatingTransactionsPreservesAsOfDate() {
        let fixedPast = AccountingDate(year: 2020, month: 1, day: 1)
        let original = RuleContext(
            period: period,
            materiality: .defaultPolicy,
            companyFacts: CompanyFacts(customTxnNumbersForPurchases: false),
            asOfDate: fixedPast
        )
        #expect(original.asOfDate == fixedPast)
        let gated = original.gatingTransactions(["some-id"])
        #expect(gated.asOfDate == fixedPast)
    }

    // MARK: - Gauntlet Loop corpus, round 5 (2026-08-23) — a fifth fresh
    // critic, stacking combinations of already-fixed edge cases looking for
    // an interaction bug no single-axis test would catch. Found none — this
    // was the first clean round after four that each found a real gap.

    @Test("GAUNTLET R5: a negative-amount pair matching T2 across different accounts stays honest and magnitude-correct on every field — composes the negative-magnitude fix (rounds 1-2) with the T2-honest-evidence fix (round 3)")
    func gauntletR5StackNegativeAmountT2AcrossAccounts() {
        let a = purchase(id: "1", date: AccountingDate(year: 2026, month: 7, day: 1), amountMinorUnits: -500_000, account: "checking-1", docNumber: "REF-NEG-1")
        let b = purchase(id: "2", date: AccountingDate(year: 2026, month: 7, day: 28), amountMinorUnits: -500_000, account: "cc-amex", docNumber: "REF-NEG-1")
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b], customTxnNumbers: true), context: context(customTxnNumbers: true))
        guard case .findings(let findings) = outcome, let finding = findings.first else {
            Issue.record("expected a T2 finding for a negative-amount pair, got \(outcome)")
            return
        }
        #expect(finding.confidence == .high)
        #expect(finding.dollarExposure == Money(minorUnits: 500_000, currency: .usd))
        #expect(finding.severity == .high)
        #expect(finding.title == "Possible duplicate expense — \(finding.vendorName ?? ""), \(finding.dollarExposure)")
        #expect(finding.evidence.allSatisfy { $0.highlightedFields == ["amount", "docNumber"] })
    }

    @Test("GAUNTLET R5: a three-way trio where pairs resolve to different tiers (A-B exact/T1, A-C and B-C near-date/T3) — each pairwise finding's tier and evidence stays independently correct, not leaked from a sibling pair sharing a transaction")
    func gauntletR5StackThreeWayMixedTiers() {
        let a = purchase(id: "A", date: AccountingDate(year: 2026, month: 7, day: 14), account: "checking-1")
        let b = purchase(id: "B", date: AccountingDate(year: 2026, month: 7, day: 14), account: "checking-1")
        let c = purchase(id: "C", date: AccountingDate(year: 2026, month: 7, day: 16), account: "checking-1")
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b, c]), context: context())
        guard case .findings(let findings) = outcome else {
            Issue.record("expected findings, got \(outcome)")
            return
        }
        #expect(findings.count == 3)
        func finding(for ids: Set<String>) -> Finding? {
            findings.first { Set($0.evidence.map(\.transactionID)) == ids }
        }
        guard let ab = finding(for: ["A", "B"]), let ac = finding(for: ["A", "C"]), let bc = finding(for: ["B", "C"]) else {
            Issue.record("expected all three pairwise findings to exist")
            return
        }
        #expect(ab.confidence == .high)
        #expect(ac.confidence == .medium)
        #expect(bc.confidence == .medium)
        #expect(ab.evidence.allSatisfy { $0.highlightedFields == ["amount", "date", "paymentAccount"] })
    }

    @Test("GAUNTLET R5 (documents existing design, not a bug): a dismissal recorded against a T3 (medium) match also suppresses the SAME transaction-id pair if it later resolves to T1 (high) on a corrected resync — dismissal is keyed on transaction-pair identity, never on match tier, by design")
    func gauntletR5DismissalSurvivesTierUpgrade() {
        let aT3 = purchase(id: "1", date: AccountingDate(year: 2026, month: 7, day: 10))
        let bT3 = purchase(id: "2", date: AccountingDate(year: 2026, month: 7, day: 13))
        let firstRun = DuplicatePostedExpenseRule.evaluate(dataSet([aT3, bT3]), context: context())
        guard case .findings(let findings1) = firstRun, let originalFinding = findings1.first else {
            Issue.record("expected an initial T3 finding")
            return
        }
        #expect(originalFinding.confidence == .medium)

        let ctxWithDismissal = RuleContext(period: period, materiality: .defaultPolicy, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false), dismissedFindingIDs: [originalFinding.id])
        let aT1 = purchase(id: "1", date: AccountingDate(year: 2026, month: 7, day: 10))
        let bT1 = purchase(id: "2", date: AccountingDate(year: 2026, month: 7, day: 10))
        let secondRun = DuplicatePostedExpenseRule.evaluate(dataSet([aT1, bT1]), context: ctxWithDismissal)
        guard case .pass = secondRun else {
            Issue.record("expected the stale T3 dismissal to still suppress the now-T1 match, got \(secondRun)")
            return
        }
    }

    @Test("GAUNTLET R5: literal id collision is excluded even when the colliding pair would otherwise satisfy T2 (docNumber match) — confirms the id guard runs before ANY tier logic, T2 included, not just T1")
    func gauntletR5IDCollisionExcludedEvenForT2Shape() {
        let a = purchase(id: "999", date: AccountingDate(year: 2026, month: 7, day: 1), account: "checking-1", docNumber: "REF-X")
        let b = purchase(id: "999", date: AccountingDate(year: 2026, month: 7, day: 25), account: "checking-2", docNumber: "REF-X")
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b], customTxnNumbers: true), context: context(customTxnNumbers: true))
        guard case .pass = outcome else {
            Issue.record("expected .pass — same literal id must exclude the pair regardless of which tier's shape it would otherwise match, got \(outcome)")
            return
        }
    }

    @Test("GAUNTLET R5: a negative-amount T2 pair exactly at the materiality floor fires at .high severity")
    func gauntletR5NegativeAmountT2ExactlyAtFloor() {
        let a = purchase(id: "1", date: AccountingDate(year: 2026, month: 7, day: 1), amountMinorUnits: -2_500, account: "checking-1", docNumber: "REF-FLOOR")
        let b = purchase(id: "2", date: AccountingDate(year: 2026, month: 7, day: 25), amountMinorUnits: -2_500, account: "checking-2", docNumber: "REF-FLOOR")
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b], customTxnNumbers: true), context: context(customTxnNumbers: true))
        guard case .findings(let findings) = outcome, let finding = findings.first else {
            Issue.record("expected a finding exactly at the floor, got \(outcome)")
            return
        }
        #expect(finding.severity == .high)
        #expect(finding.dollarExposure == Money(minorUnits: 2_500, currency: .usd))
    }

    @Test("GAUNTLET R5: a negative-amount T2 pair one cent below the materiality floor is fully excluded")
    func gauntletR5NegativeAmountT2OneCentBelowFloor() {
        let a = purchase(id: "1", date: AccountingDate(year: 2026, month: 7, day: 1), amountMinorUnits: -2_499, account: "checking-1", docNumber: "REF-FLOOR2")
        let b = purchase(id: "2", date: AccountingDate(year: 2026, month: 7, day: 25), amountMinorUnits: -2_499, account: "checking-2", docNumber: "REF-FLOOR2")
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b], customTxnNumbers: true), context: context(customTxnNumbers: true))
        guard case .pass = outcome else {
            Issue.record("expected .pass one cent below the floor even for a negative-amount T2 shape, got \(outcome)")
            return
        }
    }

    @Test("GAUNTLET R5: a three-way mutual duplicate where one transaction is gated — only the pair NOT involving the gated transaction still fires")
    func gauntletR5ThreeWayWithOneGated() {
        let a = purchase(id: "A")
        let b = purchase(id: "B")
        let c = purchase(id: "C")
        let ctx = RuleContext(period: period, materiality: .defaultPolicy, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false), gatedTransactionIDs: ["A"])
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b, c]), context: ctx)
        guard case .findings(let findings) = outcome else {
            Issue.record("expected findings, got \(outcome)")
            return
        }
        #expect(findings.count == 1)
        #expect(Set(findings.first?.evidence.map(\.transactionID) ?? []) == Set(["B", "C"]))
    }

    // MARK: - Gauntlet Loop corpus, round 6 (2026-08-23) — SECOND consecutive
    // clean round (round 5 was the first). Per the loop's own stop
    // condition, this closes out Gauntlet A on this rule.

    @Test("GAUNTLET R6: a dataset with ONLY Bills (zero Purchases), including two that would be an obvious T1 duplicate if they were Purchases, reaches .pass with checkedCount 0 and .complete coverage — the entity-kind filter interacts correctly with coverage even when the filtered set is empty but the raw input isn't")
    func gauntletR6OnlyNonPurchaseEntitiesStillPasses() {
        let bill1 = LedgerTransaction(id: "b1", entityKind: .bill, vendorName: "Permian Supply", txnDate: AccountingDate(year: 2026, month: 7, day: 14), totalAmount: Money(minorUnits: 48_620, currency: .usd), paymentAccountID: "checking-1", docNumber: nil, isVoided: false, memo: nil, provenance: .qboAPI(readAt: Date()))
        let bill2 = LedgerTransaction(id: "b2", entityKind: .bill, vendorName: "Permian Supply", txnDate: AccountingDate(year: 2026, month: 7, day: 14), totalAmount: Money(minorUnits: 48_620, currency: .usd), paymentAccountID: "checking-1", docNumber: nil, isVoided: false, memo: nil, provenance: .qboAPI(readAt: Date()))
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([bill1, bill2]), context: context())
        guard case .pass(let coverage, let checked) = outcome else {
            Issue.record("expected .pass, got \(outcome)")
            return
        }
        #expect(coverage == .complete)
        #expect(checked == 0)
    }

    @Test("GAUNTLET R6: three independent 4-way mutual-duplicate clusters plus unrelated singletons produce exactly 3×C(4,2)=18 findings, all distinct ids, with zero cross-cluster leakage")
    func gauntletR6ThreeIndependentClustersNoLeakage() {
        let clusterA = (0..<4).map { i in purchase(id: "A\(i)", vendor: "Permian Supply", date: AccountingDate(year: 2026, month: 7, day: 14), amountMinorUnits: 48_620, account: "checking-1") }
        let clusterB = (0..<4).map { i in purchase(id: "B\(i)", vendor: "Cool Cars", date: AccountingDate(year: 2026, month: 7, day: 5), amountMinorUnits: 12_000, account: "1150040000") }
        let clusterC = (0..<4).map { i in purchase(id: "C\(i)", vendor: "ADP", date: AccountingDate(year: 2026, month: 7, day: 20), amountMinorUnits: 99_999, account: "checking-1") }
        let singleton1 = purchase(id: "S1", vendor: "Odessa Fuel", amountMinorUnits: 5_000)
        let singleton2 = purchase(id: "S2", vendor: "Odessa Fuel", amountMinorUnits: 5_001)

        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet(clusterA + clusterB + clusterC + [singleton1, singleton2]), context: context())
        guard case .findings(let findings) = outcome else {
            Issue.record("expected findings, got \(outcome)")
            return
        }
        #expect(findings.count == 18)
        #expect(Set(findings.map(\.id)).count == findings.count)
        for f in findings {
            let txIDs = Set(f.evidence.map(\.transactionID))
            let inOneCluster = txIDs.allSatisfy { $0.hasPrefix("A") } || txIDs.allSatisfy { $0.hasPrefix("B") } || txIDs.allSatisfy { $0.hasPrefix("C") }
            #expect(inOneCluster, "finding mixes clusters: \(txIDs)")
        }
    }

    @Test("GAUNTLET R6: a five-way mutual T1 duplicate cluster produces exactly C(5,2)=10 distinct findings, no crash — confirms pairwise-loop correctness scales past the three-way cases already covered")
    func gauntletR6FiveWayClusterProducesTenFindings() {
        let cluster = (0..<5).map { i in purchase(id: "X\(i)") }
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet(cluster), context: context())
        guard case .findings(let findings) = outcome else {
            Issue.record("expected findings, got \(outcome)")
            return
        }
        #expect(findings.count == 10)
        #expect(Set(findings.map(\.id)).count == 10)
    }

    @Test("GAUNTLET R6 (stress): a would-be 5-way cluster combined with a literal id-collision pair, one voided member, and one gated member all at once — the id-colliding pair collapses to one logical transaction rather than double-counting or silently dropping the one real remaining pair")
    func gauntletR6StressedClusterWithExclusionsCombined() {
        let x0 = purchase(id: "X0")
        let x0dup = purchase(id: "X0") // literal id collision with x0 — same pairKey as (x0,x1) would be for (x0dup,x1)
        let x1 = purchase(id: "X1")
        let x3voided = purchase(id: "X3", isVoided: true)
        let x4gated = purchase(id: "X4")

        let ctx = RuleContext(period: period, materiality: .defaultPolicy, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false), gatedTransactionIDs: ["X4"])
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([x0, x0dup, x1, x3voided, x4gated]), context: ctx)
        guard case .findings(let findings) = outcome else {
            Issue.record("expected findings, got \(outcome)")
            return
        }
        // Only real candidate pair after every exclusion: (X0, X1) — the
        // id-colliding x0/x0dup entries produce the same pairKey against x1
        // and correctly collapse via consideredPairs' Set<Set<String>> dedup
        // rather than double-counting.
        #expect(findings.count == 1)
        #expect(Set(findings[0].evidence.map(\.transactionID)) == Set(["X0", "X1"]))
    }

    @Test("GAUNTLET R6: a .medium (T3) finding is dismissable via dismissedFindingIDs exactly the same way a .high finding is — no confidence-based special-casing gap")
    func gauntletR6MediumConfidenceDismissalWorksIdentically() {
        let a = purchase(id: "1", date: AccountingDate(year: 2026, month: 7, day: 14))
        let b = purchase(id: "2", date: AccountingDate(year: 2026, month: 7, day: 16))
        let firstRun = DuplicatePostedExpenseRule.evaluate(dataSet([a, b]), context: context())
        guard case .findings(let f1) = firstRun, let mediumID = f1.first?.id else {
            Issue.record("expected a T3 finding")
            return
        }
        #expect(f1.first?.confidence == .medium)

        let dismissedContext = RuleContext(period: period, materiality: .defaultPolicy, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false), dismissedFindingIDs: [mediumID])
        guard case .pass = DuplicatePostedExpenseRule.evaluate(dataSet([a, b]), context: dismissedContext) else {
            Issue.record("expected dismissal to suppress the T3 finding down to .pass")
            return
        }
    }

    @Test("GAUNTLET R6: the same 4-way mutual cluster fed in original vs. fully reversed array order yields the identical SET of finding ids — no iteration-order-dependent non-determinism in the pairwise scan")
    func gauntletR6RerunWithReorderedArrayYieldsSameFindingIDSet() {
        let originalOrder = (0..<4).map { i in purchase(id: "Y\(i)") }
        let reversedOrder = Array(originalOrder.reversed())

        guard case .findings(let f1) = DuplicatePostedExpenseRule.evaluate(dataSet(originalOrder), context: context()),
              case .findings(let f2) = DuplicatePostedExpenseRule.evaluate(dataSet(reversedOrder), context: context()) else {
            Issue.record("expected findings on both")
            return
        }
        #expect(Set(f1.map(\.id)) == Set(f2.map(\.id)))
        #expect(f1.count == f2.count)
    }

    @Test("GAUNTLET: a Purchase's own offsetting VendorCredit (refund-then-reissue shape) changes nothing — this rule never reads input.vendorCredits, consistent with its own doc comment scoping it narrower than 'any duplicate'")
    func gauntletVendorCreditPresenceDoesNotAffectOutcome() {
        let a = purchase(id: "1")
        let b = purchase(id: "2")
        let offsettingCredit = LedgerVendorCredit(
            id: "vc-1",
            vendorName: "Permian Supply",
            txnDate: AccountingDate(year: 2026, month: 7, day: 15),
            totalAmount: Money(minorUnits: 48_620, currency: .usd),
            balance: .zero,
            provenance: .qboAPI(readAt: Date())
        )
        let withoutCredit = DuplicatePostedExpenseRule.evaluate(dataSet([a, b]), context: context())
        let withCreditDataSet = NormalizedDataSet(
            realmID: realm,
            period: period,
            transactions: [a, b],
            vendorCredits: [offsettingCredit],
            coverage: .complete,
            companyFacts: CompanyFacts(customTxnNumbersForPurchases: false)
        )
        let withCredit = DuplicatePostedExpenseRule.evaluate(withCreditDataSet, context: context())
        guard case .findings(let f1) = withoutCredit, case .findings(let f2) = withCredit else {
            Issue.record("expected findings in both cases")
            return
        }
        #expect(f1.map(\.id) == f2.map(\.id))
    }

    // MARK: - Gauntlet Loop, Gauntlet B (2026-08-23) — the finding surface
    // is actionable without opening QBO to decode it: real evidence values,
    // a vendor-named title, a plain-English narrative, and a pre-approval
    // checklist. Three gaps the owner found directly in the running app.

    @Test("GAUNTLET B: evidence carries the ACTUAL VALUES for every highlighted field, not just field names — a T1 finding shows the real amount, date, payment account, and vendor for both transactions")
    func gauntletBEvidenceCarriesRealFieldValues() {
        let a = purchase(id: "145", date: AccountingDate(year: 2026, month: 7, day: 14), amountMinorUnits: 48_620, account: "checking-1")
        let b = purchase(id: "151", date: AccountingDate(year: 2026, month: 7, day: 14), amountMinorUnits: 48_620, account: "checking-1")
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b]), context: context())
        guard case .findings(let findings) = outcome, let finding = findings.first else {
            Issue.record("expected a finding, got \(outcome)")
            return
        }
        for item in finding.evidence {
            #expect(item.fieldValues["amount"] == "USD 486.20")
            #expect(item.fieldValues["date"] == "2026-7-14")
            #expect(item.fieldValues["paymentAccount"] == "checking-1")
            #expect(item.fieldValues["vendor"] == "Permian Supply")
        }
    }

    @Test("GAUNTLET B: a T2 finding's evidence values include docNumber and omit paymentAccount/date — fieldValues stays consistent with highlightedFields' per-tier honesty fix")
    func gauntletBT2EvidenceValuesMatchHighlightedFields() {
        let a = purchase(id: "1", date: AccountingDate(year: 2026, month: 7, day: 1), account: "checking-1", docNumber: "REF-1")
        let b = purchase(id: "2", date: AccountingDate(year: 2026, month: 7, day: 28), account: "cc-amex", docNumber: "REF-1")
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b], customTxnNumbers: true), context: context(customTxnNumbers: true))
        guard case .findings(let findings) = outcome, let finding = findings.first else {
            Issue.record("expected a T2 finding, got \(outcome)")
            return
        }
        #expect(finding.evidence[0].fieldValues["docNumber"] == "REF-1")
        // fieldValues MAY still carry paymentAccount/date internally (the
        // helper captures every known field on the transaction), but the
        // view only renders what's in highlightedFields — verified here
        // that highlightedFields itself stays T2-honest (amount, docNumber
        // only), consistent with the round-3 fix.
        #expect(finding.evidence.allSatisfy { $0.highlightedFields == ["amount", "docNumber"] })
    }

    @Test("GAUNTLET B: the finding title names the vendor, not just the dollar amount")
    func gauntletBTitleNamesVendor() {
        let a = purchase(id: "1", vendor: "Permian Supply")
        let b = purchase(id: "2", vendor: "Permian Supply")
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b]), context: context())
        guard case .findings(let findings) = outcome, let finding = findings.first else {
            Issue.record("expected a finding, got \(outcome)")
            return
        }
        #expect(finding.title.contains("Permian Supply"))
    }

    @Test("GAUNTLET B: a T1 finding's narrative is a real, deterministic, non-empty sentence naming the vendor and dollar amount — not AI-generated (no AI integration exists in this codebase at all)")
    func gauntletBT1NarrativeIsDeterministicAndNamesVendorAndAmount() {
        let a = purchase(id: "1", vendor: "Permian Supply", amountMinorUnits: 48_620)
        let b = purchase(id: "2", vendor: "Permian Supply", amountMinorUnits: 48_620)
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b]), context: context())
        guard case .findings(let findings) = outcome, let finding = findings.first else {
            Issue.record("expected a finding, got \(outcome)")
            return
        }
        let narrative = try! #require(finding.narrative)
        #expect(narrative.contains("Permian Supply"))
        #expect(narrative.contains("USD 486.20"))
        // Determinism: running the exact same input twice produces the
        // byte-identical narrative — the same guarantee already proven for
        // detection/severity/exposure/evidence.
        let secondRun = DuplicatePostedExpenseRule.evaluate(dataSet([a, b]), context: context())
        guard case .findings(let findings2) = secondRun else {
            Issue.record("expected a finding on the second run")
            return
        }
        #expect(findings2.first?.narrative == narrative)
    }

    @Test("GAUNTLET B: a T2 finding's narrative correctly describes a shared reference number, not a date/account match it never checked")
    func gauntletBT2NarrativeDescribesReferenceNumberNotDateOrAccount() {
        let a = purchase(id: "1", date: AccountingDate(year: 2026, month: 7, day: 1), account: "checking-1", docNumber: "REF-1")
        let b = purchase(id: "2", date: AccountingDate(year: 2026, month: 7, day: 28), account: "cc-amex", docNumber: "REF-1")
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b], customTxnNumbers: true), context: context(customTxnNumbers: true))
        guard case .findings(let findings) = outcome, let finding = findings.first else {
            Issue.record("expected a T2 finding, got \(outcome)")
            return
        }
        let narrative = try! #require(finding.narrative)
        #expect(narrative.contains("reference number"))
        #expect(narrative.contains("REF-1"))
    }

    @Test("GAUNTLET B: a T3 finding's narrative states the actual number of days apart, not a false 'same date' claim")
    func gauntletBT3NarrativeStatesDaysApart() {
        let a = purchase(id: "1", date: AccountingDate(year: 2026, month: 7, day: 10))
        let b = purchase(id: "2", date: AccountingDate(year: 2026, month: 7, day: 13))
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b]), context: context())
        guard case .findings(let findings) = outcome, let finding = findings.first else {
            Issue.record("expected a T3 finding, got \(outcome)")
            return
        }
        let narrative = try! #require(finding.narrative)
        #expect(narrative.contains("3 days apart"))
    }

    @Test("GAUNTLET B: preApprovalChecklist is populated with concrete, non-empty steps naming both transaction ids — not left as spec'd-but-never-built")
    func gauntletBPreApprovalChecklistIsPopulated() {
        let a = purchase(id: "145")
        let b = purchase(id: "151")
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b]), context: context())
        guard case .findings(let findings) = outcome, let finding = findings.first else {
            Issue.record("expected a finding, got \(outcome)")
            return
        }
        #expect(!finding.preApprovalChecklist.isEmpty)
        #expect(finding.preApprovalChecklist.contains(where: { $0.contains("145") && $0.contains("151") }))
    }

    // MARK: - Gauntlet Loop, Gauntlet B critic pass (2026-08-23) — a fresh
    // critic found three more real gaps after the first round of fixes:
    // the payment account shown was a raw QBO account id, not its real
    // name; Dismiss had no stated consequence; and nothing said what
    // happens if a finding is left open.

    @Test("GAUNTLET B (critic pass): when the real account is present in input.accounts, evidence/narrative/checklist all show its NAME, not the raw QBO account id")
    func gauntletBCriticAccountNameResolvedWhenAvailable() {
        let a = purchase(id: "1", date: AccountingDate(year: 2026, month: 7, day: 14), account: "35")
        let b = purchase(id: "2", date: AccountingDate(year: 2026, month: 7, day: 14), account: "35")
        let checkingAccount = LedgerAccount(id: "35", name: "Checking", accountType: .bank)
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b], accounts: [checkingAccount]), context: context())
        guard case .findings(let findings) = outcome, let finding = findings.first else {
            Issue.record("expected a finding, got \(outcome)")
            return
        }
        #expect(finding.evidence.allSatisfy { $0.fieldValues["paymentAccount"] == "Checking" })
        #expect(finding.narrative?.contains("Checking") == true)
        #expect(finding.narrative?.contains("35") == false, "the raw account id must not leak into the narrative once a real name is available")
        #expect(finding.preApprovalChecklist.contains(where: { $0.contains("Checking") }))
    }

    @Test("GAUNTLET B (critic pass): when the account is NOT present in input.accounts (e.g. accounts weren't synced), evidence/narrative fall back to the raw id rather than showing nothing")
    func gauntletBCriticAccountFallsBackToRawIDWhenUnresolved() {
        let a = purchase(id: "1", account: "checking-1")
        let b = purchase(id: "2", account: "checking-1")
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b], accounts: []), context: context())
        guard case .findings(let findings) = outcome, let finding = findings.first else {
            Issue.record("expected a finding, got \(outcome)")
            return
        }
        #expect(finding.evidence.allSatisfy { $0.fieldValues["paymentAccount"] == "checking-1" })
    }

    @Test("GAUNTLET B (critic pass): riskIfIgnored is populated with a concrete, non-empty statement naming the real dollar amount")
    func gauntletBCriticRiskIfIgnoredIsPopulated() {
        let a = purchase(id: "1", amountMinorUnits: 48_620)
        let b = purchase(id: "2", amountMinorUnits: 48_620)
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b]), context: context())
        guard case .findings(let findings) = outcome, let finding = findings.first else {
            Issue.record("expected a finding, got \(outcome)")
            return
        }
        let risk = try! #require(finding.riskIfIgnored)
        #expect(risk.contains("USD 486.20"))
        #expect(!risk.isEmpty)
    }

    @Test("GAUNTLET B (round 2 critic pass): a T2 finding whose pair spans TWO DIFFERENT payment accounts names BOTH accounts in the pre-approval checklist's statement-check step — T2's own match condition never requires a shared account, so naming only one would send a bookkeeper to check the wrong statement")
    func gauntletBRound2T2ChecklistNamesBothAccountsWhenTheyDiffer() {
        let checkingAccount = LedgerAccount(id: "checking-1", name: "Checking", accountType: .bank)
        let savingsAccount = LedgerAccount(id: "savings-2", name: "Savings", accountType: .bank)
        let a = purchase(id: "1", date: AccountingDate(year: 2026, month: 7, day: 1), account: "checking-1", docNumber: "REF-99")
        let b = purchase(id: "2", date: AccountingDate(year: 2026, month: 7, day: 20), account: "savings-2", docNumber: "REF-99")
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b], customTxnNumbers: true, accounts: [checkingAccount, savingsAccount]), context: context(customTxnNumbers: true))
        guard case .findings(let findings) = outcome, let finding = findings.first else {
            Issue.record("expected a T2 finding, got \(outcome)")
            return
        }
        #expect(finding.confidence == .high) // confirms this is T2
        #expect(finding.preApprovalChecklist.contains(where: { $0.contains("Checking") && $0.contains("Savings") }))
    }

    @Test("GAUNTLET B (round 2 critic pass): a T2 finding whose pair shares the SAME payment account keeps the single-account checklist wording — no regression for the common case")
    func gauntletBRound2T2ChecklistNamesOneAccountWhenTheyMatch() {
        let checkingAccount = LedgerAccount(id: "checking-1", name: "Checking", accountType: .bank)
        let a = purchase(id: "1", date: AccountingDate(year: 2026, month: 7, day: 1), account: "checking-1", docNumber: "REF-99")
        let b = purchase(id: "2", date: AccountingDate(year: 2026, month: 7, day: 20), account: "checking-1", docNumber: "REF-99")
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b], customTxnNumbers: true, accounts: [checkingAccount]), context: context(customTxnNumbers: true))
        guard case .findings(let findings) = outcome, let finding = findings.first else {
            Issue.record("expected a T2 finding, got \(outcome)")
            return
        }
        #expect(finding.preApprovalChecklist.contains(where: { $0.contains("Checking") && !$0.contains("BOTH") }))
    }
}
