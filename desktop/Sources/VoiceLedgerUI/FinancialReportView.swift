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
    private let onExport: (ReportExportFormat) -> Void
    /// Variance analysis (docs/VOICE_LEDGER_SPEC.md's Firm Cockpit Close
    /// Package section) — optional so this view's other 6 call sites (Cash
    /// Flow, and every report before this was added) need no changes.
    /// `nil` prior lines and `false` loading/no error is the same as never
    /// having asked for a comparison at all.
    private let priorPeriodLines: [ReportLine]?
    private let priorPeriodLabel: String?
    private let isLoadingVariance: Bool
    private let varianceError: String?
    private let onLoadVariance: (() -> Void)?

    public init(
        title: String,
        sourceDescription: String,
        environment: VLEnvironmentTone,
        lines: [ReportLine],
        isLoading: Bool,
        errorMessage: String?,
        onRefresh: @escaping () -> Void,
        onExport: @escaping (ReportExportFormat) -> Void = { _ in },
        priorPeriodLines: [ReportLine]? = nil,
        priorPeriodLabel: String? = nil,
        isLoadingVariance: Bool = false,
        varianceError: String? = nil,
        onLoadVariance: (() -> Void)? = nil
    ) {
        self.title = title
        self.sourceDescription = sourceDescription
        self.environment = environment
        self.lines = lines
        self.isLoading = isLoading
        self.errorMessage = errorMessage
        self.onRefresh = onRefresh
        self.onExport = onExport
        self.priorPeriodLines = priorPeriodLines
        self.priorPeriodLabel = priorPeriodLabel
        self.isLoadingVariance = isLoadingVariance
        self.varianceError = varianceError
        self.onLoadVariance = onLoadVariance
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VLSpacing.md) {
                HStack {
                    Text(title)
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

                if onLoadVariance != nil {
                    varianceSection
                }
            }
            .padding(VLSpacing.pageGutter)
        }
        .background(VLColor.background)
    }

    private var varianceSection: some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.xs) {
                HStack {
                    Text("VS. \(priorPeriodLabel ?? "PRIOR PERIOD")")
                        .font(VLTypography.eyebrow())
                        .tracking(VLTypography.eyebrowTracking)
                        .foregroundStyle(VLColor.textMuted)
                    Spacer()
                    if let priorPeriodLines, !priorPeriodLines.isEmpty {
                        EmptyView()
                    } else {
                        Button(isLoadingVariance ? "Loading…" : "Compare to prior period") { onLoadVariance?() }
                            .disabled(isLoadingVariance)
                            .font(VLTypography.caption())
                    }
                }

                if let varianceError {
                    Text(varianceError)
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textSecondary)
                }

                if let priorPeriodLines, !priorPeriodLines.isEmpty {
                    let varianceLines = VarianceAnalysis.compute(current: lines, prior: priorPeriodLines)
                    VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                        ForEach(varianceLines) { vline in
                            HStack {
                                Text(vline.label)
                                    .font(vline.isSummary ? VLTypography.cardTitle() : VLTypography.body())
                                    .foregroundStyle(vline.isSummary ? VLColor.textPrimary : VLColor.textSecondary)
                                    .padding(.leading, CGFloat(vline.depth) * 16)
                                Spacer()
                                Text(vline.priorAmount?.description ?? "—")
                                    .font(VLTypography.tabularNumeric())
                                    .foregroundStyle(VLColor.textMuted)
                                    .frame(minWidth: 90, alignment: .trailing)
                                if let change = vline.change {
                                    Text("\(change.minorUnits >= 0 ? "+" : "")\(change.description)")
                                        .font(VLTypography.tabularNumeric())
                                        .foregroundStyle(change.minorUnits >= 0 ? VLColor.textPrimary : .red)
                                        .frame(minWidth: 90, alignment: .trailing)
                                } else {
                                    Text("—").font(VLTypography.tabularNumeric()).foregroundStyle(VLColor.textMuted).frame(minWidth: 90, alignment: .trailing)
                                }
                                if let percent = vline.percentChange {
                                    Text("\(percent >= 0 ? "+" : "")\(String(format: "%.1f", percent * 100))%")
                                        .font(VLTypography.tabularNumeric())
                                        .foregroundStyle(percent >= 0 ? VLColor.textPrimary : .red)
                                        .frame(minWidth: 60, alignment: .trailing)
                                } else {
                                    Text("—").font(VLTypography.tabularNumeric()).foregroundStyle(VLColor.textMuted).frame(minWidth: 60, alignment: .trailing)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
