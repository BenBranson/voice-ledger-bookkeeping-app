import Foundation

/// `VL-RELATIONSHIP-003`. docs/backlog/REDDIT_FEEDBACK_ASSESSMENT.md's
/// Transaction Relationship Guard, branch 3: "Is it a bank-to-bank
/// transfer (never income or expense)?" — the second branch of that tree
/// to ship, after `VL-CC-PAYMENT-001` (branch 2). Same `ruleClass:
/// .relationship` resolution that rule's own doc comment established:
/// this answers "is this even the right KIND of transaction" before any
/// categorization rule runs on it, so its findings gate those rules
/// (§8.2a) rather than letting both fire on the same transaction.
///
/// **The structural signal, mirroring `VL-CC-PAYMENT-001`'s exact
/// mechanism**: a Purchase whose line is coded to another BANK-type
/// account (not an expense/asset/liability account) is, structurally,
/// money moving from one of the company's own bank accounts into
/// another — a transfer — recorded as if it were a purchase/expense
/// instead of using QBO's own Transfer entity. No vendor-name keyword
/// list is needed here (unlike `VL-CC-PAYMENT-001`'s issuer-name
/// matching) — coding a line to a Bank-type account at all is itself the
/// structural anomaly, since a real expense is never coded there.
public enum BankTransferMiscodedRule: Rule {
    public static let identity = RuleIdentity(
        id: RuleID(rawValue: "VL-RELATIONSHIP-003"),
        version: RuleVersion(major: 1, minor: 0, patch: 0),
        title: "Purchase looks like a bank-to-bank transfer, not an expense",
        category: .bankTransferMiscoded,
        ruleClass: .relationship,
        page: .cleanupAssessment,
        accountingPrinciple: "Moving money between two of the company's own bank accounts isn't income or an expense — it's a transfer, and QBO has a dedicated Transfer entity for it. A Purchase whose line is coded to another bank account is that same movement recorded the wrong way: it can inflate apparent spending activity and miscode what should be a simple balance-sheet-to-balance-sheet movement.",
        sourceDependencies: [SourceDependency(entity: .purchase), SourceDependency(entity: .account)]
    )

    public static let requirements = DataRequirements(
        entities: [.purchase, .account],
        requiredCoverage: .complete
    )

    public static func evaluate(_ input: NormalizedDataSet, context: RuleContext) -> RuleOutcome {
        let purchases = input.transactions.filter { $0.entityKind == .purchase && !$0.isVoided }
        let accountsByID = Dictionary(uniqueKeysWithValues: input.accounts.map { ($0.id, $0) })

        var findings: [Finding] = []
        for purchase in purchases {
            guard !purchase.lineAccountIDs.isEmpty else { continue }
            let lineAccounts = purchase.lineAccountIDs.compactMap { accountsByID[$0] }
            guard lineAccounts.count == purchase.lineAccountIDs.count else { continue } // some account unresolvable — don't guess
            guard lineAccounts.allSatisfy({ $0.accountType == .bank }) else { continue }
            // A line coded to the SAME account the purchase was paid from
            // is nonsensical data, not a transfer signal — excluded rather
            // than guessed at.
            guard !lineAccounts.contains(where: { $0.id == purchase.paymentAccountID }) else { continue }

            guard purchase.totalAmount >= context.materiality.absoluteFloor else { continue }

            let findingID = FindingIDGenerator.makeID(
                ruleID: identity.id,
                ruleVersion: identity.version,
                realmID: input.realmID,
                period: input.period,
                sortedAffectedIDs: [purchase.id]
            )
            if context.dismissedFindingIDs.contains(findingID) { continue }

            let targetAccountNames = lineAccounts.map(\.name).joined(separator: ", ")
            let sourceAccountName = purchase.paymentAccountID.flatMap { accountsByID[$0]?.name } ?? "the payment account"

            let procedure = GuidedProcedure(
                steps: [
                    "Open this \(purchase.totalAmount) transaction dated \(purchase.txnDate.formatted), currently coded to \(targetAccountNames)",
                    "Confirm it's genuinely a movement of money from \(sourceAccountName) into \(targetAccountNames), both your own accounts",
                    "Delete this Purchase and re-enter it using QBO's own Transfer feature (Banking → Transfer) instead",
                    "If it's NOT actually a transfer (e.g. it's a real payment coded to the wrong account by mistake), recode the line to the correct expense or liability account instead"
                ],
                pitfalls: [
                    "Don't just change the category on this transaction — a Purchase and a Transfer are different QBO entities entirely; the correct fix re-enters it as a Transfer, not a recategorized Purchase",
                    "Confirm both accounts genuinely belong to this company before treating this as a transfer — a payment to an account with a similar name that ISN'T yours would be a real expense, not this pattern"
                ],
                doneCriteria: "The movement is recorded as a QBO Transfer between the two accounts, not a Purchase"
            )

            let action = ProposedAction(
                id: "recode-as-bank-transfer",
                title: "Re-enter as a bank transfer, not a purchase",
                resolution: .manualQBO,
                guidedProcedure: procedure,
                consequences: [
                    .reporting("Removes \(purchase.totalAmount) from spending activity once corrected — this was never a real expense"),
                    .auditTrail("Voice Ledger records your attestation; QBO's own record of the re-entry is authoritative")
                ],
                reversal: .reversibleManually(procedure: "The original Purchase can be re-entered in QBO if the transfer re-entry was done in error")
            )

            findings.append(Finding(
                id: findingID,
                ruleID: identity.id,
                ruleVersion: identity.version,
                realmID: input.realmID,
                period: input.period,
                title: "Looks like a bank transfer coded as a purchase — \(purchase.totalAmount)",
                severity: Severity.derive(dollarExposure: purchase.totalAmount, materiality: context.materiality),
                confidence: .medium,
                dollarExposure: purchase.totalAmount,
                evidence: [EvidenceItem(
                    transactionID: purchase.id,
                    highlightedFields: ["lineAccount"],
                    fieldValues: [
                        "amount": purchase.totalAmount.description,
                        "date": purchase.txnDate.formatted,
                        "sourceAccount": sourceAccountName,
                        "targetAccount": targetAccountNames
                    ]
                )],
                proposedActions: [action],
                provenance: [purchase.provenance],
                vendorName: purchase.vendorName,
                narrative: "A \(purchase.totalAmount) transaction on \(purchase.txnDate.formatted) is coded to \(targetAccountNames), another bank account — this looks like money moving between your own accounts, which should be a Transfer, not a Purchase.",
                riskIfIgnored: "Left as a Purchase, this \(purchase.totalAmount) inflates apparent spending activity and isn't recorded as the simple account-to-account movement it actually is."
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
        return .pass(coverage: input.coverage, checkedCount: purchases.count)
    }
}
