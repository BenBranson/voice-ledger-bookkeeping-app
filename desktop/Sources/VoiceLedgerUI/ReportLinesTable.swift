import SwiftUI
import Core
import DesignSystem

/// Set by a report screen to let each row be clicked to ask the local AI
/// about it (owner request 2026-09-29). `nil` = rows aren't clickable.
private struct AskAIAboutReportRowKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: ((ReportLine) -> Void)? = nil
}

public extension EnvironmentValues {
    var askAIAboutReportRow: ((ReportLine) -> Void)? {
        get { self[AskAIAboutReportRowKey.self] }
        set { self[AskAIAboutReportRowKey.self] = newValue }
    }
}

/// The indented, summary-bolded line-item table shared by every financial
/// report screen — extracted from `FinancialReportView` so the Balance
/// Sheet/P&L visual-layer screens (`BalanceSheetReportView`,
/// `ProfitAndLossReportView`) can show the exact same full detailed table
/// underneath their new charts, rather than reimplementing it.
public struct ReportLinesTable: View {
    private let lines: [ReportLine]
    @Environment(\.askAIAboutReportRow) private var askAI
    @State private var askedID: String?
    @State private var hoveredID: String?

    public init(lines: [ReportLine]) {
        self.lines = lines
    }

    public var body: some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                if askAI != nil {
                    Text(askedID.flatMap { id in lines.first { $0.id == id } }.map { "Asked the local AI about “\($0.label)” — the answer appears in the Ask AI panel below." }
                         ?? "Click any row to ask the local AI about it (runs on this Mac, not online).")
                        .font(VLTypography.caption())
                        .foregroundStyle(askedID == nil ? VLColor.textMuted : VLColor.cyan)
                        .padding(.bottom, VLSpacing.xxs)
                }
                ForEach(lines) { line in
                    row(line)
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ line: ReportLine) -> some View {
        let content = HStack {
            Text(line.label)
                .font(line.isSummary ? VLTypography.cardTitle() : VLTypography.body())
                .foregroundStyle(line.isSummary ? VLColor.textPrimary : VLColor.textSecondary)
                .padding(.leading, CGFloat(line.depth) * 16)
            Spacer()
            if askAI != nil && (hoveredID == line.id || askedID == line.id) {
                Image(systemName: "sparkles").font(.caption).foregroundStyle(VLColor.cyan)
            }
            if let amount = line.amount {
                Text(amount.accountingDescription)
                    .font(VLTypography.tabularNumeric())
                    .foregroundStyle(line.isSummary ? VLColor.textPrimary : VLColor.textSecondary)
            }
        }
        if let askAI {
            content
                .padding(.horizontal, 4)
                .background(RoundedRectangle(cornerRadius: 4).fill(askedID == line.id ? VLColor.cyan.opacity(0.14) : hoveredID == line.id ? VLColor.textMuted.opacity(0.10) : .clear))
                .contentShape(Rectangle())
                .onHover { hoveredID = $0 ? line.id : (hoveredID == line.id ? nil : hoveredID) }
                .onTapGesture {
                    askedID = line.id
                    askAI(line)
                }
                .help("Ask the local AI about “\(line.label)”")
        } else {
            content
        }
    }
}
