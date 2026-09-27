import SwiftUI
import Core
import DesignSystem

/// A discovery-call script, read top to bottom on the call itself —
/// every question from the owner's own intake questionnaire, each with a
/// live-fillable answer field directly underneath it, and the exact
/// `PricingCalculator` control that question feeds scattered right next
/// to it (never grouped separately at the top, unlike
/// `PricingCalculatorView`, which stays exactly as it was for a quick
/// standalone quote). Also how a new prospect gets saved into the firm's
/// roster (`IntakeRosterStore`) — see `onSave`.
///
/// Owner directive (2026-09-27), verbatim intent preserved: "set this up
/// as a smooth conversation flow from beginning to end of the call like a
/// transcript... After each question there should be a field underneath
/// it... put sentences I should say in the transcript... put in the
/// script my credentials of holding an MBA and mention the software and
/// the free monthly report."
public struct IntakeQuestionsView: View {
    @Binding var intake: ClientIntake
    let roster: [ClientIntake]
    let environment: VLEnvironmentTone
    let aiStatus: AIStatus?
    /// Real, already-computed findings for a prospect who HAS connected
    /// and synced QBO already (rare at this stage, but real for an
    /// existing client re-doing intake) — empty otherwise, same
    /// `PricingCalculatorView` convention.
    let openFindings: [Finding]
    let onStartNew: () -> Void
    let onLoadForEditing: (ClientIntake) -> Void
    let onSave: () -> Void
    let statusMessage: String?
    let onDismissStatusMessage: () -> Void

    let quoteDraftAnswer: String?
    let isDraftingQuote: Bool
    let quoteDraftError: String?
    let onDraftQuote: (String) -> Void
    let secondOpinionConfigured: Bool
    let quoteDraftSecondOpinionAnswer: String?
    let isDraftingQuoteSecondOpinion: Bool
    let quoteDraftSecondOpinionError: String?
    let onDraftQuoteSecondOpinion: (String) -> Void

