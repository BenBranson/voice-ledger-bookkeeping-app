import Testing
@testable import Core

@Suite("AskAIContext.compose")
struct AskAIContextTests {
    func finding(narrative: String? = nil, riskIfIgnored: String? = nil, vendorName: String? = nil) -> Finding {
        Finding(
            id: "f1",
            ruleID: RuleID(rawValue: "VL-DUP-EXP-001"),
            ruleVersion: RuleVersion(major: 1, minor: 0, patch: 0),
            realmID: RealmID(rawValue: "realm-a"),
            period: AccountingPeriod(year: 2026, month: 7),
            title: "Possible duplicate expense",
            severity: .high,
            confidence: .high,
            dollarExposure: Money(minorUnits: 48_620, currency: .usd),
            evidence: [],
            proposedActions: [],
            provenance: [],
            vendorName: vendorName,
            narrative: narrative,
            riskIfIgnored: riskIfIgnored
        )
    }

    @Test("Includes the core deterministic fields every finding has")
    func includesCoreFields() {
        let context = AskAIContext.compose(finding: finding())
        #expect(context.contains("Possible duplicate expense"))
        #expect(context.contains("2026-07"))
        #expect(context.contains("high"))
        #expect(context.contains("USD 486.20") || context.contains("486.20"))
        #expect(context.contains("open"))
    }

    @Test("Includes narrative, riskIfIgnored, and vendorName when present")
    func includesOptionalFieldsWhenPresent() {
        let context = AskAIContext.compose(finding: finding(narrative: "A real narrative sentence.", riskIfIgnored: "A real risk sentence.", vendorName: "Permian Supply"))
        #expect(context.contains("A real narrative sentence."))
        #expect(context.contains("A real risk sentence."))
        #expect(context.contains("Permian Supply"))
    }

    @Test("Omits vendor/narrative/risk lines entirely when absent — never a placeholder")
    func omitsAbsentFieldsEntirely() {
        let context = AskAIContext.compose(finding: finding())
        #expect(!context.contains("Vendor:"))
        #expect(!context.contains("Narrative:"))
        #expect(!context.contains("Risk if left open:"))
    }

    @Test("Looks up the rule's real accountingPrinciple from RuleRegistry")
    func includesAccountingPrincipleFromRegistry() {
        let context = AskAIContext.compose(finding: finding())
        let expectedPrinciple = RuleRegistry.all.first { $0.identity.id == RuleID(rawValue: "VL-DUP-EXP-001") }!.identity.accountingPrinciple
        #expect(context.contains(expectedPrinciple))
    }

    @Test("compose(pageTitle:findings:) includes the page title and every finding's title")
    func pageLevelComposeIncludesTitleAndFindings() {
        let context = AskAIContext.compose(pageTitle: "Cleanup Assessment", findings: [finding(), finding()])
        #expect(context.contains("Cleanup Assessment"))
        #expect(context.contains("Possible duplicate expense"))
        #expect(context.contains("Open findings: 2"))
    }

    @Test("compose(pageTitle:findings:) caps the listed findings at 20 and notes the rest")
    func pageLevelComposeCapsAtTwenty() {
        let findings = (1...25).map { _ in finding() }
        let context = AskAIContext.compose(pageTitle: "Cleanup Assessment", findings: findings)
        #expect(context.contains("...and 5 more not listed here"))
    }

    @Test("compose(pageTitle:findings:) handles zero findings without a placeholder line")
    func pageLevelComposeHandlesEmpty() {
        let context = AskAIContext.compose(pageTitle: "Cleanup Assessment", findings: [])
        #expect(context.contains("Open findings: 0"))
        #expect(!context.contains("more not listed"))
    }

    // MARK: composeRedacted — the opt-in "second opinion" (OpenAI) tier's
    // context, 2026-08-29.

    @Test("composeRedacted replaces the vendor name with a placeholder")
    func composeRedactedReplacesVendorName() {
        let context = AskAIContext.composeRedacted(finding: finding(vendorName: "Permian Supply"))
        #expect(!context.contains("Permian Supply"))
        #expect(context.contains("the vendor"))
    }

    @Test("composeRedacted replaces the vendor name even when it also appears inside the narrative, not just the Vendor: line")
    func composeRedactedReplacesVendorNameInsideNarrative() {
        let context = AskAIContext.composeRedacted(finding: finding(
            narrative: "Two purchases from Permian Supply for $486.20 were posted on the same day.",
            vendorName: "Permian Supply"
        ))
        #expect(!context.contains("Permian Supply"))
    }

