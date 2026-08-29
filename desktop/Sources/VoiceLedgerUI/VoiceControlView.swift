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

    public init(isListening: Bool, isSpeaking: Bool, micLevel: Double, transcript: String, lastMessage: String?, errorMessage: String?) {
        self.isListening = isListening
        self.isSpeaking = isSpeaking
        self.micLevel = micLevel
        self.transcript = transcript
        self.lastMessage = lastMessage
        self.errorMessage = errorMessage
    }

    public var body: some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.xs) {
                HStack(spacing: VLSpacing.sm) {
                    Text(isListening ? "LISTENING" : (isSpeaking ? "SPEAKING" : "VOICE"))
                        .font(VLTypography.eyebrow())
                        .tracking(VLTypography.eyebrowTracking)
                        .foregroundStyle(VLColor.textMuted)
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
                }

                if !transcript.isEmpty {
                    Text("\"\(transcript)\"")
                        .font(VLTypography.body())
                        .foregroundStyle(VLColor.textSecondary)
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
            }
        }
        .frame(maxWidth: 420)
    }
}
