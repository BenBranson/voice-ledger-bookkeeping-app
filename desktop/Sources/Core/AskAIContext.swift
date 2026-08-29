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
    /// occurrences of `finding.vendorName` and any account name
    /// STRUCTURALLY tied to this specific finding via a `ProposedAction`'s
    /// `apiWriteDetails` (`currentAccountName`/`suggestedAccountName`) —
    /// case-insensitive, including inside `narrative`/proposed-action
    /// text, where they often also appear in prose, not just a labeled
    /// field.
    ///
    /// Deliberately does NOT scan the client's entire chart of accounts
    /// for a broader sweep — most real account names are short, ordinary
    /// English words ("Cash," "Rent," "Sales"), and blindly redacting any
    /// occurrence of every account name in the file would risk mangling
    /// unrelated prose ("cash flow," "total sales") the way a 1-character
    /// vendor name would (see the guard below). Only redacting names this
    /// function can PROVE are actually about this finding, not merely
    /// present somewhere in the company's books, keeps every redaction a
    /// precise, structurally-justified one rather than a guess.
    ///
    /// Still not a claim of full anonymization: dollar amounts, dates, and
    /// any account name mentioned only in a rule's own narrative prose
    /// (not carried in `apiWriteDetails`) are not stripped — those are the
    /// facts the second opinion needs to be useful at all, and Voice
    /// Ledger doesn't have a general-purpose PII/entity scrubber to safely
    /// remove more than this without risking mangling the numbers
    /// themselves. The UI's own disclaimer must state this plainly rather
    /// than imply a stronger guarantee than this function actually
    /// provides.
    public static func composeRedacted(finding: Finding) -> String {
        var text = compose(finding: finding)
        text = redact(finding.vendorName, in: text, placeholder: "the vendor")
        for action in finding.proposedActions {
            guard let details = action.apiWriteDetails else { continue }
            text = redact(details.currentAccountName, in: text, placeholder: "an account")
            text = redact(details.suggestedAccountName, in: text, placeholder: "another account")
        }
        return text
    }

    /// A 1-character (or empty) identifier would redact nearly every
    /// occurrence of that letter instead of one real identifier — guard
    /// against that pathological case rather than silently mangling the
    /// context.
    private static func redact(_ identifier: String?, in text: String, placeholder: String) -> String {
        guard let identifier, identifier.count >= 2 else { return text }
        var result = text
        while let range = result.range(of: identifier, options: .caseInsensitive) {
            result.replaceSubrange(range, with: placeholder)
        }
        return result
    }

    /// Owner directive (2026-08-29): the two report-generation buttons on
    /// Findings — "the reports should touch upon the overall health of the
    /// client's books and not [only] the major negative findings but also
    /// what is going well... able to see what's been improved or
    /// downgraded since last month." Every figure here is already real,
    /// deterministic Core/`FinancialKPIs`/`VarianceAnalysis` output — this
    /// only serializes it; the AI's job is narration, same CLAUDE.md rule 1
    /// boundary as every other `AskAIContext` function.
    ///
    /// `priorBalanceSheetLines`/`priorProfitAndLossLines` are optional —
    /// when `nil` (prior-period data hasn't been loaded), the month-over-
    /// month section is simply omitted rather than fabricated.
    public static func composeHealthReport(
        openFindings: [Finding],
        resolvedFindings: [Finding],
        dismissedFindings: [Finding],
        balanceSheetLines: [ReportLine],
        profitAndLossLines: [ReportLine],
        priorBalanceSheetLines: [ReportLine]?,
        priorProfitAndLossLines: [ReportLine]?,
        period: AccountingPeriod
    ) -> String {
        let periodLabel = "\(period.year)-\(String(format: "%02d", period.month))"
        var lines: [String] = ["Period: \(periodLabel)"]

        lines.append("")
        lines.append("OPEN ISSUES (negative):")
        let highCount = openFindings.filter { $0.severity == .high }.count
        let lowCount = openFindings.count - highCount
        lines.append("\(openFindings.count) open finding(s) — \(highCount) high severity, \(lowCount) low severity.")
        for finding in openFindings.prefix(15) {
            lines.append("- \(finding.title) (\(finding.severity.rawValue) severity, \(finding.dollarExposure.description))")
        }
        if openFindings.count > 15 {
            lines.append("...and \(openFindings.count - 15) more not listed here.")
        }

        lines.append("")
        lines.append("WHAT'S GOING WELL (positive):")
        lines.append("\(resolvedFindings.count) finding(s) resolved and confirmed fixed, \(dismissedFindings.count) reviewed and dismissed as not a real issue, this period.")
        for finding in resolvedFindings.prefix(15) {
            lines.append("- Fixed: \(finding.title)")
        }

        lines.append("")
        lines.append("KEY METRICS:")
        if let workingCapital = FinancialKPIs.workingCapital(from: balanceSheetLines) {
            lines.append("Working capital: \(workingCapital.description)")
        }
        if let currentRatio = FinancialKPIs.currentRatio(from: balanceSheetLines) {
            lines.append("Current ratio: \(String(format: "%.2f", currentRatio))")
        }
        if let grossMargin = FinancialKPIs.grossMarginPercent(from: profitAndLossLines) {
            lines.append("Gross margin: \(String(format: "%.1f", grossMargin))%")
        }
        if let netMargin = FinancialKPIs.netMarginPercent(from: profitAndLossLines) {
            lines.append("Net margin: \(String(format: "%.1f", netMargin))%")
        }
        if let netIncome = TaxEstimate.netIncome(from: profitAndLossLines) {
            lines.append("Net income: \(netIncome.description)")
        }

        if let priorBalanceSheetLines, let priorProfitAndLossLines {
            lines.append("")
            lines.append("CHANGE SINCE LAST PERIOD (summary lines only):")
            let bsVariance = VarianceAnalysis.compute(current: balanceSheetLines, prior: priorBalanceSheetLines).filter(\.isSummary)
            let plVariance = VarianceAnalysis.compute(current: profitAndLossLines, prior: priorProfitAndLossLines).filter(\.isSummary)
            for variance in (bsVariance + plVariance) {
                guard let change = variance.change else { continue }
                let percentText = variance.percentChange.map { " (\(String(format: "%+.1f", $0 * 100))%)" } ?? ""
                lines.append("\(variance.label): \(change.minorUnits >= 0 ? "+" : "")\(change.description)\(percentText)")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Owner directive (2026-08-29): the "value summary" button, shown once
    /// every finding is cleared — "explains all changes that I have made
    /// and explain whether I helped the client save money, time, etc."
    /// **Honest scope, deliberately**: this states the real, computed
    /// dollar exposure that was identified and corrected — never a claim of
    /// literal cash savings, which this app has no way to verify (CLAUDE.md
    /// rule 5 / the system prompt's own "never state a figure not already
    /// in context" rule). The AI narrating this context is told the same
    /// thing; this function's own field names ("exposure addressed," not
    /// "money saved") are the first line of defense.
    public static func composeValueSummary(
        resolvedFindings: [Finding],
        dismissedFindings: [Finding],
        corrections: [ActivityLogEntry],
        since: Date?
    ) -> String {
        var lines: [String] = []
        if let since {
            lines.append("Reporting period: since \(ISO8601DateFormatter().string(from: since)).")
        } else {
            lines.append("Reporting period: this is the first report generated for this client.")
        }

        lines.append("")
        lines.append("\(resolvedFindings.count) finding(s) were resolved and confirmed fixed against QuickBooks. \(dismissedFindings.count) were reviewed and dismissed as not real issues.")

        // Same-currency guard as `Finding.priorityScore` — summing across
        // currencies would be meaningless, not merely imprecise.
        let currency = resolvedFindings.first?.dollarExposure.currency
        if let currency, resolvedFindings.allSatisfy({ $0.dollarExposure.currency == currency }) {
            let total = resolvedFindings.reduce(Money(minorUnits: 0, currency: currency)) { $0 + $1.dollarExposure }
            lines.append("Total dollar exposure identified and corrected: \(total.description). This is the amount these errors would have overstated or understated the books by if left uncorrected — not a claim of cash the client received.")
        }

        if !resolvedFindings.isEmpty {
            lines.append("")
            lines.append("WHAT WAS FIXED:")
            for finding in resolvedFindings.prefix(20) {
                lines.append("- \(finding.title) (\(finding.dollarExposure.description))")
            }
        }

        if !corrections.isEmpty {
            lines.append("")
            lines.append("ACTIONS TAKEN:")
            for entry in corrections.prefix(20) {
                let summary = entry.findingSummary ?? entry.kind.rawValue
                lines.append("- \(summary)" + (entry.note.map { " — \($0)" } ?? ""))
            }
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
