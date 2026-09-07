import Foundation

/// Owner directive (2026-09-07): "connect Claude API... for the tool loop"
/// — a selectable backend for Voice Ledger's own in-app voice assistant,
/// alongside the existing free/local `gemma4:12b` default. Persisted via
/// `UserDefaults` (a device-level preference — which AI answers the voice
/// assistant — not a per-client/`realmId` setting, so it deliberately does
/// NOT go through `ClientStore`, which is scoped per connected client).
enum VoiceToolLoopModel: String, CaseIterable, Identifiable {
    case gemma = "gemma4:12b"
    case claudeHaiku = "claude-haiku-4-5"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gemma: return "Gemma 4:12b (local, free)"
        case .claudeHaiku: return "Claude Haiku 4.5 (cloud, ~$0.005/turn)"
        }
    }
}

enum VoiceToolLoopPreference {
    private static let userDefaultsKey = "voiceToolLoopModel"

    static var current: VoiceToolLoopModel {
        get {
            UserDefaults.standard.string(forKey: userDefaultsKey).flatMap(VoiceToolLoopModel.init(rawValue:)) ?? .gemma
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: userDefaultsKey)
        }
    }
}
