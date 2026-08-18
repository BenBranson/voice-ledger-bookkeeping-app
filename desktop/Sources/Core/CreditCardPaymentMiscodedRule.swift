import Foundation

/// `VL-CC-PAYMENT-001`. docs/backlog/CLEANUP_MODE.md §2.1, the highest-value
/// cleanup rule identified there: *"This is a huge no-no. You never want the
/// payment to a credit card be sent to an expense account."* QBO's own AI
/// was observed suggesting exactly this error (an American Express payment
/// coded to "general business expenses").
///
/// **Why this double-counts expenses:** a credit card's own charges are
/// already expensed as they post. If the payment that settles the card
/// balance is ALSO coded to an expense account, the same spending is
/// expensed twice — once per charge, once again per payment.
///
/// **Design decision: `ruleClass: .relationship`, not `.categorization`.**
/// docs/backlog/REDDIT_FEEDBACK_ASSESSMENT.md item 1 identifies this as
/// branch 2 of the Transaction Relationship Guard ("is it a credit-card
/// payment — balance sheet, never an expense?") and flags that it
/// *subsumes* this rule. `docs/phase-0/08_RULE_ENGINE.md` §8.8 recorded that
/// overlap as unresolved. Implementing this rule now is the resolution:
/// it answers "is this the right KIND of transaction" before any
/// categorization question, which is exactly what §8.2a's relationship
/// gating exists for — and it's the first real (non-fixture) rule to use
/// that gating path.
public enum CreditCardPaymentMiscodedRule: Rule {
    /// Case-insensitive substring match against the vendor/payee name.
    /// Not exhaustive — a real client's card issuer might not be in this
    /// list, which is exactly why the *structural* match (vendor name
    /// equals a real Credit Card-type account name in this client's own
    /// chart of accounts) is checked first and rated higher confidence.
    static let cardIssuerKeywords = [
        "amex", "american express", "visa", "mastercard", "master card",
        "discover", "capital one", "chase card", "credit card"
    ]

    public static let identity = RuleIdentity(
        id: RuleID(rawValue: "VL-CC-PAYMENT-001"),
        version: RuleVersion(major: 1, minor: 0, patch: 0),
        title: "Credit card payment coded to an expense account",
        category: .creditCardPaymentMiscoded,
        ruleClass: .relationship,
        page: .cleanupAssessment,
        accountingPrinciple: "A payment to a credit card settles a liability already incurred when each charge posted — it is a transfer between a liability account and an asset account, never an expense. Coding the payment itself to an expense account double-counts spending that was already expensed once, per charge.",
        sourceDependencies: [SourceDependency(entity: .purchase), SourceDependency(entity: .account)]
    )

    public static let requirements = DataRequirements(
        entities: [.purchase, .account],
        requiredCoverage: .complete
    )

