import SwiftUI
import AppKit
import Core
import DesignSystem

/// What a chart may do with an account the user selects: open it in QBO or
/// show its postings. Read-only; supplied by the app layer.
public struct ChartAccountActions {
    public var qboURL: (String) -> URL?
    public var postings: (String) -> [GeneralLedgerLine]?
    public var isLoadingPostings: (String) -> Bool
    public var loadPostings: (String) -> Void

    public init(qboURL: @escaping (String) -> URL?, postings: @escaping (String) -> [GeneralLedgerLine]?, isLoadingPostings: @escaping (String) -> Bool, loadPostings: @escaping (String) -> Void) {
        self.qboURL = qboURL
        self.postings = postings
        self.isLoadingPostings = isLoadingPostings
        self.loadPostings = loadPostings
    }

    public static var none: ChartAccountActions { ChartAccountActions(qboURL: { _ in nil }, postings: { _ in nil }, isLoadingPostings: { _ in false }, loadPostings: { _ in }) }
}

// MARK: - Shared pieces

private struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(VLTypography.eyebrow())
            .tracking(VLTypography.eyebrowTracking)
            .foregroundStyle(VLColor.textMuted)
    }
}

private struct ChartUnavailable: View {
    let message: String
    var body: some View {
        Text(message)
            .font(VLTypography.caption())
            .foregroundStyle(VLColor.textMuted)
            .frame(maxWidth: .infinity, minHeight: 80)
    }
}

private struct LegendRow: View {
    let item: ChartItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: VLSpacing.xs) {
                Circle().fill(ChartPalette.color(for: item)).frame(width: 9, height: 9)
                Text(item.label)
                    .foregroundStyle(VLColor.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                    .help(item.label)
                if item.value < 0, let note = item.note {
                    Text("· \(note)").foregroundStyle(VLColor.textMuted).lineLimit(1).truncationMode(.tail)
                }
                Spacer(minLength: VLSpacing.xs)
                if let share = item.share {
                    Text(String(format: "%.1f%%", share * 100)).foregroundStyle(VLColor.textMuted).fixedSize()
                }
                Text(item.valueText)
                    .foregroundStyle(item.value < 0 ? Color(red: 0.94, green: 0.42, blue: 0.55) : VLColor.textPrimary)
                    .fixedSize()
            }
            .font(VLTypography.caption())
            .monospacedDigit()
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .background(isSelected ? VLColor.cyan.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.label), \(item.valueText)\(item.note.map { ", \($0)" } ?? "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Persistent detail for the selected account: exact amount, share, what a
/// negative balance means, and read-only ways to dig in.
private struct AccountDetail: View {
    let item: ChartItem
    let shareLabel: String?
    let actions: ChartAccountActions
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: VLSpacing.xxs) {
            HStack {
                Eyebrow(text: "Selected")
                Spacer()
                Button("Clear", action: onClear).buttonStyle(.link).font(VLTypography.caption())
            }
            Text(item.label).font(VLTypography.cardTitle()).foregroundStyle(VLColor.textPrimary)
            HStack(spacing: VLSpacing.sm) {
                Text(item.valueText).font(VLTypography.tabularNumericEmphasis()).foregroundStyle(VLColor.textPrimary)
                if let share = item.share, let shareLabel {
                    Text(String(format: "%.1f%% of %@", share * 100, shareLabel)).font(VLTypography.caption()).foregroundStyle(VLColor.textMuted)
                }
            }
            if let note = item.note {
                Text(note).font(VLTypography.caption()).foregroundStyle(.orange)
            }
            if let accountID = item.accountID {
                HStack(spacing: VLSpacing.sm) {
                    Button(actions.postings(accountID) == nil ? "Show Postings" : "Refresh Postings") { actions.loadPostings(accountID) }
                        .buttonStyle(.bordered)
                        .disabled(actions.isLoadingPostings(accountID))
                    if let url = actions.qboURL(accountID) {
                        Link(destination: url) { Label("Open in QBO", systemImage: "arrow.up.right.square") }
                            .font(VLTypography.caption())
                    }
                }
                if actions.isLoadingPostings(accountID) {
                    ProgressView().controlSize(.small)
                } else if let rows = actions.postings(accountID) {
                    let top = rows.sorted { abs($0.amount?.minorUnits ?? 0) > abs($1.amount?.minorUnits ?? 0) }.prefix(5)
                    Text(rows.isEmpty ? "No postings found." : "Largest \(top.count) of \(rows.count) postings")
                        .font(VLTypography.caption()).foregroundStyle(VLColor.textMuted)
                    ForEach(Array(top.enumerated()), id: \.offset) { _, row in
                        HStack {
                            Text(row.label).frame(width: 78, alignment: .leading)
                            Text(row.transactionType ?? "").frame(width: 110, alignment: .leading)
                            Text(row.name ?? row.memo ?? "").lineLimit(1)
                            Spacer()
                            Text(row.amount?.accountingDescription ?? "")
                        }
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textSecondary)
                        .monospacedDigit()
                    }
                }
            }
        }
        .padding(VLSpacing.sm)
        .background(VLColor.surfaceInset, in: RoundedRectangle(cornerRadius: 8))
    }
}

