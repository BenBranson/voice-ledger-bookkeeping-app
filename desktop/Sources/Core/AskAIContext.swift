import Foundation

/// docs/VOICE_LEDGER_SPEC.md: "Every page ends with an Ask [AI] panel."
/// This is the deterministic half of that feature — CLAUDE.md rule 1's
/// boundary lives here as much as in the backend's system prompt: this
/// function only ever serializes fields a `Finding` (and its rule) already
/// carry, in plain English, for the AI to explain. It never invents a
/// number, and the backend's own system prompt is separately instructed
/// not to introduce one either — two independent places enforcing the
/// same rule, matching this codebase's general posture of not relying on
/// a single point to hold a safety property.
public enum AskAIContext {
    public static func compose(finding: Finding) -> String {
        let ruleIdentity = RuleRegistry.all.first { $0.identity.id == finding.ruleID }?.identity
        let periodLabel = "\(finding.period.year)-\(String(format: "%02d", finding.period.month))"

        var lines: [String] = []
        lines.append("Finding: \(finding.title)")
        lines.append("Period: \(periodLabel)")
        lines.append("Severity: \(finding.severity.rawValue)")
        lines.append("Confidence: \(finding.confidence.rawValue)")
        lines.append("Dollar exposure: \(finding.dollarExposure.description)")
        lines.append("Status: \(finding.status.rawValue)")
        if let vendorName = finding.vendorName {
            lines.append("Vendor: \(vendorName)")
        }
        if let narrative = finding.narrative {
            lines.append("Narrative: \(narrative)")
        }
        if let riskIfIgnored = finding.riskIfIgnored {
            lines.append("Risk if left open: \(riskIfIgnored)")
        }
        if let principle = ruleIdentity?.accountingPrinciple {
            lines.append("Accounting principle: \(principle)")
        }
        if let action = finding.proposedActions.first {
            lines.append("Proposed resolution: \(action.title) (\(action.resolution.rawValue))")
        }
        return lines.joined(separator: "\n")
    }
}
