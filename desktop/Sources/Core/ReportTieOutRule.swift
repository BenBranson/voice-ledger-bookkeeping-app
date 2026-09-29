import Foundation

/// `VL-REPORT-TIE-001`. docs/phase-0/08_RULE_ENGINE.md's backlog table:
/// "checked live 2026-08-17: `TrialBalance`'s own debit/credit total is
/// tautologically always equal... a genuine cross-report tie-out (e.g.
/// Aged Receivables total vs. Balance Sheet's A/R line) would need two
/// different report parsers built in one pass, not attempted yet." Built
/// 2026-08-18 once Balance Sheet, Aged Receivables, and Aged Payables were
/// all available in the same `NormalizedDataSet`.
///
/// **What this actually checks**: the Balance Sheet's A/R balance is
/// supposed to be the sum of every unpaid invoice — which is exactly what
/// Aged Receivables enumerates. If they don't tie out, something posted
/// directly to the A/R account outside the invoice/payment flow (a manual
/// journal entry, a miscoded deposit) — real money the Aged Receivables
/// report can't explain. Same logic for A/P against unpaid bills.
///
/// **Matches accounts by real data, not a guessed literal label**: rather
/// than hardcoding "Accounts Receivable (A/R)" (QBO's default English
/// name, which a company can rename), this cross-references
/// `input.accounts` for accounts whose `accountType` is actually
/// `.accountsReceivable`/`.accountsPayable`, then matches the Balance
/// Sheet lines by THEIR real names — correct even if the account was
/// renamed, and correct in the (rare) case of multiple A/R accounts.
public enum ReportTieOutRule: Rule {
    public static let identity = RuleIdentity(
        id: RuleID(rawValue: "VL-REPORT-TIE-001"),
        version: RuleVersion(major: 1, minor: 0, patch: 0),
        title: "Balance Sheet A/R or A/P doesn't tie to the aging report",
        category: .reportTieOut,
        ruleClass: .categorization,
        page: .cleanupAssessment,
        accountingPrinciple: "The Balance Sheet's A/R balance should always equal the sum of every unpaid invoice on Aged Receivables (and A/P to Aged Payables) — they're two views of the same underlying open transactions. A mismatch means something posted directly to the receivable/payable account outside the normal invoice-and-payment (or bill-and-payment) flow, and the aging report can no longer explain what's actually owed.",
        sourceDependencies: [SourceDependency(entity: .report), SourceDependency(entity: .account)]
    )

    public static let requirements = DataRequirements(
        entities: [.report, .account],
        requiredCoverage: .complete
    )

    public static func evaluate(_ input: NormalizedDataSet, context: RuleContext) -> RuleOutcome {
        guard !input.balanceSheetLines.isEmpty else {
            return .cannotEvaluate(.partialCoverage(reason: "Balance Sheet report not loaded for this period. Visit the Balance Sheet page (or resync) to run this check."))
        }
        guard !input.agedReceivablesLines.isEmpty || !input.agedPayablesLines.isEmpty else {
            return .cannotEvaluate(.partialCoverage(reason: "No aging report loaded. Visit the Aged Receivables or Aged Payables page (or resync) to run this check."))
        }

        var findings: [Finding] = []

        if !input.agedReceivablesLines.isEmpty,
           let finding = Self.tieOutFinding(
               input: input,
               context: context,
               accountType: .accountsReceivable,
               agingLines: input.agedReceivablesLines,
               reportLabel: "Aged Receivables",
               affectedIDSuffix: "ar-tie"
           ) {
            findings.append(finding)
        }

        if !input.agedPayablesLines.isEmpty,
           let finding = Self.tieOutFinding(
               input: input,
               context: context,
               accountType: .accountsPayable,
               agingLines: input.agedPayablesLines,
               reportLabel: "Aged Payables",
               affectedIDSuffix: "ap-tie"
           ) {
            findings.append(finding)
        }

        guard !findings.isEmpty else {
            return .pass(coverage: input.coverage, checkedCount: 1)
        }
        return .findings(findings)
    }

