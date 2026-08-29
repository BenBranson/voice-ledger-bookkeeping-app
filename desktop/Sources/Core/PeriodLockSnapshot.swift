import Foundation

/// A single Trial Balance line as captured at the moment a period was
/// locked — deliberately its own `Codable` type rather than reusing
/// `TrialBalanceLine` directly. `TrialBalanceLine.id` is a random UUID
/// fragment generated fresh on every report fetch, which is meaningless
/// once persisted to disk and read back on a later launch; this type keeps
/// only what a stored snapshot actually needs to compare against a later
/// fetch — the label and the two amount columns.
public struct TrialBalanceSnapshotLine: Codable, Hashable, Sendable {
    public let label: String
    public let debit: Money?
    public let credit: Money?

    public init(label: String, debit: Money?, credit: Money?) {
        self.label = label
        self.debit = debit
        self.credit = credit
    }
}

/// `VL-CLOSED-PERIOD-DRIFT-001`. Captured once, at the moment
/// `AppState.setPeriodLock` runs, and persisted alongside the `PeriodLock`
/// itself (`ClientStore.savePeriodLockSnapshot`) — this is the baseline a
/// later resync's Trial Balance is compared against to detect drift.
public struct PeriodLockSnapshot: Codable, Sendable, Equatable {
    public let lockedThrough: AccountingPeriod
    public let capturedAt: Date
    public let lines: [TrialBalanceSnapshotLine]

    public init(lockedThrough: AccountingPeriod, capturedAt: Date = Date(), lines: [TrialBalanceSnapshotLine]) {
        self.lockedThrough = lockedThrough
        self.capturedAt = capturedAt
        self.lines = lines
    }

    /// Summary rows (subtotals/grand totals) are excluded — they're
    /// derived from the leaf rows, not independent facts, and including
    /// them would just double-report the same drift the leaf rows already
    /// show.
    public static func capture(lockedThrough: AccountingPeriod, from trialBalanceLines: [TrialBalanceLine], capturedAt: Date = Date()) -> PeriodLockSnapshot {
        PeriodLockSnapshot(
            lockedThrough: lockedThrough,
            capturedAt: capturedAt,
            lines: trialBalanceLines.filter { !$0.isSummary }.map {
                TrialBalanceSnapshotLine(label: $0.label, debit: $0.debit, credit: $0.credit)
            }
        )
    }
}

/// Pure comparison between a locked-period snapshot and a later resync of
/// the same period's Trial Balance.
public enum PeriodDriftCheck {
    public struct DriftedLine: Sendable, Equatable {
        public let label: String
        public let lockedDebit: Money?
        public let lockedCredit: Money?
        public let currentDebit: Money?
        public let currentCredit: Money?
    }

    /// Compares by account label, not position — Trial Balance line order
    /// isn't a stable identity, and a renamed account would otherwise
    /// false-positive as two unrelated changes instead of not matching at
    /// all (which is itself a real, separate signal: a line present at
    /// lock time with a nonzero balance that's now simply gone).
    public static func drift(snapshot: PeriodLockSnapshot, current: [TrialBalanceLine]) -> [DriftedLine] {
        let currentLeafLines = current.filter { !$0.isSummary }
        let currentByLabel = Dictionary(currentLeafLines.map { ($0.label, $0) }, uniquingKeysWith: { first, _ in first })

        var drifted: [DriftedLine] = []
        for line in snapshot.lines {
            let match = currentByLabel[line.label]
            if match?.debit != line.debit || match?.credit != line.credit {
                drifted.append(DriftedLine(
                    label: line.label,
                    lockedDebit: line.debit,
                    lockedCredit: line.credit,
                    currentDebit: match?.debit,
                    currentCredit: match?.credit
                ))
            }
        }

        let snapshotLabels = Set(snapshot.lines.map(\.label))
        for line in currentLeafLines where !snapshotLabels.contains(line.label) {
            let hasNonzeroAmount = (line.debit?.minorUnits ?? 0) != 0 || (line.credit?.minorUnits ?? 0) != 0
            guard hasNonzeroAmount else { continue }
            drifted.append(DriftedLine(
                label: line.label,
                lockedDebit: nil,
                lockedCredit: nil,
                currentDebit: line.debit,
                currentCredit: line.credit
            ))
        }

        return drifted
    }
}
