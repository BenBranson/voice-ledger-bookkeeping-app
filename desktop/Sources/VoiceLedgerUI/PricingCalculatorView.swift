import SwiftUI
import Core
import DesignSystem

/// Owner directive (2026-08-31): a monthly-retainer calculator and a
/// cleanup-project calculator, presented as one page with a toggle for
/// whether this prospect needs both — "cleanup and ongoing work should
/// always be quoted as two separate line items," per pricing guidance
/// already on record for this project. All math lives in
/// `PricingCalculator` (Core, pure, tested) — this view only renders it
/// and reads/writes the inputs. Deliberately usable with NO client
/// connected at all: a bookkeeper on a discovery call with a prospect who
/// hasn't authorized QBO access yet still needs to be able to quote a
/// price on the spot.
public struct PricingCalculatorView: View {
    private let environment: VLEnvironmentTone
    private let aiStatus: AIStatus?
    private let quoteDraftAnswer: String?
    private let isDraftingQuote: Bool
    private let quoteDraftError: String?
    /// Unlike every other page's Ask AI wiring, this page owns its own
    /// inputs (tier, rate, toggles) as private view state — `RootView`
    /// has nothing published to compose a context from. So this callback
    /// receives the FULL composed context (real numbers, built fresh from
    /// current inputs every time, plus the bookkeeper's own typed
    /// instruction if they used the free-text field instead of the quick
    /// button) — the caller just asks one fixed question against whatever
    /// context this view hands it, rather than composing context itself
    /// the way every other page's `RootView` wiring does.
    private let onDraftQuote: (String) -> Void
    private let secondOpinionConfigured: Bool
    private let quoteDraftSecondOpinionAnswer: String?
    private let isDraftingQuoteSecondOpinion: Bool
    private let quoteDraftSecondOpinionError: String?
    private let onDraftQuoteSecondOpinion: (String) -> Void

    @State private var needsCleanup = false

    // Monthly retainer inputs
    @State private var volumeTier: PricingCalculator.VolumeTier = .light
    @State private var hourlyRateText = "100"
    @State private var payrollProcessing = false
    @State private var salesTaxManagement = false
    @State private var multipleBankAccounts = false
    @State private var inventoryTracking = false

    // Cleanup project inputs
    @State private var monthsBehind: PricingCalculator.MonthsBehindTier = .threeToSix
    @State private var multipleUncategorized = false
    @State private var personalBusinessMixed = false
    @State private var payrollNotReconciled = false
    @State private var salesTaxNotFiled = false
    @State private var inventoryTrackingIssues = false
    @State private var negativeBalances = false
    @State private var duplicatedAccounts = false

    public init(
        environment: VLEnvironmentTone,
        aiStatus: AIStatus? = nil,
        quoteDraftAnswer: String? = nil,
        isDraftingQuote: Bool = false,
        quoteDraftError: String? = nil,
        onDraftQuote: @escaping (String) -> Void = { _ in },
        secondOpinionConfigured: Bool = false,
        quoteDraftSecondOpinionAnswer: String? = nil,
        isDraftingQuoteSecondOpinion: Bool = false,
        quoteDraftSecondOpinionError: String? = nil,
        onDraftQuoteSecondOpinion: @escaping (String) -> Void = { _ in }
    ) {
        self.environment = environment
        self.aiStatus = aiStatus
        self.quoteDraftAnswer = quoteDraftAnswer
        self.isDraftingQuote = isDraftingQuote
        self.quoteDraftError = quoteDraftError
        self.onDraftQuote = onDraftQuote
        self.secondOpinionConfigured = secondOpinionConfigured
        self.quoteDraftSecondOpinionAnswer = quoteDraftSecondOpinionAnswer
        self.isDraftingQuoteSecondOpinion = isDraftingQuoteSecondOpinion
        self.quoteDraftSecondOpinionError = quoteDraftSecondOpinionError
        self.onDraftQuoteSecondOpinion = onDraftQuoteSecondOpinion
    }

    private var hourlyRate: Money {
        let dollars = Double(hourlyRateText.trimmingCharacters(in: .whitespaces)) ?? 0
        return Money(minorUnits: Int64((dollars * 100).rounded()), currency: .usd)
    }

