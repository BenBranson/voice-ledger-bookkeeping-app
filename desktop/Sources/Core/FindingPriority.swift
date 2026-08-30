import Foundation

/// Owner directive (2026-08-29): "queue findings like a triage from most
/// important to least important and give them a percentage" — CLAUDE.md
/// rule 1 means that ranking has to be deterministic Swift, never an LLM
/// guess. This combines the three signals a `Finding` already carries
/// (severity, confidence, dollar exposure) into a single reproducible 0-100
/// score, so the same findings always sort and read the same way regardless
/// of which rule produced them or in what order the engine ran.
public extension Finding {
    /// 0-100. Weighted: severity 50% (already a materiality-floor
    /// classification — the dominant signal for "does this matter"),
    /// confidence 30% (how sure the rule is this is a real issue, not a
    /// coincidence), dollar exposure 20% (so a $40,000 duplicate outranks a
    /// $2,600 one even though both cross the same "high" severity floor).
    ///
    /// Exposure is scaled against the same `MaterialityPolicy.defaultPolicy`
    /// floor `Severity.derive` itself uses, capped at 4x the floor so one
    /// enormous finding can't make every other high-severity finding look
    /// unimportant by comparison. `Money`'s `<`/arithmetic operators trap on
    /// a currency mismatch (by design — see `Money.swift`), so a
    /// non-USD-floor exposure contributes 0 to this component rather than
    /// crashing the triage screen; severity and confidence alone still
    /// place it correctly among same-severity peers.
    var priorityScore: Int {
        let severityComponent: Double = severity == .high ? 1.0 : 0.4
        let confidenceComponent: Double
        switch confidence {
        case .high: confidenceComponent = 1.0
        case .medium: confidenceComponent = 0.6
        case .low: confidenceComponent = 0.3
        }

        var exposureComponent = 0.0
        let floor = MaterialityPolicy.defaultPolicy.absoluteFloor
        if dollarExposure.currency == floor.currency, floor.minorUnits > 0 {
            let ratio = Double(dollarExposure.minorUnits) / Double(floor.minorUnits * 4)
            exposureComponent = min(1.0, max(0.0, ratio))
        }

        let weighted = severityComponent * 0.5 + confidenceComponent * 0.3 + exposureComponent * 0.2
        return Int((weighted * 100).rounded())
    }
}

/// Deterministic triage ordering — highest `priorityScore` first. Ties break
/// on raw dollar exposure (same-currency only, for the same crash-safety
/// reason `priorityScore` guards against), then finding id, so the order is
/// stable and reproducible across runs rather than depending on whatever
/// order `RuleEngine.evaluate` happened to produce findings in.
public enum FindingTriage {
    public static func sorted(_ findings: [Finding]) -> [Finding] {
        findings.sorted { a, b in
            if a.priorityScore != b.priorityScore { return a.priorityScore > b.priorityScore }
            if a.dollarExposure.currency == b.dollarExposure.currency, a.dollarExposure != b.dollarExposure {
                return a.dollarExposure > b.dollarExposure
            }
            return a.id < b.id
        }
    }
}

public extension Finding {
    /// Owner directive (2026-08-30), via Gemma's own suggestion on Cleanup
    /// Assessment: "rank findings not just by severity, but by ease of fix
    /// vs. dollar impact." `ResolutionKind` already carries the real signal
    /// this needs — `.stagedAPI` (Apply Fix does the whole thing, then a
    /// verified round-trip re-check) vs. `.manualQBO` (the bookkeeper has to
    /// go do it in QBO by hand) IS "ease of fix," not a new invented metric.
    /// A finding with no proposed action at all counts as manual — nothing
    /// automatable exists for it, so it can't be a one-click quick win.
    var isQuickWin: Bool {
        proposedActions.first?.resolution == .stagedAPI
    }
}

/// Owner directive (2026-08-30): "quick wins first" — a bookkeeper working
/// through a fresh client's books should hit the one-click fixes before the
/// findings that need real manual work in QBO, since clearing those first
/// shrinks the list fastest for the same time spent. Ties within each group
/// fall back to `FindingTriage.sorted`'s own priority ordering, so this is
/// additive to triage, not a replacement for it.
public enum QuickWinTriage {
    public static func sorted(_ findings: [Finding]) -> [Finding] {
        FindingTriage.sorted(findings).sorted { a, b in
            if a.isQuickWin != b.isQuickWin { return a.isQuickWin && !b.isQuickWin }
            return false
        }
    }
}
