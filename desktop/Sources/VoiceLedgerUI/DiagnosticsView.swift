import SwiftUI
import AppKit
import Core
import DesignSystem

/// Client Diagnostics (owner feature list 2026-09-29): cleanup scope score
/// and quote, stale bank-feed sentinel, flux alerts, and a paste-ready KPI
/// summary — all computed by `ClientDiagnostics` from a multi-month
/// `HistorySnapshot`. Nothing here is shown until real history is loaded.
public struct DiagnosticsView: View {
    public struct ViewState {
        public let environment: VLEnvironmentTone
        public let historyRange: String?
        public let historyFetchedAt: Date?
        public let isLoadingHistory: Bool
        public let historyError: String?
        public let scope: CleanupScopeScore?
        public let feeds: [BankFeedActivity]
        public let flux: [FluxAlert]
        public let kpi: KPISummary?
        public let unreconciledMonths: Int
        public var history: HistorySnapshot? = nil

        public init(environment: VLEnvironmentTone, historyRange: String?, historyFetchedAt: Date?, isLoadingHistory: Bool, historyError: String?, scope: CleanupScopeScore?, feeds: [BankFeedActivity], flux: [FluxAlert], kpi: KPISummary?, unreconciledMonths: Int, history: HistorySnapshot? = nil) {
            self.history = history
            self.environment = environment
            self.historyRange = historyRange
            self.historyFetchedAt = historyFetchedAt
            self.isLoadingHistory = isLoadingHistory
            self.historyError = historyError
            self.scope = scope
            self.feeds = feeds
            self.flux = flux
            self.kpi = kpi
            self.unreconciledMonths = unreconciledMonths
        }
    }

    private let state: ViewState
    private let onLoadHistory: () -> Void
    private let onSetUnreconciledMonths: (Int) -> Void