    private var monthlyFlags: PricingCalculator.MonthlyComplexityFlags {
        .init(payrollProcessing: payrollProcessing, salesTaxManagement: salesTaxManagement, multipleBankAccounts: multipleBankAccounts, inventoryTracking: inventoryTracking)
    }

    private var monthlyQuote: PricingCalculator.MonthlyQuote {
        PricingCalculator.monthlyQuote(tier: volumeTier, hourlyRate: hourlyRate, flags: monthlyFlags)
    }

    private var cleanupIssues: PricingCalculator.CleanupIssueFlags {
        .init(
            multipleUncategorized: multipleUncategorized, personalBusinessMixed: personalBusinessMixed,
            payrollNotReconciled: payrollNotReconciled, salesTaxNotFiled: salesTaxNotFiled,
            inventoryTrackingIssues: inventoryTrackingIssues, negativeBalances: negativeBalances,
            duplicatedAccounts: duplicatedAccounts
        )
    }

    private var cleanupQuote: PricingCalculator.CleanupQuote {
        PricingCalculator.cleanupQuote(monthsBehind: monthsBehind, volumeTier: volumeTier, hourlyRate: hourlyRate, issues: cleanupIssues)
    }

    private var combinedProposal: PricingCalculator.CombinedProposal {
        .init(cleanup: needsCleanup ? cleanupQuote : nil, monthly: monthlyQuote)
    }

    /// Built fresh from current inputs every time a draft is requested —
    /// every figure here is real `PricingCalculator` output, nothing
    /// invented (CLAUDE.md rule 1).
    private var composedNumbersContext: String {
        let totalHoursText = String(format: "%.1f", monthlyQuote.totalHours)
        let baseHoursText = String(format: "%.1f", monthlyQuote.baseHours)
        let addOnHoursText = String(format: "%.1f", monthlyQuote.addOnHours)
        var lines = ["Monthly retainer: \(totalHoursText) hrs/mo (\(baseHoursText) base + \(addOnHoursText) add-ons) at \(hourlyRate.description)/hr = \(monthlyQuote.monthlyInvestment.description)/mo."]
        if needsCleanup {
            lines.append("One-time cleanup project: \(monthsBehind.label) behind, \(cleanupQuote.issueCount) data hygiene issue(s) flagged, estimated \(cleanupQuote.low.description)–\(cleanupQuote.high.description) (midpoint \(cleanupQuote.midpoint.description)).")
            lines.append("Day-one total (cleanup + first month's retainer): \(combinedProposal.dayOneTotal.description). Then \(monthlyQuote.monthlyInvestment.description)/mo ongoing.")
        }
        return lines.joined(separator: "\n")
    }

    private func requestDraft(instruction: String) {
        let numbers = composedNumbersContext
        let combined = instruction == Self.draftQuotePrompt
            ? numbers
            : "\(numbers)\n\nAdditional instruction from the bookkeeper: \(instruction)"
        onDraftQuote(combined)
    }