    private static func tieOutFinding(
        input: NormalizedDataSet,
        context: RuleContext,
        accountType: LedgerAccountType,
        agingLines: [AgingLine],
        reportLabel: String,
        affectedIDSuffix: String
    ) -> Finding? {
        let matchingAccountNames = Set(input.accounts.filter { $0.accountType == accountType }.map(\.name))
        guard !matchingAccountNames.isEmpty else { return nil }

        let balanceSheetTotal = input.balanceSheetLines
            .filter { !$0.isSummary && matchingAccountNames.contains($0.label) }
            .compactMap(\.amount)
            .reduce(Money.zero, +)

        guard let agingGrandTotal = agingLines.last(where: { $0.isSummary })?.total else { return nil }

        let difference = balanceSheetTotal - agingGrandTotal
        let exposure = difference.minorUnits < 0 ? Money(minorUnits: -difference.minorUnits, currency: difference.currency) : difference
        guard exposure >= context.materiality.absoluteFloor else { return nil }

        let severity = Severity.derive(dollarExposure: exposure, materiality: context.materiality)
        let findingID = FindingIDGenerator.makeID(
            ruleID: identity.id,
            ruleVersion: identity.version,
            realmID: input.realmID,
            period: input.period,
            sortedAffectedIDs: [affectedIDSuffix]
        )
        if context.dismissedFindingIDs.contains(findingID) { return nil }

        let accountLabel = accountType == .accountsReceivable ? "A/R" : "A/P"
        let procedure = GuidedProcedure(
            steps: [
                "Open QuickBooks Online → Reports → \(reportLabel) and note the total shown",
                "Open the Balance Sheet and note the \(accountLabel) balance for the same date",
                "Run a Transaction Detail report filtered to the \(accountLabel) account for the period, sorted by transaction type",
                "Look for Journal Entries or Deposits posted directly to \(accountLabel) — these don't appear on \(reportLabel) but do affect the Balance Sheet",
                "Reclassify or reverse anything found that shouldn't have hit \(accountLabel) directly"
            ],
            pitfalls: [
                "A timing difference (report run at slightly different moments) can cause a tiny, immaterial gap — this check already filters those out below the materiality floor",
                "Multiple \(accountLabel)-type accounts are rare but possible — this check sums all of them, so a mismatch means the combined total is off, not necessarily a single account"
            ],
            doneCriteria: "Balance Sheet \(accountLabel) and \(reportLabel)'s total agree, or the difference has been identified and documented as expected"
        )

        let action = ProposedAction(
            id: "review-report-tie-out-\(affectedIDSuffix)",
            title: "Reconcile Balance Sheet \(accountLabel) against \(reportLabel)",
            resolution: .manualQBO,
            guidedProcedure: procedure,
            consequences: [
                .reporting("\(exposure) of the \(accountLabel) balance isn't explained by any open invoice/bill on \(reportLabel)"),
                .auditTrail("Voice Ledger records your attestation; QBO's own reports remain authoritative")
            ],
            reversal: .reversibleManually(procedure: "Reclassify or reverse the transaction found to be posted directly to the account, once identified")
        )

        return Finding(
            id: findingID,
            ruleID: identity.id,
            ruleVersion: identity.version,
            realmID: input.realmID,
            period: input.period,
            title: "Balance Sheet \(accountLabel) doesn't tie to \(reportLabel) — off by \(exposure)",
            severity: severity,
            confidence: .high,
            dollarExposure: exposure,
            evidence: [EvidenceItem(
                transactionID: affectedIDSuffix,
                highlightedFields: ["amount"],
                fieldValues: ["amount": exposure.description, "balanceSheetTotal": balanceSheetTotal.description, "agingTotal": agingGrandTotal.description]
            )],
            proposedActions: [action],
            provenance: [.qboAPI(readAt: Date())],
            narrative: TranspositionHint.appending(to: "The Balance Sheet's \(accountLabel) balance (\(balanceSheetTotal)) is off by \(exposure) from \(reportLabel)'s total (\(agingGrandTotal)) — something likely posted directly to \(accountLabel) outside the normal invoice/bill flow.", difference: exposure),
            riskIfIgnored: "This \(exposure) stays unexplained by any open invoice or bill on \(reportLabel) until the direct posting is found and reclassified."
        )
    }
}