    public static func evaluate(_ input: NormalizedDataSet, context: RuleContext) -> RuleOutcome {
        let purchases = input.transactions.filter { $0.entityKind == .purchase && !$0.isVoided }
        let accountsByID = Dictionary(uniqueKeysWithValues: input.accounts.map { ($0.id, $0) })
        let creditCardAccountsByLowercasedName = Dictionary(
            input.accounts.filter { $0.accountType == .creditCard }.map { ($0.name.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let creditCardAccountNames = Set(creditCardAccountsByLowercasedName.keys)

        var findings: [Finding] = []

        for purchase in purchases {
            guard let vendor = purchase.vendorName, !vendor.isEmpty else { continue }
            let vendorLower = vendor.lowercased()

            let isStructuralMatch = creditCardAccountNames.contains(vendorLower)
            let isKeywordMatch = cardIssuerKeywords.contains { vendorLower.contains($0) }
            guard isStructuralMatch || isKeywordMatch else { continue }

            // Every line must be coded to an expense-like account for this
            // to be the error — a payment split across an expense line AND
            // a legitimate liability line isn't the same mistake, and a
            // transaction with no line-account data at all can't be judged
            // (missing data, not a clean pass — excluded, not asserted).
            guard !purchase.lineAccountIDs.isEmpty else { continue }
            let lineAccounts = purchase.lineAccountIDs.compactMap { accountsByID[$0] }
            guard lineAccounts.count == purchase.lineAccountIDs.count else { continue } // some account unresolvable — don't guess
            guard lineAccounts.allSatisfy({ $0.accountType.isExpenseLike }) else { continue }

            guard purchase.totalAmount >= context.materiality.absoluteFloor else { continue }

            let confidence: Confidence = isStructuralMatch ? .high : .medium
            let severity = Severity.derive(dollarExposure: purchase.totalAmount, materiality: context.materiality)

            let findingID = FindingIDGenerator.makeID(
                ruleID: identity.id,
                ruleVersion: identity.version,
                realmID: input.realmID,
                period: input.period,
                sortedAffectedIDs: [purchase.id]
            )
            if context.dismissedFindingIDs.contains(findingID) { continue }

            let expenseAccountNames = lineAccounts.map(\.name).joined(separator: ", ")
            let procedure = GuidedProcedure(
                steps: [
                    "Open QuickBooks Online",
                    "Find this payment to \(vendor), dated \(purchase.txnDate.year)-\(purchase.txnDate.month)-\(purchase.txnDate.day), \(purchase.totalAmount)",
                    "Confirm this is genuinely a credit card payment, not a purchase made using a card matching this name coincidentally",
                    "Change the category from \(expenseAccountNames) to the correct Credit Card liability account for \(vendor)",
                    "If no matching Credit Card account exists yet, that account needs to be created first (Chart of Accounts Cleanup)"
                ],
                pitfalls: [
                    "Don't reclassify if this vendor name match is a coincidence (e.g. a store named similarly to a card issuer, not the issuer itself)",
                    "Recategorizing changes which account the money is recorded against — verify the correct Credit Card account exists first"
                ],
                doneCriteria: "The transaction is coded to the credit card's own liability account, not an expense account"
            )

            // A staged API fix is only offered when the correct target
            // account is unambiguous end-to-end: a structural (not keyword)
            // vendor match, exactly one line (so there's no question which
            // line to reclassify), a resolvable QBO Line.Id and SyncToken
            // (both required by `updatePurchaseLineAccount`), and a real
            // Credit Card account whose name matches the vendor. Anything
            // short of that stays `.manualQBO` — a guided procedure, not an
            // auto-suggested write.
            var apiWriteDetails: StagedAPIWriteDetails?
            if isStructuralMatch,
               purchase.lines.count == 1,
               let syncToken = purchase.syncToken,
               let targetAccount = creditCardAccountsByLowercasedName[vendorLower] {
                let line = purchase.lines[0]
                let currentAccountName = accountsByID[line.accountID]?.name ?? line.accountID
                apiWriteDetails = StagedAPIWriteDetails(
                    purchaseID: purchase.id,
                    lineID: line.id,
                    expectedSyncToken: syncToken,
                    currentAccountID: line.accountID,
                    currentAccountName: currentAccountName,
                    suggestedAccountID: targetAccount.id,
                    suggestedAccountName: targetAccount.name
                )
            }

            let action = ProposedAction(
                id: "recategorize-to-credit-card-liability",
                title: "Recategorize to the credit card liability account",
                resolution: apiWriteDetails != nil ? .stagedAPI : .manualQBO,
                guidedProcedure: procedure,
                consequences: [
                    .reporting("expenses decrease by \(purchase.totalAmount) once corrected — this spending was already counted when the card's own charges posted"),
                    .reconciliation("the credit card account's balance becomes accurate once the payment is coded against it"),
                    .auditTrail("Voice Ledger records your attestation; QBO's own record of the change is authoritative")
                ],
                reversal: .reversibleManually(procedure: "Change the category back in QBO if done in error"),
                apiWriteDetails: apiWriteDetails
            )

            findings.append(Finding(
                id: findingID,
                ruleID: identity.id,
                ruleVersion: identity.version,
                realmID: input.realmID,
                period: input.period,
                title: "Credit card payment coded to \(expenseAccountNames) — \(purchase.totalAmount)",
                severity: severity,
                confidence: confidence,
                dollarExposure: purchase.totalAmount,
                evidence: [EvidenceItem(transactionID: purchase.id, highlightedFields: ["vendor", "lineAccount"])],
                proposedActions: [action],
                provenance: [purchase.provenance]
            ))
        }

        if findings.isEmpty {
            guard case .complete = input.coverage else {
                return .cannotEvaluate(.partialCoverage(reason: {
                    if case .partial(let reason) = input.coverage { return reason }
                    return "unknown"
                }()))
            }
            return .pass(coverage: input.coverage, checkedCount: purchases.count)
        }
        return .findings(findings)
    }
}