private func reconcileSelection(_ selected: inout String?, validIDs: Set<String>) {
    if let current = selected, !validIDs.contains(current) { selected = nil }
}

// MARK: - Balance breakdown

public struct BalanceBreakdownCard: View {
    enum Mode: String, CaseIterable, Identifiable {
        case doughnut = "Share"
        case signed = "Signed balances"
        var id: String { rawValue }
    }

    let breakdown: SignedBreakdown?
    let emptyMessage: String
    let actions: ChartAccountActions
    @State private var selectedID: String?
    @State private var mode: Mode = .doughnut

    public init(breakdown: SignedBreakdown?, emptyMessage: String = "Not available — sync to load the Balance Sheet.", actions: ChartAccountActions = .none) {
        self.breakdown = breakdown
        self.emptyMessage = emptyMessage
        self.actions = actions
    }

    private var allItems: [ChartItem] { (breakdown?.positiveItems ?? []) + (breakdown?.negativeItems ?? []) }

    public var body: some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.sm) {
                HStack {
                    Eyebrow(text: breakdown?.title ?? "Balance Sheet")
                    Spacer()
                    if breakdown != nil {
                        Picker("View", selection: $mode) {
                            ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                        .help("Share shows positive balances only; Signed balances shows every account, including negatives, on one axis.")
                    }
                }
                if let b = breakdown, ChartAssets.directory != nil {
                    content(b)
                } else if breakdown != nil {
                    ChartUnavailable(message: "Chart files are missing — run \"npm install\" in report-renderer.")
                } else {
                    ChartUnavailable(message: emptyMessage)
                }
            }
        }
        .onChange(of: breakdown) { _, _ in reconcileSelection(&selectedID, validIDs: Set(allItems.map(\.id))) }
    }

    @ViewBuilder
    private func content(_ b: SignedBreakdown) -> some View {
        let ids = Set(allItems.map(\.id))
        let summary = "\(b.title): positive balances \(b.positiveSubtotalText), negative balances \(b.negativeSubtotalText), net \(b.netText)."
        if mode == .doughnut {
            HStack(alignment: .top, spacing: VLSpacing.md) {
                EChartView(kind: "breakdownDoughnut", data: b, allowedIDs: ids, selectedID: selectedID, summary: summary) { selectedID = $0 }
                    .frame(width: 190, height: 190)
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(b.positiveItems) { item in
                        LegendRow(item: item, isSelected: item.id == selectedID) { selectedID = selectedID == item.id ? nil : item.id }
                    }
                }
            }
            Text(b.percentDenominatorLabel).font(VLTypography.caption()).foregroundStyle(VLColor.textMuted)
            if !b.negativeItems.isEmpty {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Negative balances — not part of the chart or its percentages")
                        .font(VLTypography.caption()).foregroundStyle(Color(red: 0.94, green: 0.42, blue: 0.55))
                    ForEach(b.negativeItems) { item in
                        LegendRow(item: item, isSelected: item.id == selectedID) { selectedID = selectedID == item.id ? nil : item.id }
                            .help(item.note ?? "")
                    }
                }
            }
        } else {
            EChartView(kind: "breakdownDiverging", data: b, allowedIDs: ids, selectedID: selectedID, summary: summary) { selectedID = $0 }
                .frame(height: CGFloat(max(150, 24 * allItems.count + 34)))
            Picker("Account", selection: $selectedID) {
                Text("Choose an account…").tag(String?.none)
                ForEach(allItems) { Text("\($0.label) — \($0.valueText)").tag(String?.some($0.id)) }
            }
            .labelsHidden()
            .fixedSize()
        }
        HStack(spacing: VLSpacing.xs) {
            totalPill("Positive", b.positiveSubtotalText)
            totalPill("Negative", b.negativeSubtotalText)
            totalPill("Net", b.netText, emphasize: true)
        }
        if let reported = b.reportedTotalText {
            Text(b.reconciles ? "Net ties to the QuickBooks total of \(reported)." : "Net does not tie to the QuickBooks total of \(reported).")
                .font(VLTypography.caption())
                .foregroundStyle(b.reconciles ? VLColor.textMuted : .orange)
        }
        if let id = selectedID, let item = allItems.first(where: { $0.id == id }) {
            AccountDetail(item: item, shareLabel: "positive balances", actions: actions) { selectedID = nil }
        }
    }

    private func totalPill(_ label: String, _ value: String, emphasize: Bool = false) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(VLColor.textMuted)
            Text(value).fontWeight(emphasize ? .semibold : .regular).foregroundStyle(VLColor.textPrimary)
        }
        .font(VLTypography.caption())
        .monospacedDigit()
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(VLColor.surfaceInset, in: Capsule())
    }
}

