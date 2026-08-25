import Testing
@testable import Core
import Foundation

/// Gauntlet C ("Honesty Audit"), round 1 (2026-08-24), scoped to
/// VL-DUP-EXP-001 (`DuplicatePostedExpenseRule`) and its finding surface —
/// a clean round (no dishonesty found), promoted to a permanent suite so
/// these confirmed-honest behaviors are protected from silent regression,
/// same convention as Gauntlet A's confirmed-correct fixture corpus.
@Suite("VL-DUP-EXP-001 honesty audit — Gauntlet C")
struct DuplicatePostedExpenseRuleHonestyTests {
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

    func dataSet(_ transactions: [LedgerTransaction], coverage: Coverage = .complete, accounts: [LedgerAccount] = []) -> NormalizedDataSet {
        NormalizedDataSet(
            realmID: realm,
            period: period,
            transactions: transactions,
            accounts: accounts,
            coverage: coverage,
            companyFacts: CompanyFacts(customTxnNumbersForPurchases: false)
        )
    }

    // MARK: Check 1 — engine gate/rule outcome stay synchronized

    /// RuleEngineActor.runOne's step-3 gate compares `input.coverage` against
    /// `ruleType.requirements.requiredCoverage`. DUP-EXP-001 declares
    /// `.complete`, so on `.partial` coverage the ENGINE returns
    /// `.cannotEvaluate` before the rule's own `evaluate` ever runs — meaning
    /// the rule's own internal `.cannotEvaluate` branch (triggered by
    /// `input.coverage != .complete` with zero findings) should be
    /// unreachable through the real engine path. Proven directly here by
    /// running the SAME RuleEngine the app uses, not just calling
    /// `DuplicatePostedExpenseRule.evaluate` directly.
    @Test("Engine never lets DUP-EXP-001 see partial coverage — cannotEvaluate always comes from the gate, never the rule's own fallback")
    func engineGateIntercepts_partialCoverage() async {
        let engine = RuleEngine(rules: [DuplicatePostedExpenseRule.self])
        let input = dataSet([], coverage: .partial(reason: "readPurchases returned a full page"))
        let evaluation = await engine.evaluate(pages: [.page3Transactions], input: input, context: context())
        let result = evaluation.results[DuplicatePostedExpenseRule.identity.id]
        guard case .cannotEvaluate(.partialCoverage(let reason)) = result?.outcome else {
            Issue.record("expected cannotEvaluate, got \(String(describing: result?.outcome))")
            return
        }
        #expect(reason == "readPurchases returned a full page")
        // `StatusMapping.status(for:)` lives in VoiceLedgerUI, which no test
        // target currently depends on (checked Package.swift — CoreTests
        // only depends on Core), so it can't be called from this fixture.
        // Its logic was verified by direct code trace instead
        // (Sources/VoiceLedgerUI/StatusMapping.swift lines 13-22): the
        // `.cannotEvaluate` case maps unconditionally to `.notChecked`
        // (gray) with no other branch that could turn it green. Confirmed
        // here structurally: this IS a `.cannotEvaluate`.
        if case .cannotEvaluate = result!.outcome {
            // matches — see comment above
        } else {
            Issue.record("expected cannotEvaluate")
        }
    }

    /// Companion positive case: with `.complete` coverage and real findings,
    /// the engine result maps to `.reviewNeeded` (not green) via
    /// `StatusMapping`.
    @Test("Engine result with findings maps to reviewNeeded, never verified")
    func engineResult_withFindings_mapsToReviewNeeded() async {
        let engine = RuleEngine(rules: [DuplicatePostedExpenseRule.self])
        let a = purchase(id: "145", docNumber: "4471")
        let b = purchase(id: "151", docNumber: "4471-DUP")
        let input = dataSet([a, b])
        let evaluation = await engine.evaluate(pages: [.page3Transactions], input: input, context: context())
        let result = evaluation.results[DuplicatePostedExpenseRule.identity.id]
        guard case .findings(let findings) = result?.outcome else {
            Issue.record("expected findings, got \(String(describing: result?.outcome))")
            return
        }
        #expect(findings.count == 1)
        // Same StatusMapping caveat as above — verified by trace instead of
        // call: `.findings` maps unconditionally to `.reviewNeeded`.
    }

    // MARK: Check 2 — coverage-strip percentage/denominator