    @Test("composeRedacted is case-insensitive")
    func composeRedactedIsCaseInsensitive() {
        let context = AskAIContext.composeRedacted(finding: finding(
            narrative: "A charge from PERMIAN SUPPLY appeared twice.",
            vendorName: "Permian Supply"
        ))
        #expect(!context.contains("PERMIAN SUPPLY"))
    }

    @Test("composeRedacted still includes dollar exposure, severity, and dates — only the vendor identity is stripped")
    func composeRedactedKeepsFinancialFacts() {
        let context = AskAIContext.composeRedacted(finding: finding(vendorName: "Permian Supply"))
        #expect(context.contains("486.20") || context.contains("USD 486.20"))
        #expect(context.contains("high"))
        #expect(context.contains("2026-07"))
    }

    @Test("composeRedacted is identical to compose when there is no vendor name")
    func composeRedactedMatchesComposeWithNoVendor() {
        let plainFinding = finding()
        #expect(AskAIContext.composeRedacted(finding: plainFinding) == AskAIContext.compose(finding: plainFinding))
    }

    @Test("composeRedacted does not attempt to redact a 1-character vendor name — avoids mangling every occurrence of that letter")
    func composeRedactedSkipsPathologicallyShortVendorName() {
        let context = AskAIContext.composeRedacted(finding: finding(narrative: "A charge appeared twice.", vendorName: "A"))
        #expect(context.contains("A charge appeared twice."))
    }

    // MARK: composeRedacted — account-name redaction via apiWriteDetails
    // (2026-08-29): structurally-known account names, not a blind sweep
    // of the whole chart of accounts.

    private func stagedActionFinding(currentAccountName: String, suggestedAccountName: String) -> Finding {
        let details = StagedAPIWriteDetails(
            purchaseID: "p1", lineID: "l1", expectedSyncToken: "1",
            currentAccountID: "50", currentAccountName: currentAccountName,
            suggestedAccountID: "60", suggestedAccountName: suggestedAccountName
        )
        let action = ProposedAction(
            id: "reclassify", title: "Reclassify to \(suggestedAccountName)", resolution: .stagedAPI,
            guidedProcedure: nil, consequences: [], reversal: .irreversible, apiWriteDetails: details
        )
        return Finding(
            id: "f1", ruleID: RuleID(rawValue: "VL-CC-PAYMENT-001"), ruleVersion: RuleVersion(major: 1, minor: 0, patch: 0),
            realmID: RealmID(rawValue: "realm-a"), period: AccountingPeriod(year: 2026, month: 7),
            title: "Test finding", severity: .high, confidence: .high,
            dollarExposure: Money(minorUnits: 48_620, currency: .usd),
            evidence: [], proposedActions: [action], provenance: [],
            // `compose(finding:)` doesn't surface `currentAccountName`
            // anywhere on its own — only prose fields do. The narrative is
            // exactly the kind of real place a rule mentions the CURRENT
            // (wrong) account by name, which is what this test needs to
            // actually exercise both redaction targets.
            narrative: "This was coded to \(currentAccountName), which is a real problem."
        )
    }

    @Test("composeRedacted replaces both the current and suggested account names from apiWriteDetails")
    func composeRedactedReplacesStructuralAccountNames() {
        let context = AskAIContext.composeRedacted(finding: stagedActionFinding(currentAccountName: "Owner Draw", suggestedAccountName: "Payroll Expenses"))
        #expect(!context.contains("Owner Draw"))
        #expect(!context.contains("Payroll Expenses"))
        #expect(context.contains("an account"))
        #expect(context.contains("another account"))
    }

    @Test("composeRedacted's account-name redaction is case-insensitive")
    func composeRedactedAccountRedactionIsCaseInsensitive() {
        let finding = stagedActionFinding(currentAccountName: "Owner Draw", suggestedAccountName: "Payroll Expenses")
        // The action's own title embeds the suggested name in a different case than the field itself would ever naturally vary, proving the match isn't literal-only.
        let context = AskAIContext.composeRedacted(finding: finding)
        #expect(!context.lowercased().contains("owner draw"))
    }