// MARK: - Waterfall

public struct WaterfallCard: View {
    let data: WaterfallData?
    @State private var selectedID: String?

    public init(data: WaterfallData?) { self.data = data }

    public var body: some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.sm) {
                Eyebrow(text: "Revenue to \(data?.steps.last?.label.lowercased() ?? "net income")")
                if let w = data, ChartAssets.directory != nil {
                    let summary = w.steps.map { "\($0.label) \($0.valueText)" }.joined(separator: ", then ")
                    EChartView(kind: "waterfall", data: w, allowedIDs: Set(w.steps.map(\.id)), selectedID: selectedID, summary: summary) { selectedID = $0 }
                        .frame(height: 250)
                    HStack(spacing: VLSpacing.xs) {
                        ForEach(w.steps) { step in
                            Button { selectedID = selectedID == step.id ? nil : step.id } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(step.label).foregroundStyle(VLColor.textMuted).lineLimit(1)
                                    Text(step.valueText).foregroundStyle(VLColor.textPrimary)
                                }
                                .font(VLTypography.caption())
                                .monospacedDigit()
                                .padding(5)
                                .background(step.id == selectedID ? VLColor.cyan.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(step.label) \(step.valueText)")
                        }
                    }
                    if let id = selectedID, let step = w.steps.first(where: { $0.id == id }) {
                        Text(step.kind == "total"
                             ? "\(step.label): \(step.valueText), measured from zero."
                             : "\(step.label): \(step.valueText), taking the running total from \(Money(minorUnits: Int64((step.from * 100).rounded()), currency: .usd).accountingDescription) to \(Money(minorUnits: Int64((step.to * 100).rounded()), currency: .usd).accountingDescription).")
                            .font(VLTypography.caption())
                            .foregroundStyle(VLColor.textSecondary)
                    }
                    Text(w.reconciles ? "Uses QuickBooks' own section totals; ties exactly to reported net income." : (w.note ?? ""))
                        .font(VLTypography.caption())
                        .foregroundStyle(w.reconciles ? VLColor.textMuted : .orange)
                } else {
                    ChartUnavailable(message: data == nil ? "Not available — the P&L has no Total Income or Net Income for this period." : "Chart files are missing — run \"npm install\" in report-renderer.")
                }
            }
        }
        .onChange(of: data) { _, _ in reconcileSelection(&selectedID, validIDs: Set(data?.steps.map(\.id) ?? [])) }
    }
}

// MARK: - Expense categories

public struct ExpenseCategoriesCard: View {
    let data: RankedBars?
    let actions: ChartAccountActions
    @State private var selectedID: String?

    public init(data: RankedBars?, actions: ChartAccountActions = .none) {
        self.data = data
        self.actions = actions
    }

