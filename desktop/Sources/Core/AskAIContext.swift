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
        // Every computed option, not just the first — so a "what should I
        // do" answer can recommend AND explain the alternatives, all
        // strictly from what this app already computed (CLAUDE.md rule 1:
        // the model narrates these, it never invents a fix of its own).
        for (index, action) in finding.proposedActions.enumerated() {
            let label = finding.proposedActions.count > 1 ? "Proposed resolution \(index + 1)" : "Proposed resolution"
            lines.append("\(label): \(action.title) (\(action.resolution.rawValue))")
            if let steps = action.guidedProcedure?.steps, !steps.isEmpty {
                lines.append("  Steps: \(steps.joined(separator: "; "))")
            }
            if !action.consequences.isEmpty {
                let consequenceText = action.consequences.map { consequence -> String in
                    switch consequence {
                    case .reconciliation(let text): return "Reconciliation: \(text)"
                    case .reporting(let text): return "Reporting: \(text)"
                    case .auditTrail(let text): return "Audit trail: \(text)"
                    }
                }.joined(separator: "; ")
                lines.append("  Consequences: \(consequenceText)")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Owner directive (2026-08-29): before any finding's context leaves
    /// this machine for the opt-in "second opinion" (OpenAI) tier, the
    /// vendor name is replaced with a placeholder — deliberately built here
    /// in Core, deterministically, rather than trusted to a prompt
    /// instruction, since a system prompt is a request the model could
    /// ignore, not a guarantee.
    ///
    /// **Honest scope, not a claim of full anonymization**: this replaces
    /// occurrences of `finding.vendorName` specifically (case-insensitive,
    /// including inside `narrative`/proposed-action text, where it often
    /// also appears in prose). It does NOT strip dollar amounts, dates,
    /// account names, or transaction identifiers — those are the facts the
    /// second opinion needs to be useful at all, and Voice Ledger doesn't
    /// have a general-purpose PII/entity scrubber to safely remove them
    /// without risking mangling the numbers themselves. The UI's own
    /// disclaimer must state this plainly rather than imply a stronger
    /// guarantee than this function actually provides.
    public static func composeRedacted(finding: Finding) -> String {
        var text = compose(finding: finding)
        // A 1-character vendor name would redact nearly every letter in
        // the text instead of one identifier — guard against that
        // pathological case rather than silently mangling the context.
        guard let vendorName = finding.vendorName, vendorName.count >= 2 else { return text }
        while let range = text.range(of: vendorName, options: .caseInsensitive) {
            text.replaceSubrange(range, with: "the vendor")
        }
        return text
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
