import Foundation

/// docs/phase-0/08_RULE_ENGINE.md §8.2a. Recorded when a relationship-class
/// rule's finding gates a specific transaction out of categorization-class
/// evaluation — the gate is visible, never silent (mirrors §8.5 step 6's
/// suppression rule).
///
/// **Scoped to one transaction, not a whole rule.** An earlier version of
/// this type gated entire categorization RULES whenever any relationship
/// rule fired at all — correct for a single-relationship-rule fixture test,
/// but wrong the moment a second, unrelated categorization rule existed:
/// `VL-CC-PAYMENT-001` firing on one transaction must not blind
/// `VL-PAYROLL-LUMP-001` to every OTHER transaction on the same page. Caught
/// while wiring in the first two real Cleanup Assessment rules, before it
/// could produce a wrong result — see `RuleEngineGatingTests`.
public struct GatingOutcome: Sendable {
    public let transactionID: String
    public let gatingRuleID: RuleID
    public let gatingFindingID: String
    public let reason: String
}

public struct EngineDefect: Sendable {
    public let ruleID: RuleID
    public let description: String
}

public struct CheckResult: Sendable {
    public let outcome: RuleOutcome
}

public struct PageEvaluation: Sendable {
    public let results: [RuleID: CheckResult]
    public let gating: [GatingOutcome]
    public let engineDefects: [EngineDefect]
}

/// docs/phase-0/08_RULE_ENGINE.md §8.5.
public actor RuleEngine {
    private let rules: [any Rule.Type]

    public init(rules: [any Rule.Type]) {
        self.rules = rules
    }

    /// `pages`, not a single page: docs/backlog/CLEANUP_MODE.md describes
    /// the Cleanup Assessment as running "every deterministic rule across
    /// the full available history," aggregating across what were
    /// previously separate per-page rule buckets — not a page with its own
    /// siloed rule set. Passing a set (rather than adding a second method)
    /// keeps §8.2a's gating correct in both cases: a relationship rule on
    /// one page can gate a categorization rule on another page IF the
    /// caller asked for both together, and single-page callers (`Set([.page3Transactions])`)
    /// see exactly the old single-page behavior.
    public func evaluate(pages: Set<WorkflowPage>, input: NormalizedDataSet, context: RuleContext) -> PageEvaluation {
        let relevantRules = rules.filter { pages.contains($0.identity.page) }
        let relationshipRules = relevantRules.filter { $0.identity.ruleClass == .relationship }
        let categorizationRules = relevantRules.filter { $0.identity.ruleClass == .categorization }

        var results: [RuleID: CheckResult] = [:]
        var gating: [GatingOutcome] = []
        var defects: [EngineDefect] = []

        // Step 1a (§8.2a): relationship-class rules evaluate first, against
        // the ORIGINAL context (no transactions gated yet — nothing can gate
        // a relationship rule).
        var gatedTransactionIDs: Set<String> = []
        for ruleType in relationshipRules {
            let result = Self.runOne(ruleType, input: input, context: context, defects: &defects)
            results[ruleType.identity.id] = result
            if case .findings(let findings) = result.outcome {
                for finding in findings {
                    for evidence in finding.evidence {
                        gatedTransactionIDs.insert(evidence.transactionID)
                        gating.append(GatingOutcome(
                            transactionID: evidence.transactionID,
                            gatingRuleID: ruleType.identity.id,
                            gatingFindingID: finding.id,
                            reason: "Not evaluated by categorization rules — already explained by relationship finding \(finding.id) (\(ruleType.identity.id))."
                        ))
                    }
                }
            }
        }

        // Categorization rules run with an AUGMENTED context carrying the
        // gated transaction IDs — each rule is responsible for skipping
        // those specific transactions in its own loop (see
        // DuplicatePostedExpenseRule / CreditCardPaymentMiscodedRule /
        // PayrollLumpSumRule). The rule itself still runs and can still
        // produce findings for every OTHER transaction — nothing is
        // suppressed at the rule level anymore.
        let categorizationContext = context.gatingTransactions(gatedTransactionIDs)
        for ruleType in categorizationRules {
            results[ruleType.identity.id] = Self.runOne(ruleType, input: input, context: categorizationContext, defects: &defects)
        }

        return PageEvaluation(results: results, gating: gating, engineDefects: defects)
    }

    /// docs/phase-0/08_RULE_ENGINE.md §8.5 steps 1, 3, 4, 5 (steps 2 and 6
    /// — data assembly and suppression — are handled by the caller and by
    /// individual rules' own exclusions respectively; see
    /// docs/phase-0/11_VERTICAL_SLICE.md §11.2 for VL-DUP-EXP-001's).
    private static func runOne(
        _ ruleType: any Rule.Type,
        input: NormalizedDataSet,
        context: RuleContext,
        defects: inout [EngineDefect]
    ) -> CheckResult {
        // Step 3: coverage gate. The rule never runs if required coverage
        // isn't met — this is what makes CLAUDE.md rule 5 (gray, not green,
        // on incomplete data) a type-level guarantee rather than a rule
        // author's responsibility to remember.
        if case .partial(let reason) = input.coverage, ruleType.requirements.requiredCoverage == .complete {
            return CheckResult(outcome: .cannotEvaluate(.partialCoverage(reason: reason)))
        }

        // Step 4: evaluate (pure — no I/O possible through `RuleContext`).
        let outcome = ruleType.evaluate(input, context: context)

        // Step 5: outcome validation (§8.1) — a rule cannot claim `.pass`
        // on incomplete coverage. Catching this here, not trusting the rule,
        // is the defense §8.1 describes against our own future carelessness.
        if case .pass(let coverage, _) = outcome, coverage != .complete {
            defects.append(EngineDefect(
                ruleID: ruleType.identity.id,
                description: "Rule returned .pass with coverage \(coverage) — downgraded to .cannotEvaluate."
            ))
            return CheckResult(outcome: .cannotEvaluate(.partialCoverage(reason: "engine defect: rule claimed .pass on incomplete coverage")))
        }

        return CheckResult(outcome: outcome)
    }
}

/// docs/phase-0/08_RULE_ENGINE.md §8.3. Compile-time registration — adding a
/// rule means editing this list, so it appears in a diff and gets reviewed.
public enum RuleRegistry {
    public static let all: [any Rule.Type] = [
        DuplicatePostedExpenseRule.self,
        CreditCardPaymentMiscodedRule.self,
        PayrollLumpSumRule.self,
        OpeningBalanceEquityRule.self,
        NegativeBalanceRule.self,
        DuplicateVendorRule.self
    ]

    public static func rules(for page: WorkflowPage) -> [any Rule.Type] {
        all.filter { $0.identity.page == page }
    }
}
