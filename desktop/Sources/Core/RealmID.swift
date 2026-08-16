import Foundation

/// The QBO company identifier. The isolation key for everything.
///
/// docs/phase-0/04_DATA_MODEL.md §4.4, docs/phase-0/07_CLIENT_ISOLATION.md.
/// This type exists so that "which client is this data for" is a typed
/// question everywhere in the codebase, never a bare String threaded through
/// function signatures where it could be confused with any other identifier.
public struct RealmID: Hashable, Codable, Sendable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// Sandbox and production are different realms, therefore different scopes,
/// therefore different local stores (§7.2). There is no "switch to
/// production" operation — this value is immutable on whatever owns it.
///
/// CLAUDE.md rule 7: never modify production QBO data during development.
/// The badge that renders this must be visually unmistakable
/// (docs/phase-0/03_SECURITY_THREAT_MODEL.md §3.8) — that's a later, UI step;
/// this enum is the typed fact the badge will eventually read from.
public enum QBOEnvironment: String, Codable, Sendable {
    case sandbox
    case production
}
