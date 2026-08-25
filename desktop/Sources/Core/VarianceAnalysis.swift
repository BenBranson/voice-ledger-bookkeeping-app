import Foundation

/// docs/VOICE_LEDGER_SPEC.md's Firm Cockpit Close Package section names
/// "variance" as part of what a close package should show — previously not
/// built anywhere in the app. Pure arithmetic over two already-fetched
/// report line sets (current period vs. a prior period, both real QBO
/// data): no invented numbers, no AI involvement, matching CLAUDE.md rule 1
/// ("code computes and classifies, Claude explains — never an authoritative
/// number from anything but deterministic Swift").
public struct VarianceLine: Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let depth: Int
    public let isSummary: Bool
    public let currentAmount: Money?
    public let priorAmount: Money?
    /// `currentAmount - priorAmount`. `nil` when either side is missing —
    /// a missing amount is not the same as zero, and treating it as such
    /// would fabricate a change that was never actually computed from two
    /// real numbers.
    public let change: Money?
    /// `change / priorAmount`, as a fraction (0.10 = +10%). `nil` when
    /// `priorAmount` is `nil` OR zero — dividing by zero (or by an amount
    /// that was never fetched) has no honest percentage to report.
    public let percentChange: Double?

    public init(label: String, depth: Int, isSummary: Bool, currentAmount: Money?, priorAmount: Money?) {
        self.id = "\(depth)-\(label)-\(isSummary)"
        self.label = label
        self.depth = depth
        self.isSummary = isSummary
        self.currentAmount = currentAmount
        self.priorAmount = priorAmount
        if let currentAmount, let priorAmount, currentAmount.currency == priorAmount.currency {
            self.change = currentAmount - priorAmount
        } else {
            self.change = nil
        }
        if let priorAmount, priorAmount.minorUnits != 0, let change {
            self.percentChange = Double(change.minorUnits) / Double(abs(priorAmount.minorUnits))
        } else {
            self.percentChange = nil
        }
    }
}

public enum VarianceAnalysis {
    /// Matches lines by `label` — the same key QBO's own report structure
    /// uses consistently across periods for the same account/section.
    /// Iterates `current`'s own line order (so the result reads in the
    /// same order as the report already on screen); a label present in
    /// `prior` but not `current` (an account with prior-period activity
    /// only) is appended at the end, since there's no natural position for
    /// it in `current`'s ordering. Duplicate labels within one side (rare,
    /// but the account hierarchy can repeat a name at different depths)
    /// match by first-occurrence-in-order on both sides — a best-effort
    /// pairing, not a perfect structural diff.
    public static func compute(current: [ReportLine], prior: [ReportLine]) -> [VarianceLine] {
        var priorByLabel: [String: [Money?]] = [:]
        for line in prior {
            priorByLabel[line.label, default: []].append(line.amount)
        }
        var priorConsumedCount: [String: Int] = [:]

        var result: [VarianceLine] = []
        var currentLabels = Set<String>()
        for line in current {
            currentLabels.insert(line.label)
            let consumed = priorConsumedCount[line.label, default: 0]
            let candidates = priorByLabel[line.label] ?? []
            let priorAmount: Money? = consumed < candidates.count ? candidates[consumed] : nil
            priorConsumedCount[line.label] = consumed + 1
            result.append(VarianceLine(label: line.label, depth: line.depth, isSummary: line.isSummary, currentAmount: line.amount, priorAmount: priorAmount))
        }
        for line in prior where !currentLabels.contains(line.label) {
            result.append(VarianceLine(label: line.label, depth: line.depth, isSummary: line.isSummary, currentAmount: nil, priorAmount: line.amount))
        }
        return result
    }
}
