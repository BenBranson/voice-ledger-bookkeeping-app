import SwiftUI
import Core
import DesignSystem

/// docs/VOICE_LEDGER_SPEC.md Page 10 (Taxes, Type A): "locally estimates
/// trends and possible exposure from QBO financial data... Always labeled
/// an estimate, never filing guidance." See `Core/TaxEstimate.swift`'s doc
/// comment — this page and its underlying computation contain ZERO tax
/// law by deliberate design (owner instruction, 2026-08-28): no bracket,
/// no rate, no jurisdiction rule. The only number this page computes is
/// `netIncome × a rate the user types in themselves`; every dollar figure
/// on this page traces back to either QBO's own "Net Income" line or that
/// user-typed rate, never anything this app asserts on its own.
public struct TaxesView: View {
    private let environment: VLEnvironmentTone
    private let currentPeriodLabel: String
    private let priorPeriodLabel: String
    private let currentNetIncome: Money?
    private let priorNetIncome: Money?
    private let isLoading: Bool
    private let errorMessage: String?
    private let settings: TaxEstimateSettings
    private let onRefresh: () -> Void
    private let onSaveSettings: (TaxEstimateSettings) -> Void
    /// Owner directive (2026-08-31): every page ends in a two-tier Ask AI
    /// panel — see `TwoTierAskAIPanel`. The existing system prompt's own
    /// "never give definitive tax, legal, or filing advice" rule already
    /// covers this page specifically — nothing new needed to keep this
    /// page's own strict non-advice posture intact.
    private let aiStatus: AIStatus?
    private let askAIAnswer: String?
    private let isAskingAI: Bool
    private let askAIError: String?
    private let onAskAI: (String) -> Void
    private let secondOpinionConfigured: Bool
    private let secondOpinionAnswer: String?
    private let isAskingSecondOpinion: Bool
    private let secondOpinionError: String?
    private let onAskSecondOpinion: (String) -> Void

    @State private var actorNameDraft: String = NSFullUserName()
    @State private var rateDraft: String = ""
    @State private var noteDraft: String = ""

    public init(
        environment: VLEnvironmentTone,
        currentPeriodLabel: String,
        priorPeriodLabel: String,
        currentNetIncome: Money?,
        priorNetIncome: Money?,
        isLoading: Bool,
        errorMessage: String?,
        settings: TaxEstimateSettings,
        onRefresh: @escaping () -> Void,
        onSaveSettings: @escaping (TaxEstimateSettings) -> Void,
        aiStatus: AIStatus? = nil,
        askAIAnswer: String? = nil,
        isAskingAI: Bool = false,
        askAIError: String? = nil,
        onAskAI: @escaping (String) -> Void = { _ in },
        secondOpinionConfigured: Bool = false,
        secondOpinionAnswer: String? = nil,
        isAskingSecondOpinion: Bool = false,
        secondOpinionError: String? = nil,
        onAskSecondOpinion: @escaping (String) -> Void = { _ in }
    ) {
        self.environment = environment
        self.currentPeriodLabel = currentPeriodLabel
        self.priorPeriodLabel = priorPeriodLabel
        self.currentNetIncome = currentNetIncome
        self.priorNetIncome = priorNetIncome
        self.isLoading = isLoading
        self.errorMessage = errorMessage
        self.settings = settings
        self.onRefresh = onRefresh
        self.onSaveSettings = onSaveSettings
        self.aiStatus = aiStatus
        self.askAIAnswer = askAIAnswer
        self.isAskingAI = isAskingAI
        self.askAIError = askAIError
        self.onAskAI = onAskAI
        self.secondOpinionConfigured = secondOpinionConfigured
        self.secondOpinionAnswer = secondOpinionAnswer
        self.isAskingSecondOpinion = isAskingSecondOpinion
        self.secondOpinionError = secondOpinionError
        self.onAskSecondOpinion = onAskSecondOpinion
        _rateDraft = State(initialValue: settings.ratePercent.map { String($0) } ?? "")
        _noteDraft = State(initialValue: settings.note ?? "")
    }

    private var parsedRate: Double? {
        let trimmed = rateDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let value = Double(trimmed), value >= 0 else { return nil }
        return value
    }

    private var estimatedSetAside: Money? {
        TaxEstimate.estimatedSetAside(netIncome: currentNetIncome, ratePercent: parsedRate)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VLSpacing.md) {
                HStack {
                    Text("Taxes")
                        .font(VLTypography.pageTitle())
                        .foregroundStyle(VLColor.textPrimary)
                    Spacer()
                    VLEnvironmentBadge(environment)
                }

                VLCard(accentRail: VLColor.violet) {
                    VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                        Text("Not tax advice, not a filing calculation")
                            .font(VLTypography.cardTitle())
                            .foregroundStyle(VLColor.textPrimary)
                        Text("This page contains no tax law of any kind — no rate, bracket, or rule is built into Voice Ledger. It shows QuickBooks' own real net income figures, and does simple multiplication using a rate YOU provide (from your CPA or your own knowledge of your situation). It cannot know your actual liability, deductions, outside income, entity structure, or filed-return status. Confirm everything here with a licensed tax professional before acting on it.")
                            .font(VLTypography.caption())
                            .foregroundStyle(VLColor.textSecondary)
                    }
                }

