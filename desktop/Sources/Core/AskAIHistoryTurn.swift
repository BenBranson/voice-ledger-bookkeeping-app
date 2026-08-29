import Foundation

/// One prior turn of a voice conversation, replayed into an Ask AI call so
/// a follow-up isn't answered from zero context — added 2026-08-29 after
/// researching a different app's voice assistant (the owner said it felt
/// sharper): that app replays its last several exchanges into every call,
/// while this app's voice engine previously sent one isolated question with
/// no memory of what was just discussed. `content` is always something
/// this app already said or the user already said — never new
/// authoritative data — so this doesn't touch CLAUDE.md rule 1's boundary,
/// only conversational continuity. Lives in Core (not `IntegrationsQuickBooks`)
/// so `VoiceEngine` (`VoiceLedgerApp`) can build this from
/// `VoiceTranscriptEntry` without depending on the integrations layer.
public struct AskAIHistoryTurn: Codable, Sendable, Equatable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}
