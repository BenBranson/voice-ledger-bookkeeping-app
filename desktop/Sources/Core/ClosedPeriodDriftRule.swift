import Foundation

/// `VL-CLOSED-PERIOD-DRIFT-001`. docs/phase-0/08_RULE_ENGINE.md's backlog
/// table: "A closed period's trial-balance snapshot/hash no longer matches
/// on resync." Ties into `PeriodLock` (Page 2): `AppState.setPeriodLock`
/// captures a `PeriodLockSnapshot` of the Trial Balance at the moment a
/// period is locked; this rule compares that snapshot against the SAME
/// period's Trial Balance on any later resync.
///
/// **Only fires when the currently-synced period IS the locked-through
/// period.** The snapshot is a promise about one specific period's
/// numbers, not every period up to it — comparing it against a different
/// period's Trial Balance would compare unrelated numbers. A bookkeeper
/// revisits the locked month specifically (e.g. to answer a client
/// question) to trigger this check, same trigger pattern
/// `VL-PERIOD-CLOSED-001`'s doc comment describes.
public enum ClosedPeriodDriftRule: Rule {
    public static let identity = RuleIdentity(
        id: RuleID(rawValue: "VL-CLOSED-PERIOD-DRIFT-001"),
        version: RuleVersion(major: 1, minor: 0, patch: 0),
        title: "A locked period's Trial Balance no longer matches its snapshot",
        category: .closedPeriodDrift,
        ruleClass: .categorization,
        page: .cleanupAssessment,
        accountingPrinciple: "Once a period is locked, its Trial Balance should stop moving — that's the whole point of a close. If the same period's Trial Balance looks different than it did at lock time, something changed after the close: a backdated entry, an edit to an existing transaction, or a deletion. Whatever it is, the reports already delivered for this period may no longer be accurate.",
        sourceDependencies: [SourceDependency(entity: .report)]
    )

    public static let requirements = DataRequirements(
        entities: [.report],
        requiredCoverage: .complete
    )

