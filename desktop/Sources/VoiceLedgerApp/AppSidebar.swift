import SwiftUI
import Core
import DesignSystem
import VoiceLedgerUI

/// Every top-level destination `RootView.content` can render, EXCEPT the two
/// parameterized drill-down screens (`.detail`, `.procedure`) — those are
/// reached by tapping into a finding, never directly from the sidebar, and
/// `RootView.sidebarSelection`'s getter maps them back to `.findings` so
/// the "Findings" row stays highlighted while one is open (the same way a
/// Finder sidebar row stays selected while you're looking inside a folder
/// it contains).
///
/// Replaces the old `ToolbarItemGroup` overflow menu (23 buttons behind one
/// arrow at the top of the window) — a real usability problem the owner
/// flagged directly: finding anything, including Voice, meant opening that
/// menu and scanning a flat list. A left-hand sidebar, grouped by workflow
/// stage, makes every destination visible at a glance without hiding any of
/// them and without touching what any individual screen does.
enum SidebarItem: String, CaseIterable, Identifiable {
    /// Owner directive (2026-08-29): a real per-client KPI dashboard — the
    /// app's actual landing screen now (`AppState.screen`'s default). Not
    /// to be confused with the OLD `.dashboard` case, renamed `.findings`
    /// below — that one's title was always "Findings," a naming leftover,
    /// not an actual dashboard.
    case dashboard
    case findings
    /// Owner directive (2026-08-31): a dedicated, always-reachable
    /// exact-dollar-amount lookup across every synced transaction — for
    /// spotting phantom duplicates, split payments, and transposition
    /// errors by amount alone. Distinct from the quick in-view amount
    /// filters on General Ledger/Findings/Cleanup Assessment (narrower,
    /// scoped to what's already on that page) — this one searches
    /// everything synced, from anywhere in the app.
    case amountSearch
    /// Owner directive (2026-08-31): "quote cleanup and monthly ongoing
    /// bookkeeping as two separate line items" — a pricing tool for
    /// discovery calls, usable before a prospect ever connects QBO.
    case pricingCalculator
    /// Owner directive (2026-09-27): a discovery-call script under Pricing
    /// Calculator — the same pricing inputs, scattered next to the intake
    /// question each corresponds to, with a live answer field under every
    /// question, plus the qualitative intake fields (business context,
    /// scope, contacts, goals) the pricing tool alone never captured.
    case intakeQuestions
    case complianceCalendar
    case scopeRequests
    case industrySetup
    case chartsGallery
    case businessDiagnosis
    case firmCockpit
    /// Owner directive (2026-09-06): "build cash flow forecasting."
    case cashFlowForecast
    case diagnostics
    case cleanupAssessment
    case balanceSheetIntegrity
    case chartOfAccountsCleanup
    case bankFeedCleanup
    case batchFixes
    case salesTaxReview
    /// Owner directive (2026-09-06): "build... recurring-vendor
    /// detection."
    case recurringVendors
    case monthEndClose
    case closePackage
    case activityLog
    case balanceSheetReport
    case profitAndLossReport
    case cashFlowReport
    case trialBalanceReport
    case agedReceivablesReport
    case agedPayablesReport
    case generalLedgerReport
    case taxes
    case clientMemory
    case voiceHistory
    case connection
    case scopeAndPeriodLock
    /// Owner directive (2026-09-06): "Voice Ledger should have a settings
    /// menu for audio input... and pick for audio output."
    case audioSettings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .findings: return "Findings"
        case .amountSearch: return "Search by Amount"
        case .pricingCalculator: return "Pricing Calculator"
        case .intakeQuestions: return "Intake Questions"
        case .complianceCalendar: return "Compliance Calendar"
        case .scopeRequests: return "Scope Requests"
        case .industrySetup: return "Industry Setup"
        case .chartsGallery: return "Charts & Cards"
        case .businessDiagnosis: return "Business Diagnosis"
        case .firmCockpit: return "Firm Cockpit"
        case .cashFlowForecast: return "Cash Flow Forecast"
        case .diagnostics: return "Client Diagnostics"
        case .cleanupAssessment: return "Cleanup Assessment"
        case .balanceSheetIntegrity: return "Balance Sheet Integrity"
        case .chartOfAccountsCleanup: return "Chart of Accounts"
        case .bankFeedCleanup: return "Bank Feed Cleanup"
        case .batchFixes: return "Batch Fixes"
        case .salesTaxReview: return "Sales Tax Review"
        case .recurringVendors: return "Recurring Vendors"
        case .monthEndClose: return "Month-End Close"
        case .closePackage: return "Close Package"
        case .activityLog: return "Activity Log"
        case .balanceSheetReport: return "Balance Sheet"
        case .profitAndLossReport: return "Profit & Loss"
        case .cashFlowReport: return "Cash Flow"
        case .trialBalanceReport: return "Trial Balance"
        case .agedReceivablesReport: return "Aged Receivables"
        case .agedPayablesReport: return "Aged Payables"
        case .generalLedgerReport: return "General Ledger"
        case .taxes: return "Taxes"
        case .clientMemory: return "Client Memory"
        case .voiceHistory: return "Voice History"
        case .connection: return "Connection"
        case .scopeAndPeriodLock: return "Scope & Period Lock"
        case .audioSettings: return "Audio Settings"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.50percent"
        case .findings: return "list.bullet.rectangle.portrait"
        case .amountSearch: return "magnifyingglass.circle"
        case .pricingCalculator: return "dollarsign.circle"
        case .intakeQuestions: return "checklist"
        case .complianceCalendar: return "calendar"
        case .scopeRequests: return "dollarsign.square"
        case .industrySetup: return "wrench.and.screwdriver"
        case .chartsGallery: return "rectangle.stack"
        case .businessDiagnosis: return "stethoscope"
        case .firmCockpit: return "square.grid.2x2"
        case .cashFlowForecast: return "chart.line.uptrend.xyaxis.circle"
        case .diagnostics: return "stethoscope"
        case .cleanupAssessment: return "checkmark.seal"
        case .balanceSheetIntegrity: return "chart.bar.doc.horizontal"
        case .chartOfAccountsCleanup: return "folder.badge.gearshape"
        case .bankFeedCleanup: return "building.columns"
        case .batchFixes: return "wand.and.stars"
        case .salesTaxReview: return "percent"
        case .recurringVendors: return "arrow.triangle.2.circlepath.circle"
        case .monthEndClose: return "calendar.badge.clock"
        case .closePackage: return "shippingbox"
        case .activityLog: return "clock.arrow.circlepath"
        case .balanceSheetReport: return "chart.bar"
        case .profitAndLossReport: return "chart.line.uptrend.xyaxis"
        case .cashFlowReport: return "arrow.left.arrow.right.circle"
        case .trialBalanceReport: return "equal.circle"
        case .agedReceivablesReport: return "arrow.down.circle"
        case .agedPayablesReport: return "arrow.up.circle"
        case .generalLedgerReport: return "book.closed"
        case .taxes: return "banknote"
        case .clientMemory: return "brain"
        case .voiceHistory: return "bubble.left.and.text.bubble.right"
        case .connection: return "link"
        case .scopeAndPeriodLock: return "lock.shield"
        case .audioSettings: return "waveform.badge.mic"
        }
    }
}