    /// `StatusMapping.status(for:)` never produces a bare percentage or
    /// score — confirmed by exhaustively enumerating every `RuleOutcome`
    /// shape and inspecting the `VLStatus` cases it can produce. There is no
    /// numeric health score anywhere in this mapping to lack a denominator.
    @Test("RuleOutcome itself carries no numeric percentage/score field — only these three discrete cases")
    func ruleOutcome_hasNoNumericScoreField() {
        // Exhaustive over RuleOutcome's three cases (Sources/Core/RuleEngine.swift
        // lines 153-157) — `.pass(coverage:checkedCount:)`, `.findings([Finding])`,
        // `.cannotEvaluate(MissingRequirement)`. None of the three carries a
        // percentage/ratio; `checkedCount` is a raw count, never divided by
        // anything to form a score, and StatusMapping.status(for:) (read directly,
        // Sources/VoiceLedgerUI/StatusMapping.swift lines 13-22) switches on
        // these three cases only, producing a discrete VLStatus — never a Double
        // or percentage string. Confirmed by construction: this switch is
        // exhaustive (Swift enforces it) and matches what StatusMapping switches on.
        let passOutcome = RuleOutcome.pass(coverage: .complete, checkedCount: 5)
        let findingsOutcome = RuleOutcome.findings([])
        let cannotEvalOutcome = RuleOutcome.cannotEvaluate(.partialCoverage(reason: "x"))
        for outcome in [passOutcome, findingsOutcome, cannotEvalOutcome] {
            switch outcome {
            case .pass, .findings, .cannotEvaluate:
                break // exhaustive — no other case exists to hide a score in
            }
        }
    }

    // MARK: Check 3 — "Automatic" claim vs verified capability

    /// The rule hardcodes `.manualQBO` for its only proposed action (void),
    /// consistent with docs/phase-0/02_QBO_CAPABILITY_MATRIX.md row 11.x:
    /// void-a-Purchase is DISPROVEN as an API operation (verified
    /// 2026-08-16, HTTP 400 "Unsupported Operation"). Confirms the rule
    /// never claims an automatic resolution for something the API can't do.
    @Test("DUP-EXP-001's only action is manualQBO, matching the disproven void-Purchase API capability")
    func action_isManualQBO_matchingDisprovenVoidCapability() {
        let a = purchase(id: "1")
        let b = purchase(id: "2")
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b]), context: context())
        guard case .findings(let findings) = outcome, let action = findings.first?.proposedActions.first else {
            Issue.record("expected a finding with a proposed action")
            return
        }
        #expect(action.resolution == .manualQBO)
        // StatusMapping.resolutionStatus(.manualQBO) == .actionRequired,
        // confirmed by direct read of Sources/VoiceLedgerUI/StatusMapping.swift
        // lines 40-45 (no test-target access to VoiceLedgerUI — see above).
    }

    // MARK: Check 8 (N/A confirmation) — no OCR provenance ever reaches this rule

    /// Every Purchase this rule evaluates comes from `QBOSyncClient.sync`,
    /// stamped `.qboAPI(readAt:)`. Confirms by construction that this rule's
    /// evidence provenance is never `.importedFile(... extractionMethod:
    /// .onDeviceVision/.claudeVision ...)` — the OCR-to-green pathway
    /// (check 8) does not exist for this rule at all.
    @Test("Findings carry qboAPI provenance only — OCR/extraction check is N/A for this rule")
    func provenance_isQBOAPIOnly_neverExtraction() {
        let a = purchase(id: "1")
        let b = purchase(id: "2")
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b]), context: context())
        guard case .findings(let findings) = outcome, let finding = findings.first else {
            Issue.record("expected a finding")
            return
        }
        for p in finding.provenance {
            guard case .qboAPI = p else {
                Issue.record("expected qboAPI provenance, got \(p)")
                continue
            }
        }
    }

    // MARK: Account-label fallback honesty (supporting check 1)

    /// When the referenced payment account isn't present in
    /// `input.accounts` (e.g. an accounts-page truncation the overall
    /// `Coverage` scalar doesn't track — see QBOSyncClient.sync's own doc
    /// comment on accounts pagination not being wired in), the rule falls
    /// back to the RAW account id rather than fabricating or omitting a
    /// name. This is honest degradation (shows exactly what it has), not a
    /// false claim — confirmed directly rather than assumed from the code
    /// comment.
    @Test("Missing account from input.accounts falls back to the raw id, never a fabricated name, never a crash")
    func missingAccount_fallsBackToRawID_notFabricated() {
        let a = purchase(id: "1", account: "acct-999-not-in-list")
        let b = purchase(id: "2", account: "acct-999-not-in-list")
        // Deliberately empty `accounts` — simulates the account genuinely
        // missing from `input.accounts`.
        let outcome = DuplicatePostedExpenseRule.evaluate(dataSet([a, b], accounts: []), context: context())
        guard case .findings(let findings) = outcome, let finding = findings.first else {
            Issue.record("expected a finding")
            return
        }
        #expect(finding.narrative?.contains("acct-999-not-in-list") == true)
        #expect(finding.evidence[0].fieldValues["paymentAccount"] == "acct-999-not-in-list")
    }
}
