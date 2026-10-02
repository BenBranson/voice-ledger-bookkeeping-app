import Foundation

/// docs/VOICE_LEDGER_SPEC.md's Firm Cockpit: "every connected client on
/// one screen: period, close readiness %, urgent findings, client-blocked
/// items, reconciliation status, pending imports, last sync, deadlines."
///
/// **A real slice, not the whole thing** — same honesty convention as the
/// Baseline Evidence Pack (`CLAUDE.md` terminology). Built here: write-
/// access state and the last live health check (from the backend's own
/// connection registry — real, timestamped, never a guess), plus, read
/// from each client's own local store: open finding counts (total and
/// high-severity), month-end checklist completion, imported statement
/// line count, and last local activity. **Not built**: "client-blocked
/// items" and "deadlines" — this app tracks neither anywhere yet (no
/// finding carries a "waiting on client" state, no page tracks due
/// dates), so faking either would be exactly the kind of invented status
/// `CLAUDE.md` rule 5 forbids. "Pending imports" is shown as a plain
/// count of imported statement lines, not a judgment about what's
/// actually still pending action.
public struct ConnectedClient: Identifiable, Codable, Sendable, Equatable {
    public let realmID: RealmID
    public let companyName: String?
    public let environment: QBOEnvironment
    public let writeEnabled: Bool
    public let lastHealthCheckAt: Date?
    public let lastHealthCheckStatus: ConnectionHealthStatus?

    public var id: String { realmID.rawValue }

    public init(realmID: RealmID, companyName: String?, environment: QBOEnvironment, writeEnabled: Bool, lastHealthCheckAt: Date?, lastHealthCheckStatus: ConnectionHealthStatus?) {
        self.realmID = realmID
        self.companyName = companyName
        self.environment = environment
        self.writeEnabled = writeEnabled
        self.lastHealthCheckAt = lastHealthCheckAt
        self.lastHealthCheckStatus = lastHealthCheckStatus
    }
}

/// Mirrors `IntegrationsQuickBooks.HealthStatus`'s color semantics
/// (gray means the check didn't complete, never confused with "fine") —
/// duplicated here rather than imported, since `Core` never imports
/// `Integrations` (`CLAUDE.md`'s architecture boundary).
public enum ConnectionHealthStatus: String, Codable, Sendable {
    case green
    case yellow
    case red
    case gray
}

public struct ClientCockpitSummary: Identifiable, Sendable {
    public let client: ConnectedClient
    public let openFindingsCount: Int
    public let urgentFindingsCount: Int
    public let checklistCompleted: Int
    public let checklistTotal: Int
    public let importedStatementLineCount: Int
    public let lastLocalActivityAt: Date?
    /// Bank/card accounts with no posting in 5+ days as of the client's
    /// last history load; `nil` when no history has been loaded.
    public let staleBankFeeds: [String]?
    public let staleBankFeedsAsOf: AccountingDate?
    /// Next filing or delivery from this client's compliance calendar.
    public var nextDeadline: ComplianceDeadline?
    /// Bank, card or loan accounts that appeared in QuickBooks and haven't been acknowledged.
    public var newAccountsCount: Int = 0
    /// False until the bookkeeper reviewed the client's compliance profile.
    public var profileReviewed: Bool = false

    public var id: String { client.id }

    public init(client: ConnectedClient, openFindingsCount: Int, urgentFindingsCount: Int, checklistCompleted: Int, checklistTotal: Int, importedStatementLineCount: Int, lastLocalActivityAt: Date?, staleBankFeeds: [String]? = nil, staleBankFeedsAsOf: AccountingDate? = nil) {
        self.staleBankFeeds = staleBankFeeds
        self.staleBankFeedsAsOf = staleBankFeedsAsOf
        self.client = client
        self.openFindingsCount = openFindingsCount
        self.urgentFindingsCount = urgentFindingsCount
        self.checklistCompleted = checklistCompleted
        self.checklistTotal = checklistTotal
        self.importedStatementLineCount = importedStatementLineCount
        self.lastLocalActivityAt = lastLocalActivityAt
    }
}

public enum FirmCockpit {
    /// Pure — every input is data the caller already read (from the
    /// backend's connection registry and this one client's local
    /// `ClientStore`), never a fresh read or network call of its own.
    /// "Urgent" means open + `.high` severity — the same signal
    /// `NextBestAction.compute` already treats as top priority, reused
    /// here rather than a second definition that could disagree.
    public static func summarize(
        client: ConnectedClient,
        findings: [Finding],
        checklistCompletions: [ChecklistItemCompletion],
        period: AccountingPeriod,
        importedStatementLineCount: Int,
        activityLog: [ActivityLogEntry],
        history: HistorySnapshot? = nil,
        practiceProfile: ClientPracticeProfile? = nil,
        newAccountAlerts: [NewAccountAlert] = [],
        today: AccountingDate = AccountingDate(date: Date())
    ) -> ClientCockpitSummary {
        let openFindings = findings.filter { $0.status == .open }
        let urgentCount = openFindings.filter { $0.severity == .high }.count
        let checklistStatus = MonthEndChecklist.completionStatus(completions: checklistCompletions, period: period)
        let lastActivity = activityLog.map(\.recordedAt).max()
        var summary = ClientCockpitSummary(
            client: client,
            openFindingsCount: openFindings.count,
            urgentFindingsCount: urgentCount,
            checklistCompleted: checklistStatus.completed,
            checklistTotal: checklistStatus.total,
            importedStatementLineCount: importedStatementLineCount,
            lastLocalActivityAt: lastActivity,
            staleBankFeeds: history.map { ClientDiagnostics.bankFeedActivity(history: $0, asOf: $0.through).filter(\.isStale).map(\.accountName) },
            staleBankFeedsAsOf: history?.through
        )
        if let practiceProfile {
            summary.nextDeadline = ComplianceCalendar.deadlines(for: practiceProfile, from: today, days: 120).first
            summary.profileReviewed = practiceProfile.reviewed
        }
        summary.newAccountsCount = newAccountAlerts.filter { $0.acknowledgedAt == nil }.count
        return summary
    }
}
