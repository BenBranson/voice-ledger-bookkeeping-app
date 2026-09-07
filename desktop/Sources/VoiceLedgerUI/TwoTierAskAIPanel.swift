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
    /// Owner directive (2026-08-31): a one-click default question (e.g.
    /// "Draft a Client Message," "Summarize What Needs Attention") for a
    /// caller with an obvious default ask, same as `AskAIPanelView`'s own
    /// `quickAskLabel` — surfaced only on the free/local tier, since a
    /// quick action shouldn't default to a paid API call. `nil` (the
    /// default) renders nothing extra; every existing caller of this view
    /// is unaffected.
    private let quickAskLabel: String?
    private let onQuickAsk: () -> Void

    private let secondOpinionConfigured: Bool
    private let secondOpinionDisclaimer: String
    private let secondOpinionAnswer: String?
    private let isAskingSecondOpinion: Bool
    private let secondOpinionError: String?
    private let onAskSecondOpinion: (String) -> Void

    /// Owner directive (2026-09-06): "I downloaded qwen3:8b, make every
    /// section... also have a button for asking qwen3:8b, I want to see
    /// if I get better responses." A single bundled struct rather than 5
    /// more individually-named parameters — every one of the ~20 call
    /// sites already passes a same-shaped answer/isAsking/error/onAsk
    /// group for BOTH tiers above; a third named quintuple would make an
    /// already-long init harder to read for no real benefit, since the
    /// caller builds this the same way either way. Still local and free
    /// like the primary tier (this is a comparison of two local models
    /// answering the SAME context, not a second paid API), so it's
    /// rendered as a THIRD `AskAIPanelView`, styled like the primary one,
    /// not like the opt-in-cost second-opinion tier below it. `nil` (the
    /// default) renders nothing extra — every existing call site is
    /// unaffected until `RootView` opts a page in.
    public struct AlternateModelTier {
        public let label: String
        public let modelName: String
        public let disclaimer: String
        public let answer: String?
        public let isAsking: Bool
        public let error: String?
        public let onAsk: (String) -> Void

        public init(label: String, modelName: String, disclaimer: String, answer: String?, isAsking: Bool, error: String?, onAsk: @escaping (String) -> Void) {
            self.label = label
            self.modelName = modelName
            self.disclaimer = disclaimer
            self.answer = answer
            self.isAsking = isAsking
            self.error = error
            self.onAsk = onAsk
        }
    }
    /// Owner directive (2026-09-07): "add an ask claude at the bottom of
    /// every section" — a second alternate tier alongside Qwen3:8b, not a
    /// replacement. Plural (was a single optional) so both can render at
    /// once; each element renders as its own `AskAIPanelView`, in order.
    private let alternateModelTiers: [AlternateModelTier]

    public init(
        aiStatus: AIStatus?,
        placeholder: String,
        primaryDisclaimer: String,
        primaryAnswer: String?,
        isAskingPrimary: Bool,
        primaryError: String?,
        onAskPrimary: @escaping (String) -> Void,
        quickAskLabel: String? = nil,
        onQuickAsk: @escaping () -> Void = {},
        secondOpinionConfigured: Bool,
        secondOpinionDisclaimer: String,
        secondOpinionAnswer: String?,
        isAskingSecondOpinion: Bool,
        secondOpinionError: String?,
        onAskSecondOpinion: @escaping (String) -> Void,
        alternateModelTiers: [AlternateModelTier] = []
    ) {
        self.aiStatus = aiStatus
        self.placeholder = placeholder
        self.primaryDisclaimer = primaryDisclaimer
        self.primaryAnswer = primaryAnswer
        self.isAskingPrimary = isAskingPrimary
        self.primaryError = primaryError
        self.onAskPrimary = onAskPrimary
        self.quickAskLabel = quickAskLabel
        self.onQuickAsk = onQuickAsk
        self.secondOpinionConfigured = secondOpinionConfigured
        self.secondOpinionDisclaimer = secondOpinionDisclaimer
        self.secondOpinionAnswer = secondOpinionAnswer
        self.isAskingSecondOpinion = isAskingSecondOpinion
        self.secondOpinionError = secondOpinionError
        self.onAskSecondOpinion = onAskSecondOpinion
        self.alternateModelTiers = alternateModelTiers
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
                onAsk: onAskPrimary,
                quickAskLabel: quickAskLabel,
                onQuickAsk: onQuickAsk
            )

            ForEach(Array(alternateModelTiers.enumerated()), id: \.offset) { _, tier in
                AskAIPanelView(
                    title: tier.label,
                    disclaimer: tier.disclaimer,
                    placeholder: "Ask \(tier.modelName) a question",
                    aiStatus: nil,
                    answer: tier.answer,
                    isAsking: tier.isAsking,
                    error: tier.error,
                    onAsk: tier.onAsk
                )
            }

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
