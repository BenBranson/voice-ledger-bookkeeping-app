import Foundation

/// `VL-PERSONAL-001`. docs/phase-0/08_RULE_ENGINE.md's backlog table:
/// "Possible personal expense or owner draw." Same keyword-matching
/// pattern as `AvoidableFeeRule`/`PayrollLumpSumRule` — checks the vendor
/// name AND memo (both already synced on every `LedgerTransaction`, no
/// new capability needed) for specific, unambiguous terms, case-
/// insensitive. Deliberately narrow: a real vendor legitimately named
/// "Personal Touch Cleaning" or "Draper's Hardware" should never match —
/// every keyword here names the CONCEPT of an owner/personal
/// disbursement, not a word common enough to appear in an ordinary
/// business name.
public enum PersonalExpenseRule: Rule {
    static let keywords: [String] = [
        "owner draw", "owner's draw", "owners draw", "member draw",
        "shareholder distribution", "owner distribution", "personal expense",
        "personal use", "draw to owner", "distribution to owner"
    ]

    public static let identity = RuleIdentity(
        id: RuleID(rawValue: "VL-PERSONAL-001"),
        version: RuleVersion(major: 1, minor: 0, patch: 0),
        title: "Possible personal expense or owner draw",
        category: .personalExpenseOrOwnerDraw,
        ruleClass: .categorization,
        page: .cleanupAssessment,
        accountingPrinciple: "A personal expense or owner draw recorded as a business expense overstates deductible expenses and understates the owner's equity withdrawal — it needs to be reclassified to an equity/draw account, not left in ordinary expenses, both for accurate books and for tax purposes.",
        sourceDependencies: [SourceDependency(entity: .purchase)]
    )

    public static let requirements = DataRequirements(
        entities: [.purchase],
        requiredCoverage: .complete
    )

    public static func evaluate(_ input: NormalizedDataSet, context: RuleContext) -> RuleOutcome {
        var findings: [Finding] = []
        // A draw already coded entirely to equity is correct, not a finding
        // (false positive found 2026-09-29 against the seeded owner draws).
        let equityAccountIDs = Set(input.accounts.filter { $0.accountType == .equity }.map(\.id))

        for transaction in input.transactions.sorted(by: { $0.id < $1.id }) {
            guard !transaction.isVoided else { continue }
            if !transaction.lineAccountIDs.isEmpty && transaction.lineAccountIDs.allSatisfy(equityAccountIDs.contains) { continue }
            let haystack = [transaction.vendorName, transaction.noteText]
                .compactMap { $0?.lowercased() }
                .joined(separator: " ")
            guard keywords.contains(where: { haystack.contains($0) }) else { continue }
            guard transaction.totalAmount >= context.materiality.absoluteFloor else { continue }

            let findingID = FindingIDGenerator.makeID(
                ruleID: identity.id,
                ruleVersion: identity.version,
                realmID: input.realmID,
                period: input.period,
                sortedAffectedIDs: [transaction.id]
            )
            if context.dismissedFindingIDs.contains(findingID) { continue }

            let procedure = GuidedProcedure(
                steps: [
                    "Open the transaction in QuickBooks Online and confirm whether this is genuinely a personal expense or owner draw",
                    "If it is, recode the line to the appropriate Owner's Draw / equity account rather than a business expense account",
                    "If it's a recurring pattern, consider setting up a standing recurring transaction template so it's coded correctly going forward"
                ],
                pitfalls: [
                    "Some vendor names or memos legitimately contain these words without describing an actual owner draw — confirm the real nature of the transaction before recoding it",
                    "Recoding to equity changes the business's reported net income and the owner's equity balance — make sure this is the correct call, not a guess"
                ],
                doneCriteria: "The transaction is either confirmed as a genuine business expense (left as-is), or recoded to the correct equity/draw account"
            )

            let action = ProposedAction(
                id: "review-personal-expense",
                title: "Review this transaction for personal expense or owner draw",
                resolution: .manualQBO,
                guidedProcedure: procedure,
                consequences: [
                    .reporting("\(transaction.totalAmount) is currently recorded as a business expense; recoding it would reduce expenses and increase the owner's equity draw by the same amount")
                ],
                reversal: .reversibleManually(procedure: "Recode the transaction back to its original account in QBO if this was reclassified in error")
            )

            findings.append(Finding(
                id: findingID,
                ruleID: identity.id,
                ruleVersion: identity.version,
                realmID: input.realmID,
                period: input.period,
                title: "Possible personal expense or owner draw — \(transaction.vendorName ?? "unknown vendor"), \(transaction.totalAmount)",
                severity: Severity.derive(dollarExposure: transaction.totalAmount, materiality: context.materiality),
                confidence: .medium,
                dollarExposure: transaction.totalAmount,
                evidence: [EvidenceItem(
                    transactionID: transaction.id,
                    highlightedFields: ["vendorName", "memo"],
                    fieldValues: [
                        "vendorName": transaction.vendorName ?? "unknown",
                        "memo": transaction.noteText,
                        "amount": transaction.totalAmount.description,
                        "date": transaction.txnDate.formatted
                    ]
                )],
                proposedActions: [action],
                provenance: [transaction.provenance],
                vendorName: transaction.vendorName,
                narrative: "A \(transaction.totalAmount) transaction\(transaction.vendorName.map { " from \($0)" } ?? "") on \(transaction.txnDate.formatted) has a vendor name or memo suggesting a personal expense or owner draw, not an ordinary business expense.",
                riskIfIgnored: "If this is genuinely personal, it stays overstating business expenses (and understating the owner's equity draw) by \(transaction.totalAmount) until it's recoded."
            ))
        }

        guard findings.isEmpty else {
            return .findings(findings)
        }
        guard case .complete = input.coverage else {
            return .cannotEvaluate(.partialCoverage(reason: {
                if case .partial(let reason) = input.coverage { return reason }
                return "unknown"
            }()))
        }
        return .pass(coverage: input.coverage, checkedCount: input.transactions.count)
    }
}
