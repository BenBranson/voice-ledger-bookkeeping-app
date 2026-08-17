import Foundation

/// docs/phase-0/08_RULE_ENGINE.md §8.2a. Recorded when a relationship-class
/// rule's finding suppresses a categorization-class rule for the same
/// transaction — the gate is visible, never silent (mirrors §8.5 step 6's
/// suppression rule).
public struct GatingOutcome: Sendable {
    public let suppressedRuleID: RuleID
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

    public func evaluate(page: WorkflowPage, input: NormalizedDataSet, context: RuleContext) -> PageEvaluation {
        let relevantRules = rules.filter { $0.identity.page == page }
        let relationshipRules = relevantRules.filter { $0.identity.ruleClass == .relationship }
        let categorizationRules = relevantRules.filter { $0.identity.ruleClass == .categorization }

        var results: [RuleID: CheckResult] = [:]
        var gating: [GatingOutcome] = []
        var defects: [EngineDefect] = []

        // Step 1a (§8.2a): relationship-class rules evaluate first. With
        // zero relationship rules registered in this phase, this loop is a
        // structural no-op in production — exercised instead by
        // RuleEngineGatingTests using a fixture relationship rule, so the
        // branch itself is real and tested even though no shipped rule
        // takes it yet.
        var gatedRuleIDs: Set<RuleID> = []
        for ruleType in relationshipRules {
            let result = Self.runOne(ruleType, input: input, context: context, defects: &defects)
            results[ruleType.identity.id] = result
            if case .findings(let findings) = result.outcome, let first = findings.first {
                for catRule in categorizationRules {
                    gatedRuleIDs.insert(catRule.identity.id)
                    gating.append(GatingOutcome(
                        suppressedRuleID: catRule.identity.id,
                        gatingFindingID: first.id,
                        reason: "Not evaluated — transaction already explained by relationship finding \(first.id) (\(ruleType.identity.id))."
                    ))
                }
            }
        }

        for ruleType in categorizationRules {
            guard !gatedRuleIDs.contains(ruleType.identity.id) else { continue }
            results[ruleType.identity.id] = Self.runOne(ruleType, input: input, context: context, defects: &defects)
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
        DuplicatePostedExpenseRule.self
    ]

    public static func rules(for page: WorkflowPage) -> [any Rule.Type] {
        all.filter { $0.identity.page == page }
    }
}