    public var body: some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.sm) {
                Eyebrow(text: "Top expense categories")
                if let r = data, !r.items.isEmpty, ChartAssets.directory != nil {
                    let summary = r.items.map { "\($0.label) \($0.valueText)" }.joined(separator: "; ")
                    EChartView(kind: "rankedBars", data: r, allowedIDs: Set(r.items.map(\.id)), selectedID: selectedID, summary: summary) { selectedID = $0 }
                        .frame(height: CGFloat(max(120, 30 * r.items.count + 10)))
                    HStack {
                        Text("Total operating expenses \(r.totalText)").foregroundStyle(VLColor.textSecondary)
                        Spacer()
                        Text(r.reconciles ? "Ties to QuickBooks" : "QuickBooks reports \(r.reportedTotalText ?? "no total")")
                            .foregroundStyle(r.reconciles ? VLColor.textMuted : .orange)
                    }
                    .font(VLTypography.caption())
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(r.items) { item in
                            LegendRow(item: item, isSelected: item.id == selectedID) { selectedID = selectedID == item.id ? nil : item.id }
                        }
                    }
                    if let id = selectedID, let item = r.items.first(where: { $0.id == id }) {
                        AccountDetail(item: item, shareLabel: "operating expenses", actions: actions) { selectedID = nil }
                    }
                } else {
                    ChartUnavailable(message: data == nil ? "Not available — no Profit & Loss loaded." : (data!.items.isEmpty ? "No operating expenses this period." : "Chart files are missing — run \"npm install\" in report-renderer."))
                }
            }
        }
        .onChange(of: data) { _, _ in reconcileSelection(&selectedID, validIDs: Set(data?.items.map(\.id) ?? [])) }
    }
}

// MARK: - Trends

public struct TrendCard: View {
    enum Mode: String, CaseIterable, Identifiable {
        case revenueExpenses = "Revenue & expenses"
        case net = "Net income"
        var id: String { rawValue }
    }

    let data: TrendData?
    let emptyMessage: String
    @State private var mode: Mode = .revenueExpenses
    @State private var selectedID: String?

    public init(data: TrendData?, emptyMessage: String = "Load history on Client Diagnostics to see monthly trends.") {
        self.data = data
        self.emptyMessage = emptyMessage
    }

    public var body: some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.sm) {
                HStack {
                    Eyebrow(text: "Monthly trend")
                    Spacer()
                    Picker("Series", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                if let t = data, t.points.count >= 2, ChartAssets.directory != nil {
                    let ids = Set(t.points.map(\.period))
                    EChartView(kind: mode == .revenueExpenses ? "trendRevenueExpenses" : "trendNetIncome", data: t, allowedIDs: ids, selectedID: selectedID,
                               summary: "Monthly \(mode.rawValue.lowercased()) for \(t.points.first!.label) through \(t.points.last!.label).") { selectedID = $0 }
                        .frame(height: 220)
                    Picker("Month", selection: $selectedID) {
                        Text("Choose a month…").tag(String?.none)
                        ForEach(t.points, id: \.period) { Text($0.label).tag(String?.some($0.period)) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    if let id = selectedID, let point = t.points.first(where: { $0.period == id }) {
                        HStack(spacing: VLSpacing.md) {
                            Text(point.label).fontWeight(.semibold)
                            Text("Revenue \(money(point.revenue))")
                            Text("Expenses \(money(point.expenses))")
                            Text("Net \(money(point.netIncome))")
                        }
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textSecondary)
                        .monospacedDigit()
                    }
                    Text(t.note).font(VLTypography.caption()).foregroundStyle(VLColor.textMuted)
                } else {
                    ChartUnavailable(message: data == nil || (data?.points.count ?? 0) < 2 ? emptyMessage : "Chart files are missing — run \"npm install\" in report-renderer.")
                }
            }
        }
        .onChange(of: data) { _, _ in reconcileSelection(&selectedID, validIDs: Set(data?.points.map(\.period) ?? [])) }
    }

    private func money(_ value: Double?) -> String {
        value.map { Money(minorUnits: Int64(($0 * 100).rounded()), currency: .usd).accountingDescription } ?? "no data"
    }
}
