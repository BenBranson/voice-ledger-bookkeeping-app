import SwiftUI
import Core
import DesignSystem

/// docs/VOICE_LEDGER_SPEC.md: "Every page ends with an Ask [AI] panel."
/// Extracted from `FindingDetailView`'s original inline implementation
/// (2026-08-28) so every other page can embed the same panel instead of
/// duplicating this UI — the panel's own answer/error state and the
/// question text it composes are entirely the caller's responsibility
/// (`AppState.askAI(contextKey:contextText:question:)`, `AskAIContext`),
/// this view only renders whatever it's given. `disclaimer` is a required
/// parameter, not a default, so every call site has to say out loud what
/// this specific panel's answers are grounded in — the same boundary
/// CLAUDE.md rule 1 enforces everywhere else in this app.
public struct AskAIPanelView: View {
    private let disclaimer: String
    private let placeholder: String
    private let aiStatus: AIStatus?
    private let answer: String?
    private let isAsking: Bool
    private let error: String?
    private let onAsk: (String) -> Void
    /// A one-click canned question (e.g. "Explain This Finding") shown
    /// beside the free-text field, for a caller that has an obvious default
    /// question to offer rather than always requiring the bookkeeper to
    /// type one. `nil` (the default) renders nothing extra — the other call
    /// site (`CleanupAssessmentView`) is unaffected.
    private let quickAskLabel: String?
    private let onQuickAsk: () -> Void

    @State private var questionDraft = ""

    public init(
        disclaimer: String,
        placeholder: String = "Ask a question",
        aiStatus: AIStatus?,
        answer: String?,
        isAsking: Bool,
        error: String?,
        onAsk: @escaping (String) -> Void,
        quickAskLabel: String? = nil,
        onQuickAsk: @escaping () -> Void = {}
    ) {
        self.disclaimer = disclaimer
        self.placeholder = placeholder
        self.aiStatus = aiStatus
        self.answer = answer
        self.isAsking = isAsking
        self.error = error
        self.onAsk = onAsk
        self.quickAskLabel = quickAskLabel
        self.onQuickAsk = onQuickAsk
    }

    public var body: some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.sm) {
                Text("ASK AI")
                    .font(VLTypography.eyebrow())
                    .tracking(VLTypography.eyebrowTracking)
                    .foregroundStyle(VLColor.textMuted)

                if let aiStatus, !aiStatus.configured {
                    Text("AI isn't configured on this backend yet.")
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textMuted)
                } else if let aiStatus, !aiStatus.enabled {
                    Text("AI features are turned off — turn them back on from the Connection page to use this.")
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textMuted)
                } else {
                    Text(disclaimer)
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textMuted)

                    if let quickAskLabel {
                        Button(isAsking ? "Asking…" : quickAskLabel) { onQuickAsk() }
                            .buttonStyle(.bordered)
                            .disabled(isAsking)
                    }

                    if let answer {
                        Text(answer)
                            .font(VLTypography.body())
                            .foregroundStyle(VLColor.textPrimary)
                            .padding(VLSpacing.xs)
                            .background(VLColor.background)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(VLColor.border))
                    }

                    if let error {
                        Text(error)
                            .font(VLTypography.caption())
                            .foregroundStyle(.red)
                    }

                    HStack(spacing: VLSpacing.sm) {
                        TextField(placeholder, text: $questionDraft)
                            .textFieldStyle(.roundedBorder)
                            .disabled(isAsking)
                        Button(isAsking ? "Asking…" : "Ask") {
                            onAsk(questionDraft)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isAsking || questionDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }
}
