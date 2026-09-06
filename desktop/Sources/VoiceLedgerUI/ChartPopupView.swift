import SwiftUI
import Core
import Voice
import DesignSystem

/// Owner directive (2026-09-06): "maybe for making charts it can make a
/// pop up with chart for the graph im asking." Presented as a `.sheet` by
/// `RootView`, bound to `AppState.presentedChart` — a popup, not a full
/// page navigation, reusing this app's existing chart components
/// (`ExpenseDriverBarChart`, `ProfitAndLossWaterfallChart`) plus
/// `RankedMoneyBarChart` for the two chart kinds with no dedicated
/// component of their own. Every number rendered here was computed by
/// `Core` before this view ever saw it — this view only lays it out.
public struct ChartPopupView: View {
    private let request: ChartRequest
    private let onClose: () -> Void

    public init(request: ChartRequest, onClose: @escaping () -> Void) {
        self.request = request
        self.onClose = onClose
    }

    private var title: String {
        switch request {
        case .expenseDrivers(let title, _): return title
        case .vendorSpend(let title, _): return title
        case .paretoCostDrivers(let title, _): return title
        case .incomeVsExpenses(let title, _): return title
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: VLSpacing.md) {
            HStack {
                Text(title)
                    .font(VLTypography.pageTitle())
                    .foregroundStyle(VLColor.textPrimary)
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(VLColor.textMuted)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }

            ScrollView {
                content
            }
        }
        .padding(VLSpacing.pageGutter)
        // Same fix as `FindingComparisonView`: a `maxWidth`/`maxHeight` of
        // `.infinity` gives the sheet a flexible dimension to grow along,
        // so it can be dragged larger instead of being stuck at its
        // minimum size with no resize affordance.
        .frame(minWidth: 520, idealWidth: 620, maxWidth: .infinity,
               minHeight: 380, idealHeight: 460, maxHeight: .infinity)
        .background(VLColor.background)
    }

    @ViewBuilder
    private var content: some View {
        switch request {
        case .expenseDrivers(_, let drivers):
            ExpenseDriverBarChart(drivers: drivers)
        case .vendorSpend(_, let vendors):
            RankedMoneyBarChart(
                title: "Spend by Vendor",
                entries: vendors.map { .init(id: $0.id, label: $0.vendorName, amount: $0.total) }
            )
        case .paretoCostDrivers(_, let drivers):
            RankedMoneyBarChart(title: "Biggest Cost Drivers", entries: Self.paretoEntries(from: drivers))
        case .incomeVsExpenses(_, let segments):
            ProfitAndLossWaterfallChart(segments: segments)
        }
    }

    /// Cumulative percentage of the total across ALL given drivers (not
    /// just the ones actually rendered) — same same-currency guard as
    /// every other sum in this app; falls back to no percentage annotation
    /// (rather than a wrong one) if the drivers mix currencies.
    private static func paretoEntries(from drivers: [TopExpenseDrivers.Driver]) -> [RankedMoneyBarChart.Entry] {
        guard let first = drivers.first, drivers.allSatisfy({ $0.amount.currency == first.amount.currency }) else {
            return drivers.map { .init(id: $0.id, label: $0.label, amount: $0.amount) }
        }
        let total = drivers.reduce(0.0) { $0 + abs($1.amount.majorUnitsDouble) }
        guard total > 0 else { return drivers.map { .init(id: $0.id, label: $0.label, amount: $0.amount) } }
        var runningTotal = 0.0
        return drivers.map { driver in
            runningTotal += abs(driver.amount.majorUnitsDouble)
            return .init(id: driver.id, label: driver.label, amount: driver.amount, cumulativePercent: runningTotal / total * 100)
        }
    }
}