struct SidebarSection: Identifiable {
    let title: String
    let items: [SidebarItem]
    var id: String { title }
}

let sidebarSections: [SidebarSection] = [
    SidebarSection(title: "OVERVIEW", items: [.dashboard, .businessDiagnosis, .chartsGallery, .findings, .firmCockpit, .complianceCalendar, .cashFlowForecast, .amountSearch, .pricingCalculator, .intakeQuestions]),
    SidebarSection(title: "CLEANUP", items: [.diagnostics, .cleanupAssessment, .balanceSheetIntegrity, .chartOfAccountsCleanup, .bankFeedCleanup, .batchFixes, .salesTaxReview, .recurringVendors]),
    SidebarSection(title: "CLOSE", items: [.monthEndClose, .closePackage, .activityLog]),
    SidebarSection(title: "REPORTS", items: [.balanceSheetReport, .profitAndLossReport, .cashFlowReport, .trialBalanceReport, .agedReceivablesReport, .agedPayablesReport, .generalLedgerReport, .taxes]),
    SidebarSection(title: "CLIENT", items: [.scopeRequests, .industrySetup, .clientMemory]),
    SidebarSection(title: "AI", items: [.voiceHistory]),
    SidebarSection(title: "SETUP", items: [.connection, .scopeAndPeriodLock, .audioSettings])
]

