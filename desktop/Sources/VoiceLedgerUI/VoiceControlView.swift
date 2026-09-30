import SwiftUI
import DesignSystem

/// docs/VOICE_LEDGER_SPEC.md's `/voice` module — the mic toggle button plus
/// a small live status panel (level meter, transcript, last spoken reply).
/// Takes only primitive state, never `VoiceEngine` itself: `VoiceLedgerUI`
/// has no dependency on `VoiceLedgerApp`/`AVFoundation`, the same "UI-only
/// vocabulary, app layer owns the real state" split every other view in
/// this module already uses (`AskAIPanelView`, `ExportMenuButton`).
public struct VoiceMicButton: View {
    private let isListening: Bool
    private let isProcessing: Bool
    private let onToggle: () -> Void

    public init(isListening: Bool, isProcessing: Bool, onToggle: @escaping () -> Void) {
        self.isListening = isListening
        self.isProcessing = isProcessing
        self.onToggle = onToggle
    }

    public var body: some View {
        Button {
            onToggle()
        } label: {
            Label(isListening ? "Listening…" : (isProcessing ? "Thinking…" : "Voice"), systemImage: isListening ? "mic.fill" : "mic")
                .foregroundStyle(isListening ? .red : VLColor.textPrimary)
        }
    }
}

/// The floating status panel — only meaningful to show while something is
/// actually happening (listening, processing, speaking) or there's a
/// recent reply/error to display; the caller decides when to show it at
/// all (typically `isListening || isProcessing || isSpeaking || lastMessage
/// != nil || errorMessage != nil`).
public struct VoiceStatusPanel: View {
    private let isListening: Bool
    private let isSpeaking: Bool
    private let micLevel: Double
    private let transcript: String
    private let lastMessage: String?
    private let errorMessage: String?
    private let onStop: () -> Void
    private let onRetry: () -> Void
    private let onDismiss: () -> Void

    public init(
        isListening: Bool,
        isSpeaking: Bool,
        micLevel: Double,
        transcript: String,
        lastMessage: String?,
        errorMessage: String?,
        onStop: @escaping () -> Void,
        onRetry: @escaping () -> Void = {},
        onDismiss: @escaping () -> Void
    ) {
        self.isListening = isListening
        self.isSpeaking = isSpeaking
        self.micLevel = micLevel
        self.transcript = transcript
        self.lastMessage = lastMessage
        self.errorMessage = errorMessage
        self.onStop = onStop
        self.onRetry = onRetry
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.xs) {
                HStack(spacing: VLSpacing.sm) {
                    Text(isListening ? "LISTENING" : (isSpeaking ? "SPEAKING" : "VOICE"))
                        .font(VLTypography.eyebrow())
                        .tracking(VLTypography.eyebrowTracking)
                        .foregroundStyle(VLColor.textMuted)
                    // Real, live-tested gap (2026-08-29): saying "stop" out
                    // loud while she's speaking is never heard (the mic
                    // isn't listening during playback) — this button is the
                    // one reliable, immediate way to cut a reply short
                    // without also ending conversation mode.
                    if isSpeaking {
                        Button(action: onStop) {
                            Label("Stop", systemImage: "stop.fill")
                                .font(VLTypography.caption())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                    }
                    if isListening {
                        // A simple bar-meter — proves audio is reaching the
                        // engine independent of whether transcription/
                        // routing/TTS succeed (same reasoning the reference
                        // app's own level meter comment gives).
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(.red)
                                .frame(width: max(2, geo.size.width * micLevel))
                        }
                        .frame(height: 4)
                        .background(VLColor.border)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                    }
                    Spacer(minLength: VLSpacing.xs)
                    // The panel used to have no way to go away once
                    // `lastMessage`/`errorMessage` were set — this is that
                    // dismiss control.
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(VLColor.textMuted)
                    }
                    .buttonStyle(.plain)
                }

                // Confirms she actually received the right words — real,
                // requested feedback (2026-08-29): on-screen only (no
                // spoken echo — that would add a full TTS round trip to
                // every command, working against responsiveness), but
                // made more prominent than a caption so it reads as "here
                // is what I heard," not an afterthought.
                if !transcript.isEmpty {
                    Text("\"\(transcript)\"")
                        .font(VLTypography.bodyEmphasis())
                        .foregroundStyle(VLColor.textPrimary)
                }

                if let lastMessage {
                    Text(lastMessage)
                        .font(VLTypography.body())
                        .foregroundStyle(VLColor.textPrimary)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(VLTypography.caption())
                        .foregroundStyle(.red)
                }
                if !isListening && !isSpeaking && (!transcript.isEmpty || errorMessage != nil) {
                    Button(action: onRetry) {
                        Label("Try again", systemImage: "mic")
                            .font(VLTypography.caption())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(VLColor.cyan)
                }
            }
        }
        .frame(maxWidth: 420)
    }
}