                HStack {
                    Button(isLoading ? "Loading…" : "Refresh") { onRefresh() }
                        .disabled(isLoading)
                    if let errorMessage {
                        Text(errorMessage)
                            .font(VLTypography.caption())
                            .foregroundStyle(.red)
                    }
                }

                trendSection
                setAsideSection

                TwoTierAskAIPanel(
                    aiStatus: aiStatus,
                    placeholder: "Ask a question about this page",
                    primaryDisclaimer: "Answers are grounded in the net income figures and set-aside calculation on this page, plus a summary of every other open finding across the app — it never gives tax, legal, or filing advice, and cannot state a dollar figure beyond what's already computed.",
                    primaryAnswer: askAIAnswer,
                    isAskingPrimary: isAskingAI,
                    primaryError: askAIError,
                    onAskPrimary: onAskAI,
                    secondOpinionConfigured: secondOpinionConfigured,
                    secondOpinionDisclaimer: "Sends this page's net income and set-aside figures to OpenAI's API for a second opinion. This costs money per question and only runs when you ask. Never gives tax, legal, or filing advice.",
                    secondOpinionAnswer: secondOpinionAnswer,
                    isAskingSecondOpinion: isAskingSecondOpinion,
                    secondOpinionError: secondOpinionError,
                    onAskSecondOpinion: onAskSecondOpinion
                )
            }
            .padding(VLSpacing.pageGutter)
        }
        .background(VLColor.background)
    }

    private var trendSection: some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.xs) {
                Text("NET INCOME — QUICKBOOKS' OWN FIGURE")
                    .font(VLTypography.eyebrow())
                    .tracking(VLTypography.eyebrowTracking)
                    .foregroundStyle(VLColor.textMuted)
                HStack(spacing: VLSpacing.lg) {
                    VStack(alignment: .leading) {
                        Text(currentNetIncome?.description ?? "—")
                            .font(VLTypography.metricLarge())
                            .foregroundStyle(VLColor.textPrimary)
                        Text(currentPeriodLabel)
                            .font(VLTypography.caption())
                            .foregroundStyle(VLColor.textMuted)
                    }
                    VStack(alignment: .leading) {
                        Text(priorNetIncome?.description ?? "—")
                            .font(VLTypography.metricLarge())
                            .foregroundStyle(VLColor.textSecondary)
                        Text(priorPeriodLabel)
                            .font(VLTypography.caption())
                            .foregroundStyle(VLColor.textMuted)
                    }
                }
                if currentNetIncome == nil {
                    Text("No Profit & Loss data loaded for this period yet. Tap Refresh.")
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textMuted)
                }
            }
        }
    }

    private var setAsideSection: some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.sm) {
                Text("ILLUSTRATIVE SET-ASIDE")
                    .font(VLTypography.eyebrow())
                    .tracking(VLTypography.eyebrowTracking)
                    .foregroundStyle(VLColor.textMuted)
                Text("Enter a rate your CPA has given you (or one you already know applies to your situation) and this page will multiply it against this period's net income above — nothing more. Voice Ledger does not suggest, default, or verify this rate in any way.")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textMuted)

                HStack {
                    TextField("Rate (e.g. 25 for 25%)", text: $rateDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 160)
                    Text("%")
                        .foregroundStyle(VLColor.textMuted)
                    Spacer()
                    Text(estimatedSetAside?.description ?? "—")
                        .font(VLTypography.tabularNumericEmphasis())
                        .foregroundStyle(VLColor.textPrimary)
                }

                if !rateDraft.isEmpty && parsedRate == nil {
                    Text("Enter a rate as a plain number, e.g. \"25\" for 25%.")
                        .font(VLTypography.caption())
                        .foregroundStyle(.red)
                }

                TextField("Optional note (who gave you this rate, what it covers)", text: $noteDraft)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    TextField("Your name", text: $actorNameDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 220)
                    Button("Save Rate") {
                        onSaveSettings(TaxEstimateSettings(
                            ratePercent: parsedRate,
                            setBy: actorNameDraft,
                            setAt: Date(),
                            note: noteDraft.isEmpty ? nil : noteDraft
                        ))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(actorNameDraft.trimmingCharacters(in: .whitespaces).isEmpty || (!rateDraft.isEmpty && parsedRate == nil))
                }

                if let setBy = settings.setBy, let setAt = settings.setAt {
                    Text("Last saved by \(setBy) on \(setAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textMuted)
                }
            }
        }
    }
}