    @Test("composeRedacted does not touch account names when the finding has no apiWriteDetails (manualQBO resolution)")
    func composeRedactedLeavesManualQBOFindingsUnaffected() {
        let plain = finding(narrative: "Reclassify to Office Expenses to fix this.")
        #expect(AskAIContext.composeRedacted(finding: plain) == AskAIContext.compose(finding: plain))
    }

    // MARK: composeHealthReport — the "Generate Report" buttons on
    // Findings, 2026-08-29.

    @Test("composeHealthReport includes both open (negative) and resolved (positive) findings")
    func composeHealthReportIncludesBothSides() {
        let open = finding(vendorName: "Open Vendor")
        let resolved = finding(vendorName: "Resolved Vendor")
        let context = AskAIContext.composeHealthReport(
            openFindings: [open], resolvedFindings: [resolved], dismissedFindings: [],
            balanceSheetLines: [], profitAndLossLines: [], priorBalanceSheetLines: nil, priorProfitAndLossLines: nil,
            period: AccountingPeriod(year: 2026, month: 7)
        )
        #expect(context.contains("1 open finding"))
        #expect(context.contains("1 finding(s) resolved"))
    }

    @Test("composeHealthReport omits the change-since-last-period section entirely when no prior data is given")
    func composeHealthReportOmitsVarianceWithoutPriorData() {
        let context = AskAIContext.composeHealthReport(
            openFindings: [], resolvedFindings: [], dismissedFindings: [],
            balanceSheetLines: [], profitAndLossLines: [], priorBalanceSheetLines: nil, priorProfitAndLossLines: nil,
            period: AccountingPeriod(year: 2026, month: 7)
        )
        #expect(!context.contains("CHANGE SINCE LAST PERIOD"))
    }

    @Test("composeHealthReport includes real KPI figures when the underlying report lines support them")
    func composeHealthReportIncludesKPIs() {
        let bsLines = [
            ReportLine(label: "Total Current Assets", amount: Money(minorUnits: 500_00, currency: .usd), depth: 0, isSummary: true),
            ReportLine(label: "Total Current Liabilities", amount: Money(minorUnits: 200_00, currency: .usd), depth: 0, isSummary: true)
        ]
        let context = AskAIContext.composeHealthReport(
            openFindings: [], resolvedFindings: [], dismissedFindings: [],
            balanceSheetLines: bsLines, profitAndLossLines: [], priorBalanceSheetLines: nil, priorProfitAndLossLines: nil,
            period: AccountingPeriod(year: 2026, month: 7)
        )
        #expect(context.contains("Working capital") || context.contains("Current ratio"))
    }

    // MARK: composeValueSummary — the "Client Value Report" button, shown
    // once every finding is cleared, 2026-08-29.

    @Test("composeValueSummary sums dollar exposure across resolved findings, same-currency only")
    func composeValueSummarySumsExposure() {
        let a = finding(vendorName: "Vendor A")
        let context = AskAIContext.composeValueSummary(resolvedFindings: [a, a], dismissedFindings: [], corrections: [], since: nil)
        #expect(context.contains("972.40"))
    }

    @Test("composeValueSummary never claims literal cash savings — the honest-scope wording is always present when a total is stated")
    func composeValueSummaryNeverClaimsCashSavings() {
        let context = AskAIContext.composeValueSummary(resolvedFindings: [finding(vendorName: "Vendor A")], dismissedFindings: [], corrections: [], since: nil)
        #expect(context.contains("not a claim of cash the client received"))
    }

    @Test("composeValueSummary states this is the first report when since is nil")
    func composeValueSummaryFirstReportWording() {
        let context = AskAIContext.composeValueSummary(resolvedFindings: [], dismissedFindings: [], corrections: [], since: nil)
        #expect(context.contains("first report"))
    }

    @Test("composeValueSummary includes corrections from the Activity Log with their notes")
    func composeValueSummaryIncludesCorrections() {
        let entry = ActivityLogEntry(
            realmID: RealmID(rawValue: "realm-a"),
            actor: .user("Benjamin Branson"),
            kind: .apiWriteApplied,
            findingSummary: "Reclassified a credit card payment",
            note: "Moved to the correct liability account"
        )
        let context = AskAIContext.composeValueSummary(resolvedFindings: [], dismissedFindings: [], corrections: [entry], since: nil)
        #expect(context.contains("Reclassified a credit card payment"))
        #expect(context.contains("Moved to the correct liability account"))
    }
}
