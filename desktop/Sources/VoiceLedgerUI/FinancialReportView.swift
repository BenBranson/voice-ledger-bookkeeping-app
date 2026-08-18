import SwiftUI
import Core
import DesignSystem

/// docs/VOICE_LEDGER_SPEC.md Page 12 (Type A), minimal slice: a flattened
/// view of any single QBO financial-statement report (Balance Sheet,
/// Profit & Loss — both verified live to share the same recursive section
/// shape). See `ReportLine`'s doc comment — real QBO section nesting
/// collapsed to an indent depth, not a fully faithful nested UI.
/// **Report responses need normalization and won't be pixel-identical to
/// QBO's rendered reports** (CLAUDE.md) — this shows real numbers straight
/// from the API, not a branded client-ready document (that's the Close
/// Package, not built).
public struct FinancialReportView: View {
    private let title: String
    private let sourceDescription: String
    private let environment: VLEnvironmentTone
    private let lines: [ReportLine]
    private let isLoading: Bool
    private let errorMessage: String?
    private let onRefresh: () -> Void

    public init(
        title: String,
        sourceDescription: String,
        environment: VLEnvironmentTone,
        lines: [ReportLine],
        isLoading: Bool,
        errorMessage: String?,
        onRefresh: @escaping () -> Void
    ) {
        self.title = title
        self.sourceDescription = sourceDescription
        self.environment = environment
        self.lines = lines
        self.isLoading = isLoading
        self.errorMessage = errorMessage
        self.onRefresh = onRefresh
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VLSpacing.md) {
                HStack {
                    Text(title)
                        .font(VLTypography.pageTitle())
                        .foregroundStyle(VLColor.textPrimary)
                    Spacer()
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
            .padding(VLSpacing.pageGutter)
        }
        .background(VLColor.background)
    }
}
