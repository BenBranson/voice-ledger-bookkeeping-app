import Foundation

/// A UI action a voice turn wants to happen — deliberately produced ONLY
/// by `VoiceIntentRouter`'s deterministic matches, never by the reasoning
/// fallback. This is the direct fix for the reference app's own verified
/// hallucination bug: a reasoning response's `speech` can say anything,
/// but it never gets to also claim it navigated/opened/staged something —
/// only a real, matched `VoiceIntent` can produce an action a screen
/// actually changes because of.
public enum VoiceUIAction: Equatable, Sendable {
    case navigate(VoiceDestination)
    case openFinding(id: String)
    case goBack
}

/// `speech` is always shown/spoken verbatim from whichever path (router or
/// reasoning) produced it. `uiAction` and `pendingAction` are the ONLY
/// things that change application state — see `VoiceUIAction`'s doc
/// comment for why the reasoning path can never populate either.
public struct VoiceTurn: Equatable, Sendable {
    public let speech: String
    public let uiAction: VoiceUIAction?
    /// Set only when this turn creates a NEW pending confirmation (e.g.
    /// "dismiss this finding?") — never for a turn that resolves one
    /// (`VoiceIntent.confirmPending`/`.rejectPending` clear it instead,
    /// handled by the caller, not represented here).
    public let newPendingAction: VoicePendingAction?

    public init(speech: String, uiAction: VoiceUIAction? = nil, newPendingAction: VoicePendingAction? = nil) {
        self.speech = speech
        self.uiAction = uiAction
        self.newPendingAction = newPendingAction
    }
}
