import SwiftUI
import Core
import DesignSystem

/// docs/VOICE_LEDGER_SPEC.md Page 12. See `GeneralLedgerLine`'s doc
/// comment — a real transaction-level ledger grouped by account, not a
/// label+amount tree, so this renders a wide scrollable table rather than
/// reusing `FinancialReportView`'s section-indent layout.
public struct GeneralLedgerReportView: View {
    private let sourceDescription: String
    private let environment: VLEnvironmentTone
    private let lines: [GeneralLedgerLine]
    private let isLoading: Bool
    private let errorMessage: String?
    private let onRefresh: () -> Void
    private let onExport: (ReportExportFormat) -> Void

    public init(
        sourceDescription: String,
        environment: VLEnvironmentTone,
        lines: [GeneralLedgerLine],
        isLoading: Bool,
        errorMessage: String?,
        onRefresh: @escaping () -> Void,
        onExport: @escaping (ReportExportFormat) -> Void = { _ in }
    ) {
        self.sourceDescription = sourceDescription
        self.environment = environment
        self.lines = lines
        self.isLoading = isLoading
        self.errorMessage = errorMessage
        self.onRefresh = onRefresh
        self.onExport = onExport
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VLSpacing.md) {
                HStack {
                    Text("General Ledger")
                        .font(VLTypography.pageTitle())
                        .foregroundStyle(VLColor.textPrimary)
                    Spacer()
                    if !lines.isEmpty {
                        ExportMenuButton(onExport: onExport)
                    }
                    VLEnvironmentBadge(environment)
                }

                HStack {
                    Text(sourceDescription)
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textMuted)
                    Spacer()
                    Button(isLoading ? "Loading…" : "Refresh") { onRefresh() }
                        .disabled(isLoading)
                }

                if let errorMessage {
                    VLCard(accentRail: VLColor.violet) {
                        Text(errorMessage)
                            .font(VLTypography.caption())
                            .foregroundStyle(VLColor.textSecondary)
                    }
                }

                if lines.isEmpty && !isLoading && errorMessage == nil {
                    VLCard {
                        Text("No report loaded yet. Tap Refresh.")
                            .foregroundStyle(VLColor.textMuted)
                    }
                } else {
                    VLCard {
                        ScrollView(.horizontal) {
                            VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                                HStack {
                                    ForEach(["Date", "Type", "Num", "Name", "Memo", "Split", "Amount", "Balance"], id: \.self) { header in
                                        Text(header).font(VLTypography.caption()).foregroundStyle(VLColor.textMuted).frame(width: 110, alignment: .leading)
                                    }
                                }
                                ForEach(lines) { line in
                                    if line.isAccountHeader {
                                        Text(line.label)
                                            .font(VLTypography.cardTitle())
                                            .foregroundStyle(VLColor.textPrimary)
                                            .padding(.top, VLSpacing.xs)
                                    } else {
                                        HStack {
                                            Text(line.label).font(VLTypography.tabularNumeric()).foregroundStyle(line.isSummary ? VLColor.textPrimary : VLColor.textSecondary).frame(width: 110, alignment: .leading)
                                            Text(line.transactionType ?? "").font(VLTypography.body()).foregroundStyle(VLColor.textSecondary).frame(width: 110, alignment: .leading)
                                            Text(line.docNumber ?? "").font(VLTypography.body()).foregroundStyle(VLColor.textSecondary).frame(width: 110, alignment: .leading)
                                            Text(line.name ?? "").font(VLTypography.body()).foregroundStyle(VLColor.textSecondary).frame(width: 110, alignment: .leading)
                                            Text(line.memo ?? "").font(VLTypography.body()).foregroundStyle(VLColor.textSecondary).frame(width: 110, alignment: .leading)
                                            Text(line.split ?? "").font(VLTypography.body()).foregroundStyle(VLColor.textSecondary).frame(width: 110, alignment: .leading)
                                            Text(line.amount?.description ?? "").font(VLTypography.tabularNumeric()).foregroundStyle(line.isSummary ? VLColor.textPrimary : VLColor.textSecondary).frame(width: 110, alignment: .leading)
                                            Text(line.balance?.description ?? "").font(VLTypography.tabularNumeric()).foregroundStyle(line.isSummary ? VLColor.textPrimary : VLColor.textSecondary).frame(width: 110, alignment: .leading)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(VLSpacing.pageGutter)
        }
        .background(VLColor.background)
    }
}
