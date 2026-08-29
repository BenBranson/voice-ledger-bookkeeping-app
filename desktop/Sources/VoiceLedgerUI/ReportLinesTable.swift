import SwiftUI
import Core
import DesignSystem

/// The indented, summary-bolded line-item table shared by every financial
/// report screen — extracted from `FinancialReportView` so the Balance
/// Sheet/P&L visual-layer screens (`BalanceSheetReportView`,
/// `ProfitAndLossReportView`) can show the exact same full detailed table
/// underneath their new charts, rather than reimplementing it.
public struct ReportLinesTable: View {
    private let lines: [ReportLine]

    public init(lines: [ReportLine]) {
        self.lines = lines
    }

    public var body: some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                ForEach(lines) { line in
                    HStack {
                        Text(line.label)
                            .font(line.isSummary ? VLTypography.cardTitle() : VLTypography.body())
                            .foregroundStyle(line.isSummary ? VLColor.textPrimary : VLColor.textSecondary)
                            .padding(.leading, CGFloat(line.depth) * 16)
                        Spacer()
                        if let amount = line.amount {
                            Text(amount.description)
                                .font(VLTypography.tabularNumeric())
                                .foregroundStyle(line.isSummary ? VLColor.textPrimary : VLColor.textSecondary)
                        }
                    }
                }
            }
        }
    }
}
