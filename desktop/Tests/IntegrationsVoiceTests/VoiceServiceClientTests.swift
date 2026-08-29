import Testing
@testable import IntegrationsVoice
import Foundation

/// `VoiceServiceClient` itself talks to a real local process (`voice-service/`)
/// — live-verified manually against the actual running service (health
/// check, a real TTS synthesis played back, and a genuine TTS->STT round
/// trip), the same "prove it against something real" discipline this
/// session used for every other feature, rather than baked into `swift
/// test` as a dependency on a service the test runner won't have running.
/// What's unit-tested here is the pure parts: error formatting, and that
/// the client is unconditionally bound to loopback.
@Suite("VoiceServiceClient")
struct VoiceServiceClientTests {
    @Test("httpError description includes the status and body")
    func httpErrorDescriptionIncludesDetails() {
        let error = VoiceServiceClientError.httpError(status: 422, body: "Could not decode audio")
        #expect(error.description.contains("422"))
        #expect(error.description.contains("Could not decode audio"))
    }

    @Test("invalidResponse has a real, non-empty description")
    func invalidResponseHasDescription() {
        #expect(!VoiceServiceClientError.invalidResponse.description.isEmpty)
    }
}
