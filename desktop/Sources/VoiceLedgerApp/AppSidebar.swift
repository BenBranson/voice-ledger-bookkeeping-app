import SwiftUI
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
    case firmCockpit
    case cleanupAssessment
    case balanceSheetIntegrity
    case chartOfAccountsCleanup
    case bankFeedCleanup
    case batchFixes
    case salesTaxReview
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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .findings: return "Findings"
        case .firmCockpit: return "Firm Cockpit"
        case .cleanupAssessment: return "Cleanup Assessment"
        case .balanceSheetIntegrity: return "Balance Sheet Integrity"
        case .chartOfAccountsCleanup: return "Chart of Accounts"
        case .bankFeedCleanup: return "Bank Feed Cleanup"
        case .batchFixes: return "Batch Fixes"
        case .salesTaxReview: return "Sales Tax Review"
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
        case .voiceHistory: return "AI Conversations"
        case .connection: return "Connection"
        case .scopeAndPeriodLock: return "Scope & Period Lock"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.50percent"
        case .findings: return "list.bullet.rectangle.portrait"
        case .firmCockpit: return "square.grid.2x2"
        case .cleanupAssessment: return "checkmark.seal"
        case .balanceSheetIntegrity: return "chart.bar.doc.horizontal"
        case .chartOfAccountsCleanup: return "folder.badge.gearshape"
        case .bankFeedCleanup: return "building.columns"
        case .batchFixes: return "wand.and.stars"
        case .salesTaxReview: return "percent"
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
        }
    }
}

struct SidebarSection: Identifiable {
    let title: String
    let items: [SidebarItem]
    var id: String { title }
}

let sidebarSections: [SidebarSection] = [
    SidebarSection(title: "OVERVIEW", items: [.dashboard, .findings, .firmCockpit]),
    SidebarSection(title: "CLEANUP", items: [.cleanupAssessment, .balanceSheetIntegrity, .chartOfAccountsCleanup, .bankFeedCleanup, .batchFixes, .salesTaxReview]),
    SidebarSection(title: "CLOSE", items: [.monthEndClose, .closePackage, .activityLog]),
    SidebarSection(title: "REPORTS", items: [.balanceSheetReport, .profitAndLossReport, .cashFlowReport, .trialBalanceReport, .agedReceivablesReport, .agedPayablesReport, .generalLedgerReport, .taxes]),
    SidebarSection(title: "CLIENT", items: [.clientMemory]),
    SidebarSection(title: "AI", items: [.voiceHistory]),
    SidebarSection(title: "SETUP", items: [.connection, .scopeAndPeriodLock])
]

struct AppSidebar: View {
    @Binding var selection: SidebarItem?
    let companyName: String
    let periodLabel: String
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
                Section(section.title) {
                    ForEach(section.items) { item in
                        Label(item.title, systemImage: item.icon).tag(item)
                    }
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
                Text(periodLabel)
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textMuted)
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
