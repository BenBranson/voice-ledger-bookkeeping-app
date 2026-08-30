import SwiftUI
import Core
import DesignSystem

/// Owner directive (2026-08-30): "at the bottom it should give the option
/// to ask ai gemma locally or to ask open ai api, this should practically
/// be at the bottom of every section of the app." `FindingDetailView` and
/// `FindingsListView` already built this exact free-Gemma / opt-in-OpenAI
/// pairing inline, one `AskAIPanelView` each; this extracts that pairing
/// once so every other page (Cleanup Assessment, Balance Sheet Integrity,
/// the financial reports, etc.) can add both tiers with one call instead of
/// duplicating the two-panel block each time. Same CLAUDE.md rule 1
/// boundary as `AskAIPanelView` itself — this only lays out state the
/// caller already computed, never computes or judges anything on its own.
public struct TwoTierAskAIPanel: View {
    private let aiStatus: AIStatus?
    private let placeholder: String
    private let primaryDisclaimer: String
    private let primaryAnswer: String?
    private let isAskingPrimary: Bool
    private let primaryError: String?
    private let onAskPrimary: (String) -> Void

    private let secondOpinionConfigured: Bool
    private let secondOpinionDisclaimer: String
    private let secondOpinionAnswer: String?
    private let isAskingSecondOpinion: Bool
    private let secondOpinionError: String?
    private let onAskSecondOpinion: (String) -> Void

    public init(
        aiStatus: AIStatus?,
        placeholder: String,
        primaryDisclaimer: String,
        primaryAnswer: String?,
        isAskingPrimary: Bool,
        primaryError: String?,
        onAskPrimary: @escaping (String) -> Void,
        secondOpinionConfigured: Bool,
        secondOpinionDisclaimer: String,
        secondOpinionAnswer: String?,
        isAskingSecondOpinion: Bool,
        secondOpinionError: String?,
        onAskSecondOpinion: @escaping (String) -> Void
    ) {
        self.aiStatus = aiStatus
        self.placeholder = placeholder
        self.primaryDisclaimer = primaryDisclaimer
        self.primaryAnswer = primaryAnswer
        self.isAskingPrimary = isAskingPrimary
        self.primaryError = primaryError
        self.onAskPrimary = onAskPrimary
        self.secondOpinionConfigured = secondOpinionConfigured
        self.secondOpinionDisclaimer = secondOpinionDisclaimer
        self.secondOpinionAnswer = secondOpinionAnswer
        self.isAskingSecondOpinion = isAskingSecondOpinion
        self.secondOpinionError = secondOpinionError
        self.onAskSecondOpinion = onAskSecondOpinion
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: VLSpacing.sm) {
            AskAIPanelView(
                disclaimer: primaryDisclaimer,
                placeholder: placeholder,
                aiStatus: aiStatus,
                answer: primaryAnswer,
                isAsking: isAskingPrimary,
                error: primaryError,
                onAsk: onAskPrimary
            )

            if secondOpinionConfigured {
                AskAIPanelView(
                    title: "SECOND OPINION (OPENAI)",
                    disclaimer: secondOpinionDisclaimer,
                    placeholder: "Ask OpenAI for a second opinion",
                    aiStatus: nil,
                    answer: secondOpinionAnswer,
                    isAsking: isAskingSecondOpinion,
                    error: secondOpinionError,
                    onAsk: onAskSecondOpinion
                )
            }
        }
    }
}
