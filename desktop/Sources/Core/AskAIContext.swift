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
    /// Owner directive (2026-08-31): "when you first open a client's books,
    /// you want a high-impact overview that highlights anomalies,
    /// compliance risks, and health metrics instantly" — a "Danger Zone"
    /// hygiene section, added onto the existing health report rather than
    /// as a separate report type, so this signal is available every time
    /// this report runs, not just once. Two of the four signals originally
    /// proposed for this (bank reconciliation status, "Ask My Accountant"
    /// totals) are deliberately NOT included here: nothing in this
    /// codebase reads a last-reconciled-date from QBO today, and
    /// "Ask My Accountant" has no rule coverage the way `Uncategorized
    /// Expense/Income/Asset` does (`UncategorizedTransactionRule`,
    /// live-verified against this sandbox's real account IDs) — CLAUDE.md
    /// rule 6 means neither ships in a report until it's verified against
    /// this app's real data sources, not assumed from a general QBO
    /// feature list.
    ///
    /// `agedReceivablesLines`/`agedPayablesLines` optional for the same
    /// reason `priorBalanceSheetLines` is — a caller that hasn't loaded
    /// that report yet still gets a valid report, just without this
    /// section, rather than being forced to fetch it first.
    public static func composeHealthReport(
        openFindings: [Finding],
        resolvedFindings: [Finding],
        dismissedFindings: [Finding],
        balanceSheetLines: [ReportLine],
        profitAndLossLines: [ReportLine],
        priorBalanceSheetLines: [ReportLine]?,
        priorProfitAndLossLines: [ReportLine]?,
        agedReceivablesLines: [AgingLine]? = nil,
        agedPayablesLines: [AgingLine]? = nil,
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

        let uncategorizedFindings = openFindings.filter { $0.ruleID.rawValue == "VL-CAT-UNCAT-001" }
        let arOver60 = sumAgingOver60Days(agedReceivablesLines)
        let apOver60 = sumAgingOver60Days(agedPayablesLines)
        if !uncategorizedFindings.isEmpty || arOver60 != nil || apOver60 != nil {
            lines.append("")
            lines.append("DATA HYGIENE & AGING:")
            if !uncategorizedFindings.isEmpty {
                let currency = uncategorizedFindings[0].dollarExposure.currency
                if uncategorizedFindings.allSatisfy({ $0.dollarExposure.currency == currency }) {
                    let total = uncategorizedFindings.dropFirst().reduce(uncategorizedFindings[0].dollarExposure) { $0 + $1.dollarExposure }
                    lines.append("Uncategorized Expense/Income/Asset: \(uncategorizedFindings.count) transaction(s) still sitting in QBO's catch-all accounts, totaling \(total.description).")
                } else {
                    lines.append("Uncategorized Expense/Income/Asset: \(uncategorizedFindings.count) transaction(s) still sitting in QBO's catch-all accounts (mixed currencies, not summed).")
                }
            }
            if let arOver60 {
                lines.append("Accounts Receivable over 60 days: \(arOver60.description).")
            }
            if let apOver60 {
                lines.append("Accounts Payable over 60 days: \(apOver60.description).")
            }
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

    /// Sums the 61-90 and 91-and-over buckets across non-summary (leaf)
    /// aging rows — the report's own summary row is excluded so this
    /// doesn't double-count it alongside the leaf rows it already totals.
    /// Same-currency-guarded like every other sum in this file; `nil`
    /// (rather than a fabricated zero) when there's nothing to sum, so the
    /// caller can tell "genuinely zero over 60 days" apart from "this
    /// report hasn't been loaded."
    private static func sumAgingOver60Days(_ lines: [AgingLine]?) -> Money? {
        guard let lines, !lines.isEmpty else { return nil }
        let leafLines = lines.filter { !$0.isSummary }
        guard !leafLines.isEmpty else { return nil }
        let amounts = leafLines.compactMap { line -> Money? in
            switch (line.days61to90, line.days91AndOver) {
            case (nil, nil): return nil
            case (let a?, nil): return a
            case (nil, let b?): return b
            case (let a?, let b?): return a + b
            }
        }
        guard let first = amounts.first, amounts.allSatisfy({ $0.currency == first.currency }) else { return nil }
        return amounts.dropFirst().reduce(first) { $0 + $1 }
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

    /// The report-page counterpart to `compose(pageTitle:findings:)` —
    /// owner directive 2026-08-30: every section of the app should end in
    /// an Ask AI panel, including the report pages (Balance Sheet, P&L,
    /// Trial Balance, General Ledger, Aging) that have no `Finding`s at
    /// all, only report lines. Each report view's own line type (`ReportLine`,
    /// `TrialBalanceLine`, `AgingLine`, `GeneralLedgerLine`) is different, so
    /// rather than one composer per type, the caller renders its own lines
    /// to plain text first (each already has a `label` plus one or more
    /// `Money?` fields to describe) — this just assembles the page-level
    /// envelope around whatever lines it's handed, capped the same way
    /// `compose(pageTitle:findings:)` is.
    public static func compose(pageTitle: String, summaryLines: [String]) -> String {
        var lines: [String] = ["Page: \(pageTitle)"]
        lines.append(contentsOf: summaryLines.prefix(60))
        if summaryLines.count > 60 {
            lines.append("...and \(summaryLines.count - 60) more not listed here")
        }
        return lines.joined(separator: "\n")
    }

    /// Owner directive (2026-08-31): "when a client's general ledger or P&L
    /// data payload exceeds a safe token threshold, the code should
    /// summarize account totals first." A real gap this closes: General
    /// Ledger and Trial Balance can legitimately carry more accounts than
    /// `compose(pageTitle:summaryLines:)`'s own 60-line cap — and that cap
    /// previously just kept whichever 60 happened to come first (however
    /// the caller had them ordered) and silently dropped the rest with a
    /// bare "...and N more," which could drop a materially large account
    /// while keeping several tiny ones. This keeps the `keepTop` accounts
    /// by absolute dollar size instead — the ones an Ask AI answer is
    /// actually likely to be asked about — and, instead of just dropping
    /// the remainder, collapses it into one REAL summed total (never an AI
    /// guess — CLAUDE.md rule 1). Every account is still accounted for in
    /// the output, either individually or inside that aggregate.
    ///
    /// Sorted by `abs(minorUnits)` directly rather than via `Money`'s own
    /// `<` (which `precondition`-traps on a currency mismatch, by design —
    /// see `Money.swift`) — comparing raw magnitudes sidesteps that trap
    /// entirely, which matters here since this may run over a full chart
    /// of accounts that isn't guaranteed single-currency.
    ///
    /// Not a token counter — "safe token threshold" in practice, for the
    /// English/number-heavy text these contexts are made of, tracks closely
    /// enough with line/entry COUNT that a count-based cap is the honest
    /// choice here: an estimated token count from character length would
    /// be a guess dressed up as a measurement, which is worse than a plain,
    /// correct entry count the caller can reason about directly.
    /// `text` is the caller's own fully-formatted display line for that
    /// entry — e.g. Trial Balance wants both "debit X, credit Y" shown
    /// together, not a single collapsed amount, so the ranking/aggregation
    /// key (`amount`) is kept separate from what's actually rendered.
    public static func summarizeAccountTotals(_ entries: [(text: String, amount: Money)], keepTop: Int = 15) -> [String] {
        guard entries.count > keepTop else {
            return entries.map(\.text)
        }

        let sorted = entries.sorted { abs($0.amount.minorUnits) > abs($1.amount.minorUnits) }
        let kept = sorted.prefix(keepTop)
        let remainder = sorted.dropFirst(keepTop)

        var lines = kept.map(\.text)

        let currency = remainder.first?.amount.currency
        if let currency, remainder.allSatisfy({ $0.amount.currency == currency }) {
            let remainderTotal = remainder.reduce(Money(minorUnits: 0, currency: currency)) { $0 + $1.amount }
            lines.append("...and \(remainder.count) more account(s), totaling \(remainderTotal.description) — the largest \(keepTop) accounts by dollar size are listed above in full")
        } else {
            // Mixed currencies in the remainder: summing them would be
            // meaningless (`Money`'s own `+` traps on this for the same
            // reason `<` does), so this states the real count honestly
            // instead of a fabricated total.
            lines.append("...and \(remainder.count) more account(s) not summarized here (mixed currencies) — the largest \(keepTop) accounts by dollar size are listed above in full")
        }
        return lines
    }
}
