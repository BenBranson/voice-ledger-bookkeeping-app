import SwiftUI
import Core
import DesignSystem

/// Owner directive (2026-09-06): "build... recurring-vendor detection" —
/// see `RecurringVendorDetector`'s own doc comment in Core for the
/// detection model and why it reads `Purchase` history specifically.
public struct RecurringVendorsView: View {
    public struct ViewState {
        public let environment: VLEnvironmentTone
        public let recurringVendors: [RecurringVendor]
        public let missingVendors: [RecurringVendor]
        public let monthsOfHistoryScanned: Int
        public let isLoading: Bool

        public init(environment: VLEnvironmentTone, recurringVendors: [RecurringVendor], missingVendors: [RecurringVendor], monthsOfHistoryScanned: Int, isLoading: Bool) {
            self.environment = environment
            self.recurringVendors = recurringVendors
            self.missingVendors = missingVendors
            self.monthsOfHistoryScanned = monthsOfHistoryScanned
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
        alternateModelTiers: [TwoTierAskAIPanel.AlternateModelTier] = []
    ) {
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
                    Text("Recurring Vendors")
                        .font(VLTypography.pageTitle())
                        .foregroundStyle(VLColor.textPrimary)
                    Spacer()
                    SyncButton(isSyncing: isSyncing, onSync: onSync)
                    VLEnvironmentBadge(state.environment)
                }

                Text("Detects vendors charged at a consistent interval and amount across the trailing \(state.monthsOfHistoryScanned) months of Purchase history — never a guess: a vendor only appears here when its own real charge history is consistent enough (interval and amount both within a fixed tolerance) to call a pattern. Reads `Purchase` transactions only (already-recorded, already-paid charges like a subscription), which never overlaps with the separate Accounts Payable balance the Aged Payables page reports on.")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textMuted)

                if state.isLoading && state.recurringVendors.isEmpty {
                    VLCard {
                        Text("Scanning purchase history…")
                            .foregroundStyle(VLColor.textMuted)
                    }
                } else if state.recurringVendors.isEmpty {
                    VLCard {
                        Text("No recurring vendors detected in the trailing \(state.monthsOfHistoryScanned) months of Purchase history.")
                            .foregroundStyle(VLColor.textMuted)
                    }
                } else {
                    if !state.missingVendors.isEmpty {
                        VLCard(accentRail: VLColor.violet) {
                            VStack(alignment: .leading, spacing: VLSpacing.xs) {
                                VLStatusPill(.reviewNeeded, label: "\(state.missingVendors.count) recurring vendor(s) overdue for their expected charge")
                                ForEach(state.missingVendors) { vendor in
                                    Text("\(vendor.vendorName) — expected \(vendor.expectedNextChargeDate.formatted), last charged \(vendor.lastAmount.accountingDescription) on \(vendor.lastChargeDate.formatted)")
                                        .font(VLTypography.caption())
                                        .foregroundStyle(VLColor.textSecondary)
                                }
                                Text("Could mean a lapsed or cancelled subscription, a vendor who hasn't billed yet, or a charge not yet entered into QuickBooks — worth a quick check, not an automatic conclusion.")
                                    .font(VLTypography.caption())
                                    .foregroundStyle(VLColor.textMuted)
                            }
                        }
                    }

                    ForEach(state.recurringVendors) { vendor in
                        vendorCard(vendor)
                    }
                }

                TwoTierAskAIPanel(
                    aiStatus: aiStatus,
                    placeholder: "Ask a question about these vendors",
                    primaryDisclaimer: "Answers are grounded in the recurring-vendor patterns on this page, plus a summary of every other open finding across the app — it cannot state a dollar figure beyond what's already computed here.",
                    primaryAnswer: askAIAnswer,
                    isAskingPrimary: isAskingAI,
                    primaryError: askAIError,
                    onAskPrimary: onAskAI,
                    secondOpinionConfigured: secondOpinionConfigured,
                    secondOpinionDisclaimer: "Sends this page's recurring-vendor patterns, plus a summary of every other open finding across the app, to OpenAI's API for a second opinion. This costs money per question and only runs when you ask.",
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

    private func vendorCard(_ vendor: RecurringVendor) -> some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                HStack {
                    Text(vendor.vendorName)
                        .font(VLTypography.cardTitle())
                        .foregroundStyle(VLColor.textPrimary)
                    Spacer()
                    Text(vendor.averageAmount.accountingDescription)
                        .font(VLTypography.tabularNumericEmphasis())
                        .foregroundStyle(VLColor.textPrimary)
                }
                Text("Charged roughly every \(Int(vendor.averageIntervalDays.rounded())) days · \(vendor.occurrenceCount) charges seen · next expected \(vendor.expectedNextChargeDate.formatted)")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textSecondary)
                if vendor.lastAmountChanged {
                    HStack(spacing: VLSpacing.xxs) {
                        VLStatusPill(.reviewNeeded, label: "Amount changed")
                        Text("Last charge was \(vendor.lastAmount.accountingDescription) on \(vendor.lastChargeDate.formatted) — outside this vendor's usual pattern.")
                            .font(VLTypography.caption())
                            .foregroundStyle(VLColor.textSecondary)
                    }
                }
            }
        }
    }
}
