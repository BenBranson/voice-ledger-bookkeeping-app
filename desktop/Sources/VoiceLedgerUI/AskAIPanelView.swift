import SwiftUI
import AppKit
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
    /// Distinguishes multiple panels on the same screen — e.g.
    /// `FindingDetailView`'s free (Gemma) and opt-in "second opinion"
    /// (OpenAI) panels, 2026-08-29. Defaults to the original hardcoded
    /// text, so the other two call sites are unaffected.
    private let title: String
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
    /// Owner directive (2026-08-29): "a copy text button... to instantly
    /// copy the box of text." Brief label swap so the click itself gives
    /// feedback, rather than a silent copy the owner has to trust happened.
    @State private var didCopy = false

    public init(
        title: String = "ASK AI",
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
        self.title = title
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
                HStack {
                    Text(title)
                        .font(VLTypography.eyebrow())
                        .tracking(VLTypography.eyebrowTracking)
                        .foregroundStyle(VLColor.textMuted)
                    Spacer()
                    if let answer {
                        Button(didCopy ? "Copied" : "Copy Text") {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(answer, forType: .string)
                            didCopy = true
                            Task {
                                try? await Task.sleep(for: .seconds(2))
                                didCopy = false
                            }
                        }
                        .buttonStyle(.plain)
                        .font(VLTypography.caption())
                        .foregroundStyle(didCopy ? VLColor.textMuted : VLColor.cyan)
                    }
                }

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
                            .textSelection(.enabled)
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