    public init(
        intake: Binding<ClientIntake>,
        roster: [ClientIntake],
        environment: VLEnvironmentTone,
        aiStatus: AIStatus? = nil,
        openFindings: [Finding] = [],
        onStartNew: @escaping () -> Void,
        onLoadForEditing: @escaping (ClientIntake) -> Void,
        onSave: @escaping () -> Void,
        statusMessage: String? = nil,
        onDismissStatusMessage: @escaping () -> Void = {},
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
        self._intake = intake
        self.roster = roster
        self.environment = environment
        self.aiStatus = aiStatus
        self.openFindings = openFindings
        self.onStartNew = onStartNew
        self.onLoadForEditing = onLoadForEditing
        self.onSave = onSave
        self.statusMessage = statusMessage
        self.onDismissStatusMessage = onDismissStatusMessage
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

    // MARK: Derived pricing output (identical math to PricingCalculatorView)

    private var monthlyQuote: PricingCalculator.MonthlyQuote { intake.monthlyQuote }
    private var cleanupQuote: PricingCalculator.CleanupQuote { intake.cleanupQuote }
    private var combinedProposal: PricingCalculator.CombinedProposal { intake.combinedProposal }

    private var highSeverityFindingsCount: Int {
        openFindings.filter { $0.severity == .high }.count
    }

    private var totalFindingsExposure: Money? {
        guard let currency = openFindings.first?.dollarExposure.currency,
              openFindings.allSatisfy({ $0.dollarExposure.currency == currency }) else { return nil }
        return openFindings.reduce(Money(minorUnits: 0, currency: currency)) { $0 + $1.dollarExposure }
    }

    private var findingsSummaryLines: [String] {
        guard !openFindings.isEmpty else { return [] }
        var lines = ["\(openFindings.count) open finding(s) — \(highSeverityFindingsCount) high severity."]
        if let totalFindingsExposure {
            lines.append("Total dollar exposure across open findings: \(totalFindingsExposure.description).")
        }
        for finding in openFindings.filter({ $0.severity == .high }).prefix(5) {
            lines.append("- \(finding.title) (\(finding.dollarExposure.description))")
        }
        return lines
    }

    /// Every qualitative answer captured so far, plainly labeled — this is
    /// what makes the generated proposal email actually reference the
    /// call, not just the numbers. Blank answers are omitted rather than
    /// sent as empty labeled lines.
    private var qualitativeContext: String {
        let pairs: [(String, String)] = [
            ("Business", intake.legalBusinessName), ("Entity type", intake.entityType),
            ("Industry", intake.industry), ("Primary revenue sources", intake.primaryRevenueSources),
            ("Years in business", intake.yearsInBusiness),
            ("Accounting software", intake.accountingSoftware),
            ("Bank accounts", intake.bankAccountCountAnswer), ("Credit cards", intake.creditCardCountAnswer),
            ("Monthly transaction volume", intake.monthlyTransactionCountAnswer),
            ("Books up to date?", intake.booksUpToDateAnswer),
            ("Who handles AR/AP today", intake.whoManagesARAP),
            ("Payment processors / POS", intake.paymentProcessors),
            ("Primary contact", [intake.pointOfContactName, intake.pointOfContactRole].filter { !$0.isEmpty }.joined(separator: ", ")),
            ("Contact email", intake.pointOfContactEmail), ("Contact phone", intake.pointOfContactPhone),
            ("Preferred communication", intake.communicationPreference),
            ("Biggest frustrations today", intake.frustrations),
            ("Metrics/KPIs they want", intake.desiredMetrics),
            ("What the financials are for", intake.financialsUse)
        ]
        return pairs
            .filter { !$0.1.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { "\($0.0): \($0.1)" }
            .joined(separator: "\n")
    }

    private var composedNumbersContext: String {
        let totalHoursText = String(format: "%.1f", monthlyQuote.totalHours)
        let baseHoursText = String(format: "%.1f", monthlyQuote.baseHours)
        let addOnHoursText = String(format: "%.1f", monthlyQuote.addOnHours)
        var lines = ["Monthly retainer: \(totalHoursText) hrs/mo (\(baseHoursText) base + \(addOnHoursText) add-ons) at \(intake.hourlyRate.description)/hr = \(monthlyQuote.monthlyInvestment.description)/mo."]
        if intake.needsCleanup {
            lines.append("One-time cleanup project: \(intake.monthsBehind.label) behind, \(cleanupQuote.issueCount) data hygiene issue(s) flagged, estimated \(cleanupQuote.low.description)–\(cleanupQuote.high.description) (midpoint \(cleanupQuote.midpoint.description)).")
            lines.append("Day-one total (cleanup + first month's retainer): \(combinedProposal.dayOneTotal.description). Then \(monthlyQuote.monthlyInvestment.description)/mo ongoing.")
        }
        return lines.joined(separator: "\n")
    }

    private func composedContext(includeFindings: Bool) -> String {
        var lines = [qualitativeContext, "", composedNumbersContext]
        if includeFindings, !findingsSummaryLines.isEmpty {
            lines.append("")
            lines.append("Findings from this client's books (already verified, not estimates):")
            lines.append(contentsOf: findingsSummaryLines)
        }
        return lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private func requestDraft(instruction: String) {
        let context = composedContext(includeFindings: intake.includeFindingsSummary)
        let combined = instruction == Self.draftProposalPrompt ? context : "\(context)\n\nAdditional instruction from the bookkeeper: \(instruction)"
        onDraftQuote(combined)
    }

    private func requestDraftSecondOpinion(instruction: String) {
        let context = composedContext(includeFindings: intake.includeFindingsSummary)
        let combined = instruction == Self.draftProposalPrompt ? context : "\(context)\n\nAdditional instruction from the bookkeeper: \(instruction)"
        onDraftQuoteSecondOpinion(combined)
    }

    private static let draftProposalPrompt = "Write a professional, warm, and persuasive client proposal email. Weave in the specific business context and answers given above — this should read like it's about THIS prospect's actual business, not a generic template. Use exactly the pricing numbers given above — never alter or recalculate them. If a findings summary is included, briefly explain why those specific issues matter before presenting the pricing. Mention that the client will receive a free monthly report as part of the engagement. Maintain a consultative, high-value tone throughout."

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VLSpacing.md) {
                header
                rosterBar
                openingScript
                sectionBasicContext
                sectionFinancialEcosystem
                sectionScopeAndBoundaries
                sectionWorkflowAndCommunication
                sectionGoalsAndReporting

                if !openFindings.isEmpty {
                    findingsSummarySection
                }
                quoteSummarySection

                HStack {
                    Spacer()
                    Button("Save Client") { onSave() }
                        .buttonStyle(.borderedProminent)
                }

                TwoTierAskAIPanel(
                    aiStatus: aiStatus,
                    placeholder: "Ask for a different version (e.g. \"make it more formal\")",
                    primaryDisclaimer: "Drafts a client-facing proposal from the numbers and answers captured above — never invents a figure, never gives tax or legal advice. Always review before sending.",
                    primaryAnswer: quoteDraftAnswer,
                    isAskingPrimary: isDraftingQuote,
                    primaryError: quoteDraftError,
                    onAskPrimary: requestDraft,
                    quickAskLabel: "✨ Generate Professional Proposal Email",
                    onQuickAsk: { requestDraft(instruction: Self.draftProposalPrompt) },
                    secondOpinionConfigured: secondOpinionConfigured,
                    secondOpinionDisclaimer: "Sends these answers and computed numbers to OpenAI's API for a second opinion on the proposal wording. This costs money per question and only runs when you ask.",
                    secondOpinionAnswer: quoteDraftSecondOpinionAnswer,
                    isAskingSecondOpinion: isDraftingQuoteSecondOpinion,
                    secondOpinionError: quoteDraftSecondOpinionError,
                    onAskSecondOpinion: requestDraftSecondOpinion
                )
            }
            .padding(VLSpacing.pageGutter)
        }
        .background(VLColor.background)
        .alert("Intake", isPresented: Binding(get: { statusMessage != nil }, set: { if !$0 { onDismissStatusMessage() } })) {
            Button("OK") { onDismissStatusMessage() }
        } message: {
            Text(statusMessage ?? "")
        }
    }

