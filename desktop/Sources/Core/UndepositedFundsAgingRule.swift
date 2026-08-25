import Foundation

/// `VL-BS-UNDEP-001`. docs/phase-0/08_RULE_ENGINE.md §8.8 (page 8) — the
/// backlog's own note said this needed "Payment/Deposit entity reads, not
/// in the catalog." Both now exist. A `Payment` still sitting in
/// Undeposited Funds well past its own date usually means someone forgot to
/// actually deposit it — the money hasn't reached the bank yet, and the
/// account balance overstates available cash.
///
/// **Why a Payment-only check would be wrong, verified live before this was
/// built:** a real sandbox Deposit (Id 121) was found sweeping up 5
/// Payments, one dated 4 calendar days before the Deposit itself. A rule
/// that only looked at `Payment.TxnDate` vs "today" would have flagged that
/// payment as stuck during the days between its own date and the (already
/// real, already correct) deposit — a false positive on completely normal
/// activity. `Deposit.Line[].LinkedTxn[]` is checked FIRST to exclude any
/// Payment that has actually been swept, no matter how long ago its own
/// `TxnDate` was.
public enum UndepositedFundsAgingRule: Rule {
    public static let identity = RuleIdentity(
        id: RuleID(rawValue: "VL-BS-UNDEP-001"),
        version: RuleVersion(major: 1, minor: 0, patch: 0),
        title: "Payment still sitting in Undeposited Funds",
        category: .agedUndepositedFunds,
        ruleClass: .categorization,
        page: .cleanupAssessment,
        accountingPrinciple: "A Payment recorded in QuickBooks but not yet included in a bank Deposit sits in Undeposited Funds — a real asset, but not yet cash in the bank. Left there too long, it usually means the deposit was never actually made (or was made outside QBO and never recorded), which overstates readily available cash.",
        sourceDependencies: [SourceDependency(entity: .account)]
    )

    public static let requirements = DataRequirements(
        entities: [.account],
        requiredCoverage: .complete
    )

    /// Calendar days a Payment may sit in Undeposited Funds before this
    /// rule considers it worth a look — a real bank deposit often takes a
    /// few business days in practice, so this is deliberately looser than
    /// same-week.
    private static let agingThresholdDays = 7

    static let undepositedFundsAccountSubType = "UndepositedFunds"

    public static func evaluate(_ input: NormalizedDataSet, context: RuleContext) -> RuleOutcome {
        guard let undepositedFundsAccountID = input.accounts.first(where: { $0.accountSubType == undepositedFundsAccountSubType })?.id else {
            // No Undeposited Funds account in this client's chart of
            // accounts at all — genuinely nothing to check, not a coverage
            // gap. QBO creates this account by default, but a heavily
            // customized or very old company file could lack it.
            guard case .complete = input.coverage else {
                return .cannotEvaluate(.partialCoverage(reason: {
                    if case .partial(let reason) = input.coverage { return reason }
                    return "unknown"
                }()))
            }
            return .pass(coverage: input.coverage, checkedCount: 0)
        }

        let sweptPaymentIDs = Set(input.deposits.flatMap(\.linkedPaymentIDs))
        let candidates = input.transactions.filter {
            $0.entityKind == .payment && !$0.isVoided && $0.paymentAccountID == undepositedFundsAccountID
        }

        var findings: [Finding] = []

        for payment in candidates {
            guard !sweptPaymentIDs.contains(payment.id) else { continue }
            let ageDays = AccountingDate.daysBetween(payment.txnDate, context.asOfDate)
            guard ageDays > agingThresholdDays else { continue }
            guard payment.totalAmount >= context.materiality.absoluteFloor else { continue }

            let findingID = FindingIDGenerator.makeID(
                ruleID: identity.id,
                ruleVersion: identity.version,
                realmID: input.realmID,
                period: input.period,
                sortedAffectedIDs: [payment.id]
            )
            if context.dismissedFindingIDs.contains(findingID) { continue }

            let procedure = GuidedProcedure(
                steps: [
                    "Open QuickBooks Online, go to Bookkeeping > Transactions > Bank deposits",
                    "Find the Payment from \(payment.vendorName ?? "this customer"), \(payment.txnDate.formatted), \(payment.totalAmount)",
                    "Confirm whether this was actually deposited at the bank",
                    "If yes: record the Deposit in QBO to move it out of Undeposited Funds",
                    "If no: determine why — a forgotten deposit, or a Payment entered in error"
                ],
                pitfalls: [
                    "Don't record a Deposit for money that was never actually deposited at the bank — that creates a real discrepancy against the bank statement"
                ],
                doneCriteria: "The Payment either appears on a real Deposit in QBO, or is confirmed/corrected as entered in error"
            )

            let action = ProposedAction(
                id: "investigate-undeposited-payment",
                title: "Confirm and record the missing deposit",
                resolution: .manualQBO,
                guidedProcedure: procedure,
                consequences: [
                    .reconciliation("Undeposited Funds balance becomes accurate once the deposit is recorded or the payment corrected"),
                    .auditTrail("Voice Ledger records your attestation; the Deposit itself is QBO's own record")
                ],
                reversal: .reversibleManually(procedure: "A recorded Deposit can itself be edited or deleted in QBO if entered in error")
            )

            findings.append(Finding(
                id: findingID,
                ruleID: identity.id,
                ruleVersion: identity.version,
                realmID: input.realmID,
                period: input.period,
                title: "Payment still in Undeposited Funds after \(ageDays) days — \(payment.vendorName ?? "unknown"), \(payment.totalAmount)",
                severity: Severity.derive(dollarExposure: payment.totalAmount, materiality: context.materiality),
                confidence: .high,
                dollarExposure: payment.totalAmount,
                evidence: [EvidenceItem(
                    transactionID: payment.id,
                    highlightedFields: ["txnDate", "amount"],
                    fieldValues: ["txnDate": payment.txnDate.formatted, "amount": payment.totalAmount.description, "vendor": payment.vendorName ?? "unknown", "daysAged": "\(ageDays)"]
                )],
                proposedActions: [action],
                provenance: [payment.provenance],
                vendorName: payment.vendorName,
                narrative: "A \(payment.totalAmount) payment\(payment.vendorName.map { " from \($0)" } ?? "") dated \(payment.txnDate.formatted) has sat in Undeposited Funds for \(ageDays) days with no matching bank Deposit — it may have been forgotten.",
                riskIfIgnored: "Available cash stays overstated by \(payment.totalAmount) in your books until this is deposited (or confirmed as entered in error)."
            ))
        }

        if findings.isEmpty {
            guard case .complete = input.coverage else {
                return .cannotEvaluate(.partialCoverage(reason: {
                    if case .partial(let reason) = input.coverage { return reason }
                    return "unknown"
                }()))
            }
            return .pass(coverage: input.coverage, checkedCount: candidates.count)
        }
        return .findings(findings)
    }
}