    private func requestDraftSecondOpinion(instruction: String) {
        let numbers = composedNumbersContext
        let combined = instruction == Self.draftQuotePrompt
            ? numbers
            : "\(numbers)\n\nAdditional instruction from the bookkeeper: \(instruction)"
        onDraftQuoteSecondOpinion(combined)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VLSpacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                        Text("Pricing Calculator")
                            .font(VLTypography.pageTitle())
                            .foregroundStyle(VLColor.textPrimary)
                        Text("For quoting a prospect before or during a discovery call — works with no client connected.")
                            .font(VLTypography.caption())
                            .foregroundStyle(VLColor.textMuted)
                    }
                    Spacer()
                    VLEnvironmentBadge(environment)
                }

                VLCard {
                    Toggle(isOn: $needsCleanup) {
                        VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                            Text("Does this client need a historical cleanup before ongoing monthly work?")
                                .font(VLTypography.body())
                                .foregroundStyle(VLColor.textPrimary)
                            Text("Cleanup is a one-time project to fix past months; the monthly retainer is separate, ongoing work — quoted and billed separately, never blended into one number.")
                                .font(VLTypography.caption())
                                .foregroundStyle(VLColor.textMuted)
                        }
                    }
                }

                HStack(alignment: .top, spacing: VLSpacing.md) {
                    VStack(alignment: .leading, spacing: VLSpacing.md) {
                        volumeAndRateSection
                        if needsCleanup {
                            cleanupIssuesSection
                        }
                        monthlyAddOnsSection
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: VLSpacing.md) {
                        if needsCleanup {
                            cleanupOutputSection
                        }
                        monthlyOutputSection
                        if needsCleanup {
                            combinedOutputSection
                        }
                    }
                    .frame(width: 340)
                }

                TwoTierAskAIPanel(
                    aiStatus: aiStatus,
                    placeholder: "Ask for a different version (e.g. \"make it more formal\")",
                    primaryDisclaimer: "Drafts a client-facing proposal from the numbers computed above — never invents a figure, never gives tax or legal advice. Always review before sending.",
                    primaryAnswer: quoteDraftAnswer,
                    isAskingPrimary: isDraftingQuote,
                    primaryError: quoteDraftError,
                    onAskPrimary: requestDraft,
                    quickAskLabel: needsCleanup ? "Draft Client Proposal" : "Draft Client Quote",
                    onQuickAsk: { requestDraft(instruction: Self.draftQuotePrompt) },
                    secondOpinionConfigured: secondOpinionConfigured,
                    secondOpinionDisclaimer: "Sends these computed numbers to OpenAI's API for a second opinion on the proposal wording. This costs money per question and only runs when you ask.",
                    secondOpinionAnswer: quoteDraftSecondOpinionAnswer,
                    isAskingSecondOpinion: isDraftingQuoteSecondOpinion,
                    secondOpinionError: quoteDraftSecondOpinionError,
                    onAskSecondOpinion: requestDraftSecondOpinion
                )
            }
            .padding(VLSpacing.pageGutter)
        }
        .background(VLColor.background)
    }

    private static let draftQuotePrompt = "Draft a short, professional client-facing proposal using exactly the numbers given above — state the price(s) clearly and what's included."

    // MARK: Inputs

    private var volumeAndRateSection: some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.sm) {
                Text("VOLUME & RATE")
                    .font(VLTypography.eyebrow())
                    .tracking(VLTypography.eyebrowTracking)
                    .foregroundStyle(VLColor.cyan)

                Text("TRANSACTIONS PER MONTH")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textMuted)
                Picker("Transactions per month", selection: $volumeTier) {
                    ForEach(PricingCalculator.VolumeTier.allCases) { tier in
                        Text(tier.label).tag(tier)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                if needsCleanup {
                    Text("MONTHS BEHIND")
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textMuted)
                    Picker("Months behind", selection: $monthsBehind) {
                        ForEach(PricingCalculator.MonthsBehindTier.allCases) { tier in
                            Text(tier.label).tag(tier)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                Text("HOURLY RATE")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textMuted)
                HStack {
                    Text("$")
                        .foregroundStyle(VLColor.textMuted)
                    TextField("100", text: $hourlyRateText)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 100)
                    Text("/hr")
                        .foregroundStyle(VLColor.textMuted)
                }
            }
        }
    }

    private var monthlyAddOnsSection: some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.xs) {
                Text("MONTHLY COMPLEXITY ADD-ONS")
                    .font(VLTypography.eyebrow())
                    .tracking(VLTypography.eyebrowTracking)
                    .foregroundStyle(VLColor.cyan)
                Toggle("Payroll processing (+1.5 hrs/mo)", isOn: $payrollProcessing)
                Toggle("Sales tax management (+1 hr/mo)", isOn: $salesTaxManagement)
                Toggle("5+ bank/credit accounts (+1 hr/mo)", isOn: $multipleBankAccounts)
                Toggle("Inventory tracking (+2 hrs/mo)", isOn: $inventoryTracking)
            }
        }
    }

    private var cleanupIssuesSection: some View {
        VLCard(accentRail: VLColor.violet) {
            VStack(alignment: .leading, spacing: VLSpacing.xs) {
                Text("CLEANUP — DATA HYGIENE ISSUES")
                    .font(VLTypography.eyebrow())
                    .tracking(VLTypography.eyebrowTracking)
                    .foregroundStyle(VLColor.violet)
                Toggle("Multiple uncategorized transactions", isOn: $multipleUncategorized)
                Toggle("Personal and business mixed together", isOn: $personalBusinessMixed)
                Toggle("Payroll not reconciled", isOn: $payrollNotReconciled)
                Toggle("Sales tax not filed", isOn: $salesTaxNotFiled)
                Toggle("Inventory tracking issues", isOn: $inventoryTrackingIssues)
                Toggle("Negative balances", isOn: $negativeBalances)
                Toggle("Duplicated accounts", isOn: $duplicatedAccounts)
            }
        }
    }

    // MARK: Output

    private var monthlyOutputSection: some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.xs) {
                Text(needsCleanup ? "PHASE 2 — MONTHLY RETAINER" : "MONTHLY RETAINER")
                    .font(VLTypography.eyebrow())
                    .tracking(VLTypography.eyebrowTracking)
                    .foregroundStyle(VLColor.textMuted)
                outputRow("Base hours", "\(String(format: "%.1f", monthlyQuote.baseHours)) hrs")
                outputRow("Add-on hours", "\(String(format: "%.1f", monthlyQuote.addOnHours)) hrs")
                outputRow("Total hours/mo", "\(String(format: "%.1f", monthlyQuote.totalHours)) hrs", emphasize: true)
                Divider().overlay(VLColor.border)
                HStack {
                    Text("Monthly Investment")
                        .font(VLTypography.cardTitle())
                        .foregroundStyle(VLColor.textPrimary)
                    Spacer()
                    Text(monthlyQuote.monthlyInvestment.description)
                        .font(VLTypography.metricLarge())
                        .foregroundStyle(VLColor.cyan)
                }
                Text("Rounded to the nearest $50.")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textMuted)
            }
        }
    }

    private var cleanupOutputSection: some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.xs) {
                Text("PHASE 1 — ONE-TIME CLEANUP")
                    .font(VLTypography.eyebrow())
                    .tracking(VLTypography.eyebrowTracking)
                    .foregroundStyle(VLColor.textMuted)
                HStack {
                    Text("Cleanup Project")
                        .font(VLTypography.cardTitle())
                        .foregroundStyle(VLColor.textPrimary)
                    Spacer()
                    Text(cleanupQuote.midpoint.description)
                        .font(VLTypography.metricLarge())
                        .foregroundStyle(VLColor.cyan)
                }
                HStack(spacing: VLSpacing.lg) {
                    VStack(alignment: .leading) {
                        Text("LOW").font(VLTypography.caption()).foregroundStyle(VLColor.textMuted)
                        Text(cleanupQuote.low.description).font(VLTypography.body()).foregroundStyle(VLColor.textSecondary)
                    }
                    VStack(alignment: .leading) {
                        Text("HIGH").font(VLTypography.caption()).foregroundStyle(VLColor.textMuted)
                        Text(cleanupQuote.high.description).font(VLTypography.body()).foregroundStyle(VLColor.textSecondary)
                    }
                }
                Text("\(cleanupQuote.issueCount) hygiene issue\(cleanupQuote.issueCount == 1 ? "" : "s") flagged · rounded to the nearest $50, floored at $400.")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textMuted)
            }
        }
    }

    private var combinedOutputSection: some View {
        VLCard(accentRail: VLColor.cyan) {
            VStack(alignment: .leading, spacing: VLSpacing.xs) {
                Text("DAY-ONE INVESTMENT")
                    .font(VLTypography.eyebrow())
                    .tracking(VLTypography.eyebrowTracking)
                    .foregroundStyle(VLColor.textMuted)
                Text("What the client pays to get started: the cleanup project plus their first month's retainer.")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textSecondary)
                HStack {
                    Text("Day-One Total")
                        .font(VLTypography.cardTitle())
                        .foregroundStyle(VLColor.textPrimary)
                    Spacer()
                    Text(combinedProposal.dayOneTotal.description)
                        .font(VLTypography.metricLarge())
                        .foregroundStyle(VLColor.cyan)
                }
                Text("Then \(monthlyQuote.monthlyInvestment.description)/mo ongoing.")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textMuted)
            }
        }
    }

    private func outputRow(_ label: String, _ value: String, emphasize: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(VLTypography.body())
                .foregroundStyle(emphasize ? VLColor.textPrimary : VLColor.textSecondary)
            Spacer()
            Text(value)
                .font(emphasize ? VLTypography.tabularNumericEmphasis() : VLTypography.tabularNumeric())
                .foregroundStyle(emphasize ? VLColor.textPrimary : VLColor.textSecondary)
        }
    }
}
