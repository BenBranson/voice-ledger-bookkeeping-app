import Foundation

/// Owner directive (2026-08-29): "change voice history section to the
/// conversation [I] have from asking gemma and or open ai" — voice is
/// being deprioritized in favor of the Ask AI panels as the primary
/// interaction surface, and every one of those panels (per-finding
/// explain/second-opinion, the two report buttons and their follow-up
/// questions, voice's own reasoning fallback — which already routes
/// through the same `AppState.askAI`/`askSecondOpinion` methods) now logs
/// here, giving one unified, persisted history instead of a voice-only
/// transcript.
public struct AskAIConversationEntry: Identifiable, Codable, Sendable, Equatable {
    public enum Tier: String, Codable, Sendable {
        case primary
        case secondary
        /// Claude Haiku 4.5 — a THIRD tier (2026-09-07), distinct from
        /// `.secondary` (OpenAI): both are paid/cloud, but they're
        /// different providers and the report history log/conversation
        /// history should say which one actually answered.
        case claude
    }

    public let id: String
    public let askedAt: Date
    /// A human-readable name for what this question was about — a
    /// finding's title, "Book Health Report," or "Client Value Summary."
    /// Resolved by `AppState` (the one layer that knows how to map a raw
    /// context key back to something readable), never a raw internal key.
    public let contextLabel: String
    public let tier: Tier
    public let question: String
    public let answer: String
    /// What the books looked like when this was answered, so an old answer
    /// is never mistaken for a current one. Optional: entries saved before
    /// v1.53 have neither.
    public let period: String?
    public let openFindingCount: Int?

    /// "July 2026, 17 open findings", or nil for old entries.
    public var dataLabel: String? {
        guard period != nil || openFindingCount != nil else { return nil }
        let count = openFindingCount.map { "\($0) open finding\($0 == 1 ? "" : "s")" }
        return [period, count].compactMap { $0 }.joined(separator: ", ")
    }

    /// Non-nil when the books differ from when this was answered.
    public func staleNote(currentPeriod: String, currentOpenCount: Int) -> String? {
        if let period, period != currentPeriod { return "Older data: answered for \(period), now showing \(currentPeriod)." }
        if let openFindingCount, openFindingCount != currentOpenCount {
            return "Older data: \(openFindingCount) open finding\(openFindingCount == 1 ? "" : "s") then, \(currentOpenCount) now."
        }
        return nil
    }

    public init(id: String = UUID().uuidString, askedAt: Date = Date(), contextLabel: String, tier: Tier, question: String, answer: String, period: String? = nil, openFindingCount: Int? = nil) {
        self.period = period
        self.openFindingCount = openFindingCount
        self.id = id
        self.askedAt = askedAt
        self.contextLabel = contextLabel
        self.tier = tier
        self.question = question
        self.answer = answer
    }
}
