import Foundation

/// Owner directive 2026-10-02: tell the bookkeeper when the client opens a
/// new bank, card or loan account in QuickBooks without saying so. Compares
/// the accounts seen at this sync with the ones seen before.
public struct KnownAccountsBaseline: Codable, Sendable, Equatable {
    public var accountIDs: Set<String>
    public var seededAt: Date?

    public init(accountIDs: Set<String> = [], seededAt: Date? = nil) {
        self.accountIDs = accountIDs
        self.seededAt = seededAt
    }
}

public struct NewAccountAlert: Codable, Sendable, Equatable, Identifiable {
    public var id: String { accountID }
    public let accountID: String
    public let name: String
    public let type: String
    public let firstSeenAt: Date
    public var acknowledgedAt: Date?

    public init(accountID: String, name: String, type: String, firstSeenAt: Date, acknowledgedAt: Date? = nil) {
        self.accountID = accountID
        self.name = name
        self.type = type
        self.firstSeenAt = firstSeenAt
        self.acknowledgedAt = acknowledgedAt
    }
}

public enum NewAccountWatch {
    /// Accounts that need monthly reconciliation or a statement.
    public static func isWatched(_ t: LedgerAccountType) -> Bool {
        t == .bank || t == .creditCard || t == .longTermLiability
    }

    /// The first sync only records what exists (an existing client's
    /// accounts are not "new"); later syncs report what wasn't there.
    public static func check(baseline: KnownAccountsBaseline, accounts: [LedgerAccount], now: Date = Date())
        -> (baseline: KnownAccountsBaseline, newAlerts: [NewAccountAlert]) {
        let watched = accounts.filter { isWatched($0.accountType) }
        guard !watched.isEmpty else { return (baseline, []) }
        let ids = Set(watched.map(\.id))
        guard baseline.seededAt != nil else {
            return (KnownAccountsBaseline(accountIDs: ids, seededAt: now), [])
        }
        let fresh = watched.filter { !baseline.accountIDs.contains($0.id) }
        let alerts = fresh.map { NewAccountAlert(accountID: $0.id, name: $0.name, type: $0.accountType.rawValue, firstSeenAt: now) }
        return (KnownAccountsBaseline(accountIDs: baseline.accountIDs.union(ids), seededAt: baseline.seededAt), alerts)
    }
}