    public static func evaluate(_ input: NormalizedDataSet, context: RuleContext) -> RuleOutcome {
        guard let lock = context.periodLock else {
            return .cannotEvaluate(.partialCoverage(reason: "No period lock has been set. Set one on the Scope & Period Lock page to enable this check."))
        }
        guard let snapshot = context.periodLockSnapshot else {
            return .cannotEvaluate(.partialCoverage(reason: "No Trial Balance snapshot was captured when this period was locked (the lock predates this check, or the Trial Balance couldn't be fetched at lock time). Re-lock the period to capture a snapshot."))
        }
        guard (input.period.year, input.period.month) == (lock.lockedThrough.year, lock.lockedThrough.month) else {
            return .cannotEvaluate(.partialCoverage(reason: "Currently viewing \(input.period.year)-\(String(format: "%02d", input.period.month)), not the locked period \(lock.lockedThrough.year)-\(String(format: "%02d", lock.lockedThrough.month)). Switch to the locked period to run this check."))
        }
        guard !input.trialBalanceLines.isEmpty else {
            return .cannotEvaluate(.partialCoverage(reason: "Trial Balance report not loaded for this period. Visit the Trial Balance page (or resync) to run this check."))
        }

        let driftedLines = PeriodDriftCheck.drift(snapshot: snapshot, current: input.trialBalanceLines)
        let materialDrift = driftedLines.filter { line in
            let debitDelta = Self.delta(locked: line.lockedDebit, current: line.currentDebit)
            let creditDelta = Self.delta(locked: line.lockedCredit, current: line.currentCredit)
            return debitDelta >= context.materiality.absoluteFloor || creditDelta >= context.materiality.absoluteFloor
        }

        guard !materialDrift.isEmpty else {
            return .pass(coverage: input.coverage, checkedCount: snapshot.lines.count)
        }

        let totalExposure = materialDrift.reduce(Money.zero) { total, line in
            total + Self.delta(locked: line.lockedDebit, current: line.currentDebit) + Self.delta(locked: line.lockedCredit, current: line.currentCredit)
        }

        let findingID = FindingIDGenerator.makeID(
            ruleID: identity.id,
            ruleVersion: identity.version,
            realmID: input.realmID,
            period: input.period,
            sortedAffectedIDs: ["closed-period-drift"]
        )
        guard !context.dismissedFindingIDs.contains(findingID) else {
            return .pass(coverage: input.coverage, checkedCount: snapshot.lines.count)
        }

        let lineList = materialDrift.map { line -> String in
            let lockedText = line.lockedDebit?.description ?? line.lockedCredit?.description ?? "$0.00"
            let currentText = line.currentDebit?.description ?? line.currentCredit?.description ?? "$0.00"
            return "\(line.label): was \(lockedText), now \(currentText)"
        }.joined(separator: "; ")

        let procedure = GuidedProcedure(
            steps: [
                "Run a Transaction Detail report or Audit Log filtered to \(lock.lockedThrough.year)-\(String(format: "%02d", lock.lockedThrough.month)), sorted by last-modified date",
                "Look for anything modified, added, or deleted AFTER \(snapshot.capturedAt.formatted(date: .abbreviated, time: .shortened)) — the moment this period was locked",
                "Confirm whether the change was intentional (a legitimate correction) or accidental (a backdated entry that belongs in a later period)",
                "If intentional, note it and consider re-locking the period to capture a fresh snapshot; if accidental, correct it in QBO"
            ],
            pitfalls: [
                "This check compares by account label — a renamed account will show as one line disappearing and a new one appearing, not as a single edit",
                "Re-locking after resolving this replaces the snapshot with today's numbers, so investigate first — re-locking before investigating erases the evidence this check is comparing against"
            ],
            doneCriteria: "Every drifted line is explained, and the period has either been re-locked with a fresh snapshot or flagged for the client as needing to stay open"
        )

        let action = ProposedAction(
            id: "review-closed-period-drift",
            title: "Investigate what changed since this period was locked",
            resolution: .manualQBO,
            guidedProcedure: procedure,
            consequences: [
                .reporting("Reports already delivered for \(lock.lockedThrough.year)-\(String(format: "%02d", lock.lockedThrough.month)) may no longer match what's currently posted in QBO"),
                .auditTrail("Voice Ledger records your attestation; QBO's own record of any change is authoritative")
            ],
            reversal: .reversibleManually(procedure: "Re-lock the period once the drift is explained to capture a fresh snapshot")
        )

        let finding = Finding(
            id: findingID,
            ruleID: identity.id,
            ruleVersion: identity.version,
            realmID: input.realmID,
            period: input.period,
            title: "Trial Balance for a locked period has changed since lock — \(materialDrift.count) line\(materialDrift.count == 1 ? "" : "s") drifted",
            severity: Severity.derive(dollarExposure: totalExposure, materiality: context.materiality),
            confidence: .high,
            dollarExposure: totalExposure,
            evidence: [EvidenceItem(
                transactionID: "closed-period-drift",
                highlightedFields: ["trialBalance"],
                fieldValues: [
                    "lockedThrough": "\(lock.lockedThrough.year)-\(String(format: "%02d", lock.lockedThrough.month))",
                    "capturedAt": snapshot.capturedAt.formatted(date: .abbreviated, time: .shortened),
                    "driftedLines": lineList
                ]
            )],
            proposedActions: [action],
            provenance: [.qboAPI(readAt: Date())],
            narrative: "The Trial Balance for \(lock.lockedThrough.year)-\(String(format: "%02d", lock.lockedThrough.month)) no longer matches the snapshot captured when this period was locked (\(snapshot.capturedAt.formatted(date: .abbreviated, time: .shortened))): \(lineList).",
            riskIfIgnored: "Reports already delivered for this locked period may silently no longer match what's actually posted in QBO, and no one will know until someone happens to compare them by hand."
        )

        return .findings([finding])
    }

    private static func delta(locked: Money?, current: Money?) -> Money {
        let currency = locked?.currency ?? current?.currency ?? .usd
        let lockedAmount = locked ?? Money(minorUnits: 0, currency: currency)
        let currentAmount = current ?? Money(minorUnits: 0, currency: currency)
        let diff = currentAmount.minorUnits - lockedAmount.minorUnits
        return Money(minorUnits: abs(diff), currency: currency)
    }
}
