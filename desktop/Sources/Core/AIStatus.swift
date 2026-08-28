import Foundation

/// docs/VOICE_LEDGER_SPEC.md's Claude/AI Connection status (OpenAI-backed
/// per the owner's 2026-08-28 direction — see docs/VOICE_LEDGER_HANDOFF.md).
/// `configured` is whether the backend has an API key at all (an
/// unconfigured backend is not an error, just "AI features aren't set up
/// yet"); `enabled` is the app-wide kill switch, independent of
/// configuration. Lives in Core (not `IntegrationsQuickBooks`, where
/// `BackendClient` decodes it from over the wire) so `VoiceLedgerUI` views
/// can reference it without depending on the integrations layer —
/// `/core` never imports `/integrations`, and this keeps the reverse true
/// for this simple a shape too.
public struct AIStatus: Codable, Sendable, Equatable {
    public let configured: Bool
    public let enabled: Bool

    public init(configured: Bool, enabled: Bool) {
        self.configured = configured
        self.enabled = enabled
    }
}
