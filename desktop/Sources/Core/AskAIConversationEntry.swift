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

    public init(id: String = UUID().uuidString, askedAt: Date = Date(), contextLabel: String, tier: Tier, question: String, answer: String) {
        self.id = id
        self.askedAt = askedAt
        self.contextLabel = contextLabel
        self.tier = tier
        self.question = question
        self.answer = answer
    }
}