struct AppSidebar: View {
    @Binding var selection: SidebarItem?
    let companyName: String
    let periodLabel: String
    var periodChoices: [AccountingPeriod] = []
    var onChangePeriod: (AccountingPeriod) -> Void = { _ in }
    let environmentTone: VLEnvironmentTone
    let isSyncing: Bool
    let onSync: () -> Void
    let isVoiceListening: Bool
    let isVoiceProcessing: Bool
    let onToggleVoice: () -> Void
    /// Owner directive (2026-08-29): "the letters for Voice Ledger at the
    /// top left should act as a home button."
    let onGoHome: () -> Void

    var body: some View {
        List(selection: $selection) {
            ForEach(sidebarSections) { section in
                let sectionColor = VLNavColor.forSection(section.title)
                Section {
                    ForEach(section.items) { item in
                        Label {
                            // Owner directive (2026-09-06): "the left panel
                            // is currently just white font" — every row's
                            // icon now carries its section's full color and
                            // its text a softer tint of that same color, so
                            // sections are tellable apart at a glance
                            // (ADHD-friendly categorization) without
                            // reaching for the accounting status vocabulary
                            // (`VLStatus`) or losing legibility.
                            Text(item.title).foregroundStyle(sectionColor.opacity(0.82))
                        } icon: {
                            Image(systemName: item.icon).foregroundStyle(sectionColor)
                        }
                        .tag(item)
                    }
                } header: {
                    Text(section.title)
                        .foregroundStyle(sectionColor)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) {
            header
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: VLSpacing.xs) {
            HStack(spacing: VLSpacing.xs) {
                Button(action: onGoHome) {
                    HStack(spacing: VLSpacing.xs) {
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(VLColor.cyan)
                        Text("Voice Ledger")
                            .font(VLTypography.cardTitle())
                            .foregroundStyle(VLColor.textPrimary)
                    }
                }
                .buttonStyle(.plain)
                .help("Go to Dashboard")
                Spacer()
                Text("v1.80")
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(VLColor.textMuted)
                voiceMicButton
                Button(action: onSync) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .rotationEffect(.degrees(isSyncing ? 360 : 0))
                        .animation(isSyncing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isSyncing)
                }
                .buttonStyle(.plain)
                .disabled(isSyncing)
                .help("Sync")
            }
            VStack(alignment: .leading, spacing: VLSpacing.hairline) {
                Text(companyName)
                    .font(VLTypography.label())
                    .foregroundStyle(VLColor.textSecondary)
                    .lineLimit(1)
                // The reviewed month, changeable (2026-10-02; it was fixed to July 2026).
                Menu {
                    ForEach(periodChoices, id: \.self) { p in
                        Button(ReviewPeriod.label(p) + (p == periodChoices.first ? " (in progress)" : "")) { onChangePeriod(p) }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(periodLabel).font(VLTypography.caption()).foregroundStyle(VLColor.textSecondary)
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(VLColor.textMuted)
                    }
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Month being reviewed")
            }
            VLEnvironmentBadge(environmentTone)
        }
        .padding(.horizontal, VLSpacing.md)
        .padding(.top, VLSpacing.md)
        .padding(.bottom, VLSpacing.sm)
        // Real, live-reported bug (2026-08-29): without an opaque
        // background here, the List's own rows show through/overlap this
        // header once scrolled — `safeAreaInset` reserves layout space but
        // doesn't itself paint anything behind its content, so the header
        // needs its own solid fill to actually occlude what scrolls
        // underneath it.
        .background(VLColor.background)
    }

    /// A top icon button, not a bottom text row — the owner's own ask
    /// (2026-08-29): a plain circular mic glyph, filled solid red only
    /// while actually listening; an outline/silhouette otherwise, so its
    /// state reads at a glance without text.
    private var voiceMicButton: some View {
        Button(action: onToggleVoice) {
            Image(systemName: isVoiceListening ? "mic.fill" : "mic")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isVoiceListening ? .white : VLColor.textMuted)
                .frame(width: 30, height: 30)
                .background(isVoiceListening ? Color.red : VLColor.surfaceElevated)
                .clipShape(Circle())
                .overlay(
                    Circle().stroke(isVoiceListening ? Color.red : VLColor.border, lineWidth: VLBorder.hairline)
                )
        }
        .buttonStyle(.plain)
        .help(isVoiceListening ? "Listening… click to stop" : (isVoiceProcessing ? "Thinking…" : "Start a conversation"))
    }
}
