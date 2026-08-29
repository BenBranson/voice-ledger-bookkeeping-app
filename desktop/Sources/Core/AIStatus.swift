import Foundation

/// docs/VOICE_LEDGER_SPEC.md's Claude/AI Connection status. `configured` is
/// whether the backend has a usable provider at all (an unconfigured
/// backend is not an error, just "AI features aren't set up yet");
/// `enabled` is the app-wide kill switch, independent of configuration.
/// `provider`/`model` (added 2026-08-29, when the backend switched its
/// default from OpenAI to a local Ollama model to cut AI cost) say
/// honestly which one is actually answering right now — the UI must never
/// hardcode a provider name, since that's a backend config decision, not a
/// fact about this app. Lives in Core (not `IntegrationsQuickBooks`, where
/// `BackendClient` decodes it from over the wire) so `VoiceLedgerUI` views
/// can reference it without depending on the integrations layer —
/// `/core` never imports `/integrations`, and this keeps the reverse true
/// for this simple a shape too.
public struct AIStatus: Codable, Sendable, Equatable {
    public let configured: Bool
    public let enabled: Bool
    public let provider: String?
    public let model: String?

    public init(configured: Bool, enabled: Bool, provider: String? = nil, model: String? = nil) {
        self.configured = configured
        self.enabled = enabled
        self.provider = provider
        self.model = model
    }
}