    public init(state: ViewState, onLoadHistory: @escaping () -> Void, onSetUnreconciledMonths: @escaping (Int) -> Void) {
        self.state = state
        self.onLoadHistory = onLoadHistory
        self.onSetUnreconciledMonths = onSetUnreconciledMonths
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VLSpacing.md) {
                HStack {
                    Text("Client Diagnostics")
                        .font(VLTypography.pageTitle())
                        .foregroundStyle(VLColor.textPrimary)
                    Spacer()
                    Button(state.isLoadingHistory ? "Loading history…" : (state.historyRange == nil ? "Load 24-Month History" : "Refresh History")) {
                        onLoadHistory()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(state.isLoadingHistory)
                    VLEnvironmentBadge(state.environment)
                }

                Text(historyCaption)
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textMuted)
                if let error = state.historyError {
                    Text("History load failed: \(error)")
                        .font(VLTypography.caption())
                        .foregroundStyle(.red)
                }

                if state.historyRange == nil {
                    VLCard {
                        Text(state.isLoadingHistory ? "Pulling 24 months from QuickBooks — usually under a minute." : "No history loaded for this client yet. Load it to get the scope score, quote, stale-feed check, flux alerts, and KPI summary.")
                            .foregroundStyle(VLColor.textMuted)
                    }
                } else {
                    if let scope = state.scope { scopeCard(scope) }
                    feedsCard
                    PostingCalendarCard(history: state.history, accounts: state.feeds.map { (id: $0.accountID, label: $0.accountName) })
                    fluxCard
                    if let kpi = state.kpi { kpiCard(kpi) }
                }
            }
            .padding(VLSpacing.pageGutter)
        }
        .background(VLColor.background)
    }

    private var historyCaption: String {
        guard let range = state.historyRange else {
            return "Read-only. Pulls every transaction type, 24 monthly P&Ls, and the latest balance sheet and cash flow, in 3-month chunks."
        }
        let fetched = state.historyFetchedAt.map { " · loaded \($0.formatted(.relative(presentation: .named)))" } ?? ""
        return "History: \(range)\(fetched). Read-only."
    }

    private func eyebrow(_ text: String) -> some View {
        Text(text)
            .font(VLTypography.eyebrow())
            .tracking(VLTypography.eyebrowTracking)
            .foregroundStyle(VLColor.textMuted)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(VLColor.textSecondary)
            Spacer()
            Text(value).foregroundStyle(VLColor.textPrimary).monospacedDigit()
        }
        .font(VLTypography.body())
    }

    private func scopeCard(_ scope: CleanupScopeScore) -> some View {
        VLCard(accentRail: VLColor.violet) {
            VStack(alignment: .leading, spacing: VLSpacing.xs) {
                eyebrow("CLEANUP SCOPE SCORE")
                HStack(alignment: .firstTextBaseline, spacing: VLSpacing.sm) {
                    Text("\(scope.score)")
                        .font(VLTypography.metricLarge())
                        .foregroundStyle(VLColor.textPrimary)
                    Text("/ 100 · \(scope.band)")
                        .font(VLTypography.cardTitle())
                        .foregroundStyle(VLColor.textSecondary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: VLSpacing.xxs) {
                        Text("Recommended cleanup: \(scope.cleanupQuote.accountingDescription)")
                            .font(VLTypography.cardTitle())
                            .foregroundStyle(VLColor.cyan)
                        Text("\(scope.estimatedHoursLow)–\(scope.estimatedHoursHigh) est. hours · retainer \(scope.monthlyRetainer.monthlyInvestment.accountingDescription)/mo")
                            .font(VLTypography.caption())
                            .foregroundStyle(VLColor.textMuted)
                    }
                }
                Divider().overlay(VLColor.border)
                HStack {
                    Text("Unreconciled months (enter from the client's reconciliation reports)")
                        .foregroundStyle(VLColor.textSecondary)
                    Spacer()
                    Stepper("\(state.unreconciledMonths)", value: Binding(get: { state.unreconciledMonths }, set: { onSetUnreconciledMonths(max(0, $0)) }), in: 0...60)
                        .fixedSize()
                }
                .font(VLTypography.body())
                row("Months scanned", "\(scope.monthsScanned)")
                row("Average transactions / month", "\(scope.averageMonthlyTransactions) (\(scope.volumeTier.label))")
                row("Open anomalies", "\(scope.openAnomalies)")
                row("Uncategorized transactions", "\(scope.uncategorizedTransactions)")
                row("Payments not yet deposited", "\(scope.undepositedPaymentCount) · \(scope.undepositedPaymentTotal.accountingDescription)")
                row("…of those, older than 90 days", "\(scope.agedOver90Count)")
                row("Unapplied vendor credits", scope.unappliedVendorCreditTotal.accountingDescription)
                row("Duplicate-looking chart of accounts groups", "\(scope.duplicateAccountGroups)")
                row("Total dollar exposure (open findings)", scope.totalExposure.accountingDescription)
                Text("Quote = base $500 + $150 × unreconciled months + $35 × anomalies + $2.50 × uncategorized transactions; hours at $100/hr. QuickBooks' API has no reconciliation history or cleared status, so unreconciled months is your input and \"older than 90 days\" uses undeposited payments as the stand-in.")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textMuted)
            }
        }
    }

    private var feedsCard: some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.xs) {
                eyebrow("BANK FEED ACTIVITY — STALE AFTER \(ClientDiagnostics.staleFeedThresholdDays) DAYS")
                if state.feeds.isEmpty {
                    Text("No bank or credit card accounts found.").foregroundStyle(VLColor.textMuted)
                }
                ForEach(state.feeds) { feed in
                    HStack {
                        VLStatusPill(feed.isStale ? .reviewNeeded : .verified, label: feed.isStale ? "Stale" : "Active")
                        Text(feed.accountName).foregroundStyle(VLColor.textPrimary)
                        Spacer()
                        Text(feed.lastActivity.map { "Last posting \($0.formatted) · \(feed.daysSinceLastActivity ?? 0) days ago" } ?? "No postings in the loaded history")
                            .foregroundStyle(VLColor.textSecondary)
                            .monospacedDigit()
                    }
                    .font(VLTypography.body())
                }
                Text("Inferred from the newest posted transaction on each account — QuickBooks' API can't see bank-feed connection status. A stale account usually means the feed stopped pulling or \"For Review\" items haven't been accepted.")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textMuted)
            }
        }
    }

    private var fluxCard: some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.xs) {
                eyebrow("FLUX — LATEST MONTH VS 3-MONTH TRAILING AVERAGE (>20% AND >$500)")
                if state.flux.isEmpty {
                    Text("No P&L line swung more than 20% and $500 against its trailing average (or fewer than 4 complete months are loaded).")
                        .foregroundStyle(VLColor.textMuted)
                }
                ForEach(state.flux) { alert in
                    HStack {
                        Text(alert.label).foregroundStyle(VLColor.textPrimary)
                        Spacer()
                        Text("\(alert.current.accountingDescription) vs avg \(alert.trailingAverage.accountingDescription)")
                            .foregroundStyle(VLColor.textSecondary)
                        Text(alert.percentChange.map { String(format: "%+.0f%%", $0 * 100) } ?? "new")
                            .foregroundStyle(alert.change.minorUnits > 0 ? VLColor.cyan : VLColor.violet)
                            .frame(width: 60, alignment: .trailing)
                    }
                    .font(VLTypography.body())
                    .monospacedDigit()
                }
            }
        }
    }

    private func kpiCard(_ kpi: KPISummary) -> some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.xs) {
                HStack {
                    eyebrow("KPI SUMMARY — READY FOR THE CLIENT REVIEW EMAIL")
                    Spacer()
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(kpi.emailBullets.map { "• \($0)" }.joined(separator: "\n"), forType: .string)
                    }
                }
                ForEach(kpi.emailBullets, id: \.self) { bullet in
                    Text("• \(bullet)")
                        .font(VLTypography.body())
                        .foregroundStyle(VLColor.textPrimary)
                        .textSelection(.enabled)
                }
            }
        }
    }
}
