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
    /// The opt-in "second opinion" tier (2026-08-29) — always OpenAI when
    /// configured, entirely independent of `provider`/`model` above (the
    /// app's default, currently local Ollama). `false`/`nil` just means no
    /// `OPENAI_API_KEY` is set on this backend — not an error, the same
    /// "not configured yet" posture `configured` already has for the
    /// primary tier. Additive via `decodeIfPresent`, so a backend that
    /// hasn't been redeployed yet (or a stale cached response) still
    /// decodes correctly with these simply absent.
    public let secondaryConfigured: Bool
    public let secondaryProvider: String?
    public let secondaryModel: String?
    /// The `claude-haiku-4-5` voice-tool-loop model override (2026-09-07) —
    /// same "additive, absent means not configured yet" posture as the
    /// secondary tier above. Independent of `provider`/`model` (the app's
    /// default tier) and of the secondary tier (always OpenAI).
    public let anthropicConfigured: Bool
    public let anthropicModel: String?

    public init(
        configured: Bool,
        enabled: Bool,
        provider: String? = nil,
        model: String? = nil,
        secondaryConfigured: Bool = false,
        secondaryProvider: String? = nil,
        secondaryModel: String? = nil,
        anthropicConfigured: Bool = false,
        anthropicModel: String? = nil
    ) {
        self.configured = configured
        self.enabled = enabled
        self.provider = provider
        self.model = model
        self.secondaryConfigured = secondaryConfigured
        self.secondaryProvider = secondaryProvider
        self.secondaryModel = secondaryModel
        self.anthropicConfigured = anthropicConfigured
        self.anthropicModel = anthropicModel
    }

    private enum CodingKeys: String, CodingKey {
        case configured, enabled, provider, model, secondaryConfigured, secondaryProvider, secondaryModel, anthropicConfigured, anthropicModel
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        configured = try container.decode(Bool.self, forKey: .configured)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        provider = try container.decodeIfPresent(String.self, forKey: .provider)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        secondaryConfigured = try container.decodeIfPresent(Bool.self, forKey: .secondaryConfigured) ?? false
        secondaryProvider = try container.decodeIfPresent(String.self, forKey: .secondaryProvider)
        secondaryModel = try container.decodeIfPresent(String.self, forKey: .secondaryModel)
        anthropicConfigured = try container.decodeIfPresent(Bool.self, forKey: .anthropicConfigured) ?? false
        anthropicModel = try container.decodeIfPresent(String.self, forKey: .anthropicModel)
    }
}