    // MARK: Header / roster

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                Text("Intake Questions")
                    .font(VLTypography.pageTitle())
                    .foregroundStyle(VLColor.textPrimary)
                Text("A discovery-call script — read it top to bottom, fill in answers as you go.")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textMuted)
            }
            Spacer()
            VLEnvironmentBadge(environment)
        }
    }

    private var rosterBar: some View {
        VLCard {
            HStack(spacing: VLSpacing.sm) {
                VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                    Text(intake.displayName)
                        .font(VLTypography.cardTitle())
                        .foregroundStyle(VLColor.textPrimary)
                    Text("Saved roster: \(roster.count) prospect/client record(s)")
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textMuted)
                }
                Spacer()
                Menu("Load Saved…") {
                    if roster.isEmpty {
                        Text("No saved records yet")
                    }
                    ForEach(roster) { saved in
                        Button(saved.displayName) { onLoadForEditing(saved) }
                    }
                }
                Button("New Prospect") { onStartNew() }
            }
        }
    }

    /// Owner directive: "put in the script my credentials of holding an
    /// MBA and mention the software and the free monthly report that
    /// clients get" — read at the very top of the call, before any
    /// question.
    private var openingScript: some View {
        scriptLine("Thanks so much for taking the time today. Before we dive in — a bit about me: I hold an MBA, and I run my practice on Voice Ledger, dedicated bookkeeping software that keeps a close eye on your books between our check-ins. Every client also gets a free monthly report on how the business is doing — no extra charge.")
    }

    // MARK: Section 1 — Basic Business Context

    private var sectionBasicContext: some View {
        sectionCard(title: "1. BASIC BUSINESS CONTEXT", accent: VLColor.cyan) {
            questionBlock(question: "What is the legal business name, and what's the entity type — LLC, S-Corp, sole prop?") {
                HStack(spacing: VLSpacing.sm) {
                    labeledField("Business name", text: $intake.legalBusinessName)
                    labeledField("Entity type", text: $intake.entityType)
                }
            }
            questionBlock(question: "What industry are you in, and what are your primary sources of revenue?") {
                HStack(spacing: VLSpacing.sm) {
                    labeledField("Industry", text: $intake.industry)
                    labeledField("Primary revenue sources", text: $intake.primaryRevenueSources)
                }
            }
            questionBlock(question: "How long have you been in business?") {
                labeledField("Years in business", text: $intake.yearsInBusiness)
            }
        }
    }

    // MARK: Section 2 — The Financial Ecosystem (For Accurate Pricing)

    private var sectionFinancialEcosystem: some View {
        sectionCard(title: "2. THE FINANCIAL ECOSYSTEM (FOR ACCURATE PRICING)", accent: VLColor.cyan) {
            rateControl
            questionBlock(question: "What accounting software are you currently using — QuickBooks Online, desktop, Excel, or none?") {
                labeledField("Accounting software", text: $intake.accountingSoftware)
            }
            scriptLine("I currently only work with QuickBooks Online customers.")
            questionBlock(question: "How many active business bank accounts do you have?") {
                VStack(alignment: .leading, spacing: VLSpacing.xs) {
                    labeledField("Bank accounts", text: $intake.bankAccountCountAnswer)
                    Toggle("5+ bank/credit accounts (+1 hr/mo)", isOn: $intake.monthlyFlags.multipleBankAccounts)
                }
            }
            questionBlock(question: "How many active business credit cards are used for expenses?") {
                labeledField("Credit cards", text: $intake.creditCardCountAnswer)
            }
            questionBlock(question: "What's the approximate total number of transactions across all accounts each month?") {
                VStack(alignment: .leading, spacing: VLSpacing.xs) {
                    labeledField("Transactions/month", text: $intake.monthlyTransactionCountAnswer)
                    Text("TRANSACTION VOLUME TIER").font(VLTypography.caption()).foregroundStyle(VLColor.textMuted)
                    Picker("Transactions per month", selection: $intake.volumeTier) {
                        ForEach(PricingCalculator.VolumeTier.allCases) { tier in
                            Text(tier.label).tag(tier)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
            }
            questionBlock(question: "Do you currently have employees on payroll?") {
                Toggle("Payroll processing (+1.5 hrs/mo)", isOn: $intake.monthlyFlags.payrollProcessing)
            }
            questionBlock(question: "Do you collect and remit sales tax?") {
                Toggle("Sales tax management (+1 hr/mo)", isOn: $intake.monthlyFlags.salesTaxManagement)
            }
            questionBlock(question: "Do you track inventory?") {
                Toggle("Inventory tracking (+2 hrs/mo)", isOn: $intake.monthlyFlags.inventoryTracking)
            }
        }
    }

    private var rateControl: some View {
        VStack(alignment: .leading, spacing: VLSpacing.xxs) {
            Text("YOUR RATE (not a client question)")
                .font(VLTypography.caption())
                .foregroundStyle(VLColor.textMuted)
            HStack {
                Text("$").foregroundStyle(VLColor.textMuted)
                TextField("100", text: $intake.hourlyRateText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 100)
                Text("/hr").foregroundStyle(VLColor.textMuted)
            }
        }
    }

    // MARK: Section 3 — Scope of Work & Boundaries

    private var sectionScopeAndBoundaries: some View {
        sectionCard(title: "3. SCOPE OF WORK & BOUNDARIES", accent: VLColor.violet) {
            questionBlock(question: "Are your books currently up to date, or will you need historical clean-up and catch-up work?") {
                VStack(alignment: .leading, spacing: VLSpacing.xs) {
                    labeledField("Books status", text: $intake.booksUpToDateAnswer)
                    Toggle("Needs historical clean-up before ongoing work", isOn: $intake.needsCleanup)
                    if intake.needsCleanup {
                        cleanupDetailControls
                    }
                }
            }
            questionBlock(
                question: "Who currently manages your daily invoicing and collections (Accounts Receivable), and who pays your vendors (Accounts Payable)?",
                caption: "This establishes that the client handles AR/AP internally — your focus stays on reconciliation and month-end close."
            ) {
                labeledField("Who handles AR/AP today", text: $intake.whoManagesARAP)
            }
            questionBlock(question: "Do you use any third-party payment processors or point-of-sale systems — Stripe, Square, PayPal, Wix?") {
                labeledField("Payment processors / POS", text: $intake.paymentProcessors)
            }
        }
    }

    private var cleanupDetailControls: some View {
        VLCard(accentRail: VLColor.violet) {
            VStack(alignment: .leading, spacing: VLSpacing.xs) {
                Text("CLEANUP — DATA HYGIENE ISSUES")
                    .font(VLTypography.eyebrow())
                    .tracking(VLTypography.eyebrowTracking)
                    .foregroundStyle(VLColor.violet)
                Text("MONTHS BEHIND").font(VLTypography.caption()).foregroundStyle(VLColor.textMuted)
                Picker("Months behind", selection: $intake.monthsBehind) {
                    ForEach(PricingCalculator.MonthsBehindTier.allCases) { tier in
                        Text(tier.label).tag(tier)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                Toggle("Multiple uncategorized transactions", isOn: $intake.cleanupIssues.multipleUncategorized)
                Toggle("Personal and business mixed together", isOn: $intake.cleanupIssues.personalBusinessMixed)
                Toggle("Payroll not reconciled", isOn: $intake.cleanupIssues.payrollNotReconciled)
                Toggle("Sales tax not filed", isOn: $intake.cleanupIssues.salesTaxNotFiled)
                Toggle("Inventory tracking issues", isOn: $intake.cleanupIssues.inventoryTrackingIssues)
                Toggle("Negative balances", isOn: $intake.cleanupIssues.negativeBalances)
                Toggle("Duplicated accounts", isOn: $intake.cleanupIssues.duplicatedAccounts)
            }
        }
    }

    // MARK: Section 4 — Workflow & Communication

    private var sectionWorkflowAndCommunication: some View {
        sectionCard(title: "4. WORKFLOW & COMMUNICATION", accent: VLColor.violet) {
            questionBlock(question: "Who will be the primary point of contact for verifying uncategorized transactions and answering month-end questions? What's a great way to reach them?") {
                HStack(spacing: VLSpacing.sm) {
                    labeledField("Name", text: $intake.pointOfContactName)
                    labeledField("Role", text: $intake.pointOfContactRole)
                    labeledField("Email", text: $intake.pointOfContactEmail)
                    labeledField("Phone", text: $intake.pointOfContactPhone)
                }
            }
            questionBlock(question: "How do you prefer to communicate — email, asynchronous video updates, scheduled monthly calls?") {
                labeledField("Preferred communication", text: $intake.communicationPreference)
            }
        }
    }

    // MARK: Section 5 — Goals & Reporting Needs

    private var sectionGoalsAndReporting: some View {
        sectionCard(title: "5. GOALS & REPORTING NEEDS", accent: VLColor.cyan) {
            questionBlock(question: "What are your biggest frustrations with your current bookkeeping process?") {
                labeledField("Frustrations", text: $intake.frustrations, multiline: true)
            }
            questionBlock(question: "Beyond standard financial statements, what specific metrics are you hoping to track? Any executive summaries or KPI alerts that would help you run the business better?") {
                labeledField("Metrics / KPIs they want", text: $intake.desiredMetrics, multiline: true)
            }
            questionBlock(question: "Will these financials be used for tax preparation, applying for a loan, bringing on investors, or internal management?") {
                labeledField("What the financials are for", text: $intake.financialsUse)
            }
        }
    }

    // MARK: Output — findings + quote summary (same math/shape as PricingCalculatorView)

    private var findingsSummarySection: some View {
        VLCard(accentRail: VLColor.violet) {
            VStack(alignment: .leading, spacing: VLSpacing.xs) {
                Text("FINDINGS SUMMARY (AUTO-INCLUDED)")
                    .font(VLTypography.eyebrow())
                    .tracking(VLTypography.eyebrowTracking)
                    .foregroundStyle(VLColor.violet)
                Text("Only meaningful if you're actually connected to this prospect's real QuickBooks data — leave this off for a brand-new prospect you haven't synced yet.")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textMuted)
                Toggle("Include this client's findings in the proposal email", isOn: $intake.includeFindingsSummary)
                    .font(VLTypography.body())
                VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                    ForEach(findingsSummaryLines, id: \.self) { line in
                        Text(line).font(VLTypography.caption()).foregroundStyle(VLColor.textSecondary)
                    }
                }
                .opacity(intake.includeFindingsSummary ? 1 : 0.4)
            }
        }
    }

    private var quoteSummarySection: some View {
        VLCard(accentRail: VLColor.cyan) {
            VStack(alignment: .leading, spacing: VLSpacing.xs) {
                Text("RUNNING QUOTE").font(VLTypography.eyebrow()).tracking(VLTypography.eyebrowTracking).foregroundStyle(VLColor.textMuted)
                if intake.needsCleanup {
                    HStack {
                        Text("One-Time Cleanup").font(VLTypography.body()).foregroundStyle(VLColor.textSecondary)
                        Spacer()
                        Text(cleanupQuote.midpoint.description).font(VLTypography.tabularNumericEmphasis()).foregroundStyle(VLColor.textPrimary)
                    }
                }
                HStack {
                    Text("Monthly Retainer").font(VLTypography.cardTitle()).foregroundStyle(VLColor.textPrimary)
                    Spacer()
                    Text(monthlyQuote.monthlyInvestment.description).font(VLTypography.metricLarge()).foregroundStyle(VLColor.cyan)
                }
                if intake.needsCleanup {
                    Divider().overlay(VLColor.border)
                    HStack {
                        Text("Day-One Total").font(VLTypography.body()).foregroundStyle(VLColor.textSecondary)
                        Spacer()
                        Text(combinedProposal.dayOneTotal.description).font(VLTypography.tabularNumericEmphasis()).foregroundStyle(VLColor.textPrimary)
                    }
                }
                Text("Rounded to the nearest $50.").font(VLTypography.caption()).foregroundStyle(VLColor.textMuted)
            }
        }
    }

    // MARK: Small building blocks

    /// A line the bookkeeper reads aloud, visually distinct from a
    /// question — no answer field, since it's not something the prospect
    /// answers.
    private func scriptLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: VLSpacing.xs) {
            Image(systemName: "quote.bubble.fill").foregroundStyle(VLColor.textMuted)
            Text(text).font(VLTypography.body()).italic().foregroundStyle(VLColor.textSecondary)
        }
        .padding(VLSpacing.sm)
        .background(VLColor.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: VLRadius.card))
    }

    private func sectionCard<Content: View>(title: String, accent: Color, @ViewBuilder content: () -> Content) -> some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.md) {
                Text(title).font(VLTypography.eyebrow()).tracking(VLTypography.eyebrowTracking).foregroundStyle(accent)
                content()
            }
        }
    }

    /// A question to literally ask the prospect, with a caption for
    /// context (shown to the bookkeeper only) and the answer/pricing
    /// controls directly beneath it.
    private func questionBlock<Content: View>(question: String, caption: String? = nil, @ViewBuilder answer: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: VLSpacing.xs) {
            Text(question).font(VLTypography.body()).foregroundStyle(VLColor.textPrimary)
            if let caption {
                Text(caption).font(VLTypography.caption()).italic().foregroundStyle(VLColor.textMuted)
            }
            answer()
        }
        .padding(.vertical, VLSpacing.xs)
    }

    private func labeledField(_ label: String, text: Binding<String>, multiline: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: VLSpacing.xxs) {
            Text(label.uppercased()).font(VLTypography.caption()).foregroundStyle(VLColor.textMuted)
            if multiline {
                TextEditor(text: text)
                    .font(VLTypography.body())
                    .frame(minHeight: 60)
                    .padding(VLSpacing.xxs)
                    .background(VLColor.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: VLRadius.card))
            } else {
                TextField(label, text: text)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
