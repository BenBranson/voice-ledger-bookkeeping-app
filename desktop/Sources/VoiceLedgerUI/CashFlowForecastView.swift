import SwiftUI
import Core
import DesignSystem

/// Owner directive (2026-09-06): "build cash flow forecasting" — see
/// `CashFlowForecastEngine`'s own doc comment in Core for the full model
/// and its stated assumptions. This view only lays out numbers that engine
/// already computed; the disclaimer text below is the same honest-scope
/// statement, in plain English, that the engine's doc comment gives in
/// code form.
public struct CashFlowForecastView: View {
    public struct ViewState {
        public let environment: VLEnvironmentTone
        public let forecast: CashFlowForecast
        public let isLoading: Bool

        public init(environment: VLEnvironmentTone, forecast: CashFlowForecast, isLoading: Bool) {
            self.environment = environment
            self.forecast = forecast
            self.isLoading = isLoading
        }
    }

    private let state: ViewState
    private let isSyncing: Bool
    private let onSync: () -> Void
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
    private let alternateModelTiers: [TwoTierAskAIPanel.AlternateModelTier]

    /// The 13-week forecast (2026-10-02), shown above Ask AI.
    private let weeklySection: AnyView?

    public init(
        state: ViewState,
        isSyncing: Bool = false,
        onSync: @escaping () -> Void = {},
        aiStatus: AIStatus? = nil,
        askAIAnswer: String? = nil,
        isAskingAI: Bool = false,
        askAIError: String? = nil,
        onAskAI: @escaping (String) -> Void = { _ in },
        secondOpinionConfigured: Bool = false,
        secondOpinionAnswer: String? = nil,
        isAskingSecondOpinion: Bool = false,
        secondOpinionError: String? = nil,
        onAskSecondOpinion: @escaping (String) -> Void = { _ in },
        alternateModelTiers: [TwoTierAskAIPanel.AlternateModelTier] = [],
        weeklySection: AnyView? = nil
    ) {
        self.weeklySection = weeklySection
        self.state = state
        self.isSyncing = isSyncing
        self.onSync = onSync
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
        self.alternateModelTiers = alternateModelTiers
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VLSpacing.md) {
                HStack {
                    Text("Cash Flow Forecast")
                        .font(VLTypography.pageTitle())
                        .foregroundStyle(VLColor.textPrimary)
                    Spacer()
                    SyncButton(isSyncing: isSyncing, onSync: onSync)
                    VLEnvironmentBadge(state.environment)
                }

                Text("A projection, not a prediction: starting from today's real cash balance, adds Accounts Receivable expected to arrive in each window (by QuickBooks' own aging bucket — 91+ days overdue is never counted as \"expected soon,\" see below) and subtracts Accounts Payable due in that window plus any recurring vendor charges expected to hit. Does not model day-to-day timing, seasonality, or a one-time transaction not yet on the books.")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textMuted)

                if state.forecast.startingCash == nil {
                    VLCard {
                        Text(state.isLoading ? "Loading this client's numbers…" : "No balance sheet or aging data yet — sync to see a forecast.")
                            .foregroundStyle(VLColor.textMuted)
                    }
                } else {
                    HStack(spacing: VLSpacing.sm) {
                        VLCard {
                            VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                                Text("CASH TODAY")
                                    .font(VLTypography.eyebrow())
                                    .tracking(VLTypography.eyebrowTracking)
                                    .foregroundStyle(VLColor.textMuted)
                                Text(state.forecast.startingCash?.accountingDescription ?? "Not available")
                                    .font(VLTypography.metricMedium())
                                    .foregroundStyle(VLColor.cyan)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        ForEach(state.forecast.horizons) { horizon in
                            VLCard {
                                VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                                    Text("PROJECTED IN \(horizon.days) DAYS")
                                        .font(VLTypography.eyebrow())
                                        .tracking(VLTypography.eyebrowTracking)
                                        .foregroundStyle(VLColor.textMuted)
                                    Text(horizon.projectedEndingCash?.accountingDescription ?? "Not available")
                                        .font(VLTypography.metricMedium())
                                        .foregroundStyle(horizon.projectedEndingCash != nil ? VLColor.cyan : VLColor.textMuted)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }

                    ForEach(state.forecast.horizons) { horizon in
                        horizonCard(horizon)
                    }

                    if let atRisk = state.forecast.atRiskReceivables, atRisk.minorUnits != 0 {
                        VLCard(accentRail: VLColor.violet) {
                            VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                                HStack {
                                    VLStatusPill(.reviewNeeded, label: "At-risk receivables")
                                    Spacer()
                                    Text(atRisk.accountingDescription)
                                        .font(VLTypography.tabularNumericEmphasis())
                                        .foregroundStyle(VLColor.textPrimary)
                                }
                                Text("91+ days overdue — not counted as expected cash in any window above. Collecting it would be additional, not something already baked into this forecast.")
                                    .font(VLTypography.caption())
                                    .foregroundStyle(VLColor.textSecondary)
                            }
                        }
                    }
                }

                if let weeklySection { weeklySection }

                TwoTierAskAIPanel(
                    aiStatus: aiStatus,
                    placeholder: "Ask a question about this forecast",
                    primaryDisclaimer: "Answers are grounded in the forecast numbers on this page, plus a summary of every other open finding across the app — it cannot state a dollar figure beyond what's already computed here, and it never gives financial or investment advice.",
                    primaryAnswer: askAIAnswer,
                    isAskingPrimary: isAskingAI,
                    primaryError: askAIError,
                    onAskPrimary: onAskAI,
                    secondOpinionConfigured: secondOpinionConfigured,
                    secondOpinionDisclaimer: "Sends this page's forecast numbers, plus a summary of every other open finding across the app, to OpenAI's API for a second opinion. This costs money per question and only runs when you ask.",
                    secondOpinionAnswer: secondOpinionAnswer,
                    isAskingSecondOpinion: isAskingSecondOpinion,
                    secondOpinionError: secondOpinionError,
                    onAskSecondOpinion: onAskSecondOpinion,
                    alternateModelTiers: alternateModelTiers
                )
            }
            .padding(VLSpacing.pageGutter)
        }
        .background(VLColor.background)
    }

    private func horizonCard(_ horizon: CashFlowForecastHorizon) -> some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.xs) {
                Text("NEXT \(horizon.days) DAYS")
                    .font(VLTypography.eyebrow())
                    .tracking(VLTypography.eyebrowTracking)
                    .foregroundStyle(VLColor.textMuted)
                HStack {
                    Text("Expected in (receivables)")
                        .font(VLTypography.body())
                        .foregroundStyle(VLColor.textSecondary)
                    Spacer()
                    Text(horizon.expectedInflow?.accountingDescription ?? "Not available")
                        .font(VLTypography.tabularNumeric())
                        .foregroundStyle(VLColor.textPrimary)
                }
                HStack {
                    Text("Expected out (payables + recurring vendors)")
                        .font(VLTypography.body())
                        .foregroundStyle(VLColor.textSecondary)
                    Spacer()
                    Text(horizon.expectedOutflow?.accountingDescription ?? "Not available")
                        .font(VLTypography.tabularNumeric())
                        .foregroundStyle(VLColor.textPrimary)
                }
            }
        }
    }
}
