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
    /// Owner directive (2026-08-31): the proposal email should be able to
    /// cite a connected prospect's real, already-computed findings (high-
    /// severity count, total dollar exposure) to justify the cleanup
    /// pricing — pulled straight from `state.findings`, never a free-text
    /// box the bookkeeper has to paste into by hand. Empty when no client
    /// is connected yet (a discovery call before QBO access), in which
    /// case the findings section simply doesn't render and the email is
    /// pricing-only, exactly like before this feature existed.
    private let openFindings: [Finding]
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

    @State private var needsCleanup: Bool

    // Monthly retainer inputs
    @State private var volumeTier: PricingCalculator.VolumeTier = .light
    @State private var hourlyRateText = "100"
    @State private var payrollProcessing = false
    @State private var salesTaxManagement = false
    @State private var multipleBankAccounts = false
    @State private var inventoryTracking = false

    // Cleanup project inputs
    @State private var monthsBehind: PricingCalculator.MonthsBehindTier = .threeToSix
    // Owner directive (2026-08-31): close the gap between Cleanup
    // Assessment (which already computes real, rule-based findings for
    // this client) and this page's cleanup-issue checkboxes, which were
    // otherwise pure manual guesswork re-derived by eye from that other
    // page. Seeded from `openFindings` at init time (see below) only for
    // the three flags with an exact, provable rule match — the other four
    // (payroll/sales tax/inventory/duplicated accounts) have no
    // corresponding rule in this codebase yet, so they stay honestly
    // manual rather than a fabricated auto-detection.
    @State private var multipleUncategorized: Bool
    @State private var personalBusinessMixed: Bool
    @State private var payrollNotReconciled = false
    @State private var salesTaxNotFiled = false
    @State private var inventoryTrackingIssues = false
    @State private var negativeBalances: Bool
    @State private var duplicatedAccounts = false

    @State private var includeFindingsSummary = true

    public init(
        environment: VLEnvironmentTone,
        aiStatus: AIStatus? = nil,
        openFindings: [Finding] = [],
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
        self.openFindings = openFindings

        let ruleIDs = Set(openFindings.map(\.ruleID.rawValue))
        let hasUncategorized = ruleIDs.contains("VL-CAT-UNCAT-001")
        let hasPersonalMixed = ruleIDs.contains("VL-PERSONAL-001")
        let hasNegativeBalances = ruleIDs.contains("VL-BS-NEGBAL-001")
        _multipleUncategorized = State(initialValue: hasUncategorized)
        _personalBusinessMixed = State(initialValue: hasPersonalMixed)
        _negativeBalances = State(initialValue: hasNegativeBalances)
        _needsCleanup = State(initialValue: hasUncategorized || hasPersonalMixed || hasNegativeBalances)

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

    private var highSeverityFindingsCount: Int {
        openFindings.filter { $0.severity == .high }.count
    }

    /// `nil` when there's nothing to sum or the open findings mix
    /// currencies — same same-currency guard `AskAIContext` uses
    /// throughout, rather than a fabricated or misleading total.
    private var totalFindingsExposure: Money? {
        guard let currency = openFindings.first?.dollarExposure.currency,
              openFindings.allSatisfy({ $0.dollarExposure.currency == currency }) else { return nil }
        return openFindings.reduce(Money(minorUnits: 0, currency: currency)) { $0 + $1.dollarExposure }
    }

    /// Real, already-computed findings data serialized for the AI —
    /// counts and dollar exposure only, capped at the 5 highest-severity
    /// titles as concrete examples, not a full itemized dump (this is a
    /// pricing-justification summary, not the Findings page's own report).
    private var findingsSummaryLines: [String] {
        guard !openFindings.isEmpty else { return [] }
        var lines = ["\(openFindings.count) open finding(s) — \(highSeverityFindingsCount) high severity."]
        if let totalFindingsExposure {
            lines.append("Total dollar exposure across open findings: \(totalFindingsExposure.description).")
        }
        let highlighted = openFindings.filter { $0.severity == .high }.prefix(5)
        for finding in highlighted {
            lines.append("- \(finding.title) (\(finding.dollarExposure.description))")
        }
        return lines
    }

    private func composedContext(includeFindings: Bool) -> String {
        var lines = [composedNumbersContext]
        if includeFindings, !findingsSummaryLines.isEmpty {
            lines.append("")
            lines.append("Findings from this client's books (already verified, not estimates):")
            lines.append(contentsOf: findingsSummaryLines)
        }
        return lines.joined(separator: "\n")
    }

    private func requestDraft(instruction: String) {
        let context = composedContext(includeFindings: includeFindingsSummary)
        let combined = instruction == Self.draftQuotePrompt
            ? context
            : "\(context)\n\nAdditional instruction from the bookkeeper: \(instruction)"
        onDraftQuote(combined)
    }

    private func requestDraftSecondOpinion(instruction: String) {
        let context = composedContext(includeFindings: includeFindingsSummary)
        let combined = instruction == Self.draftQuotePrompt
            ? context
            : "\(context)\n\nAdditional instruction from the bookkeeper: \(instruction)"
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

                if !openFindings.isEmpty {
                    findingsSummarySection
                }

                TwoTierAskAIPanel(
                    aiStatus: aiStatus,
                    placeholder: "Ask for a different version (e.g. \"make it more formal\")",
                    primaryDisclaimer: "Drafts a client-facing proposal from the numbers computed above — never invents a figure, never gives tax or legal advice. Always review before sending.",
                    primaryAnswer: quoteDraftAnswer,
                    isAskingPrimary: isDraftingQuote,
                    primaryError: quoteDraftError,
                    onAskPrimary: requestDraft,
                    quickAskLabel: "✨ Generate Professional Proposal Email",
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

    private static let draftQuotePrompt = "Write a professional, warm, and persuasive client proposal email. Use exactly the numbers given above — never alter or recalculate them. If a findings summary is included, briefly explain why those specific issues matter for the client's business health before presenting the pricing as the clear next step. State the price(s) clearly and what's included, and maintain a consultative, high-value tone throughout."

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
                detectableToggle("Multiple uncategorized transactions", isOn: $multipleUncategorized, detected: openFindings.contains { $0.ruleID.rawValue == "VL-CAT-UNCAT-001" })
                detectableToggle("Personal and business mixed together", isOn: $personalBusinessMixed, detected: openFindings.contains { $0.ruleID.rawValue == "VL-PERSONAL-001" })
                Toggle("Payroll not reconciled", isOn: $payrollNotReconciled)
                Toggle("Sales tax not filed", isOn: $salesTaxNotFiled)
                Toggle("Inventory tracking issues", isOn: $inventoryTrackingIssues)
                detectableToggle("Negative balances", isOn: $negativeBalances, detected: openFindings.contains { $0.ruleID.rawValue == "VL-BS-NEGBAL-001" })
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

    /// Shown only when this client is connected and synced (`openFindings`
    /// non-empty) — auto-pulled from real, already-computed findings, not
    /// a paste box, so the proposal email can cite verified numbers rather
    /// than whatever the bookkeeper remembers or retypes.
    private var findingsSummarySection: some View {
        VLCard(accentRail: VLColor.violet) {
            VStack(alignment: .leading, spacing: VLSpacing.xs) {
                Text("FINDINGS SUMMARY (AUTO-INCLUDED)")
                    .font(VLTypography.eyebrow())
                    .tracking(VLTypography.eyebrowTracking)
                    .foregroundStyle(VLColor.violet)
                Toggle("Include this client's findings in the proposal email", isOn: $includeFindingsSummary)
                    .font(VLTypography.body())
                VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                    ForEach(findingsSummaryLines, id: \.self) { line in
                        Text(line)
                            .font(VLTypography.caption())
                            .foregroundStyle(VLColor.textSecondary)
                    }
                }
                .opacity(includeFindingsSummary ? 1 : 0.4)
            }
        }
    }

    /// Same as a plain `Toggle`, but with a small "detected in this
    /// client's findings" note when `detected` is true — always still
    /// editable, never a claim stronger than what was actually checked.
    private func detectableToggle(_ label: String, isOn: Binding<Bool>, detected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Toggle(label, isOn: isOn)
            if detected {
                Text("Detected in this client's synced findings — pre-checked, still editable.")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.cyan)
                    .padding(.leading, VLSpacing.lg)
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
