import Foundation

/// One turn of a voice conversation — persisted so the owner can read past
/// sessions back on reopen ("she should have a working memory"), not just
/// the structural `VoiceSessionContext` pointers (current entity, review
/// queue) that already survive a restart. Isolation is inherited from
/// whichever `ClientStore` instance appends/loads these — see that type's
/// own doc comment on why there is no `realmID` field here, matching
/// `VoiceSessionContext`'s existing shape.
public struct VoiceTranscriptEntry: Identifiable, Codable, Sendable, Equatable {
    public enum Speaker: String, Codable, Sendable {
        case user
        case assistant
    }

    public let id: String
    public let timestamp: Date
    public let speaker: Speaker
    public let text: String

    public init(id: String = UUID().uuidString, timestamp: Date = Date(), speaker: Speaker, text: String) {
        self.id = id
        self.timestamp = timestamp
        self.speaker = speaker
        self.text = text
    }
}
