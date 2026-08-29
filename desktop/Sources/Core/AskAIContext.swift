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

    /// The page-level counterpart to `compose(finding:)` — added when the
    /// Ask AI panel expanded beyond `FindingDetailView` to other pages
    /// (docs/VOICE_LEDGER_SPEC.md: "Every page ends with an Ask [AI]
    /// panel."). Same boundary: only serializes fields these findings
    /// already carry, capped at 20 so the context stays a summary rather
    /// than dumping the entire page's data into the prompt.
    public static func compose(pageTitle: String, findings: [Finding]) -> String {
        var lines: [String] = ["Page: \(pageTitle)", "Open findings: \(findings.count)"]
        for finding in findings.prefix(20) {
            let periodLabel = "\(finding.period.year)-\(String(format: "%02d", finding.period.month))"
            lines.append("- \(finding.title) — severity \(finding.severity.rawValue), exposure \(finding.dollarExposure.description), period \(periodLabel)")
        }
        if findings.count > 20 {
            lines.append("...and \(findings.count - 20) more not listed here")
        }
        return lines.joined(separator: "\n")
    }
}
