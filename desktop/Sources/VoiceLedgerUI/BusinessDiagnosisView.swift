import SwiftUI
import Charts
import Core
import DesignSystem

/// Business Diagnosis page (owner request 2026-10-02): a SWOT read of the
/// client's business, visual first. Every item is computed by
/// `BusinessDiagnosis` from stated thresholds; the AI only writes the
/// optional plain-English explanation of these exact items.
public struct BusinessDiagnosisView: View {
    let companyName: String
    let report: BusinessDiagnosis.Report
    /// Tie-out failures put the whole diagnosis on hold (CLAUDE.md rule 5).
    let untied: [TieOut.Check]
    let environment: VLEnvironmentTone
    let explanation: String?
    let isExplaining: Bool
    let explainError: String?
    let onExplain: () -> Void

    @Environment(\.qboLinks) private var links

    public init(companyName: String, report: BusinessDiagnosis.Report, untied: [TieOut.Check], environment: VLEnvironmentTone,
                explanation: String?, isExplaining: Bool, explainError: String?, onExplain: @escaping () -> Void) {
        self.companyName = companyName; self.report = report; self.untied = untied; self.environment = environment
        self.explanation = explanation; self.isExplaining = isExplaining; self.explainError = explainError; self.onExplain = onExplain
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VLSpacing.lg) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Business Diagnosis").font(VLTypography.pageTitle()).foregroundStyle(VLColor.textPrimary)
                        Text("\(companyName) · \(ReviewPeriod.label(report.period)) · computed from QuickBooks")
                            .font(VLTypography.caption()).foregroundStyle(VLColor.textMuted)
                    }
                    Spacer()
                    VLEnvironmentBadge(environment)
                }

                if !untied.isEmpty {
                    VLCard {
                        Label("On hold: \(untied.count) number\(untied.count == 1 ? "" : "s") don't tie to QuickBooks (\(untied.map(\.title).joined(separator: ", "))). The diagnosis would rest on figures that aren't verified. Sync again, or check the Dashboard's tie-out.",
                              systemImage: "exclamationmark.octagon.fill")
                            .font(VLTypography.body()).foregroundStyle(VLStatus.urgent.color)
                    }
                } else {
                    swotGrid
                    HStack(alignment: .top, spacing: VLSpacing.md) {
                        moneyGoes.frame(maxWidth: .infinity)
                        trendChart.frame(maxWidth: .infinity)
                    }
                    if !report.notJudged.isEmpty {
                        VLCard {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("NOT JUDGED YET").font(VLTypography.eyebrow()).tracking(VLTypography.eyebrowTracking).foregroundStyle(VLColor.textMuted)
                                ForEach(report.notJudged, id: \.self) { Text("– " + $0).font(VLTypography.caption()).foregroundStyle(VLColor.textMuted) }
                            }
                        }
                    }
                    explainCard
                }
            }
            .padding(VLSpacing.pageGutter)
        }
        .background(VLColor.background)
    }

    // MARK: SWOT

    private var swotGrid: some View {
        Grid(horizontalSpacing: VLSpacing.md, verticalSpacing: VLSpacing.md) {
            GridRow { quadrant(.strength); quadrant(.weakness) }
            GridRow { quadrant(.opportunity); quadrant(.threat) }
        }
    }

    private func style(_ q: BusinessDiagnosis.Quadrant) -> (Color, String) {
        switch q {
        case .strength: return (VLStatus.verified.color, "arrow.up.right.circle.fill")
        case .weakness: return (VLStatus.reviewNeeded.color, "exclamationmark.triangle.fill")
        case .opportunity: return (VLColor.cyan, "lightbulb.fill")
        case .threat: return (VLStatus.urgent.color, "bolt.shield.fill")
        }
    }

    private func quadrant(_ q: BusinessDiagnosis.Quadrant) -> some View {
        let (color, icon) = style(q)
        let items = report.items(q)
        return VStack(alignment: .leading, spacing: VLSpacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(color)
                Text(q.rawValue.uppercased()).font(VLTypography.eyebrow()).tracking(VLTypography.eyebrowTracking).foregroundStyle(color)
                Spacer()
                Text("\(items.count)").font(VLTypography.label()).foregroundStyle(color)
            }
            if items.isEmpty {
                Text(q == .strength || q == .opportunity ? "None found at the stated thresholds." : "Nothing at the stated thresholds.")
                    .font(VLTypography.caption()).foregroundStyle(VLColor.textMuted)
            }
            ForEach(items) { item in itemRow(item) }
            Spacer(minLength: 0)
        }
        .padding(VLSpacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: VLRadius.card).fill(color.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: VLRadius.card).strokeBorder(color.opacity(0.45), lineWidth: 1))
    }

    private func itemRow(_ item: BusinessDiagnosis.Item) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.title).font(VLTypography.label()).foregroundStyle(VLColor.textPrimary)
                Spacer()
                if let link = item.link, let url = links.url(for: link) {
                    Link(destination: url) { Image(systemName: "arrow.up.forward.square").foregroundStyle(VLColor.cyan) }
                        .help("Open in QuickBooks")
                }
            }
            Text(item.detail).font(VLTypography.caption()).foregroundStyle(VLColor.textSecondary)
            Text(item.basis).font(.system(size: 10)).foregroundStyle(VLColor.textMuted)
        }
        .padding(.vertical, 2)
    }

    // MARK: Charts

    private var moneyGoes: some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.sm) {
                Text("WHERE THE MONEY GOES").font(VLTypography.eyebrow()).tracking(VLTypography.eyebrowTracking).foregroundStyle(VLColor.textMuted)
                Text(report.whereMoneyGoesBasis).font(VLTypography.caption()).foregroundStyle(VLColor.textMuted)
                if report.whereMoneyGoes.isEmpty {
                    Text("No expense history loaded.").font(VLTypography.caption()).foregroundStyle(VLColor.textMuted)
                } else {
                    Chart(report.whereMoneyGoes, id: \.label) { s in
                        BarMark(x: .value("Spent", s.amount.majorUnitsDouble), y: .value("Category", s.label))
                            .foregroundStyle(VLColor.cyan.gradient)
                            .annotation(position: .trailing) {
                                Text(String(format: "%.0f%%", s.share)).font(.system(size: 10, weight: .semibold)).foregroundStyle(VLColor.textSecondary)
                            }
                    }
                    .chartXAxis(.hidden)
                    .frame(height: CGFloat(report.whereMoneyGoes.count) * 30 + 10)
                    ForEach(report.whereMoneyGoes, id: \.label) { s in
                        HStack { Text(s.label).font(VLTypography.caption()); Spacer(); Text(s.amount.accountingDescription).font(VLTypography.caption().monospacedDigit()) }
                            .foregroundStyle(VLColor.textSecondary)
                    }
                }
            }
        }
    }

    private var trendChart: some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.sm) {
                Text("REVENUE AND PROFIT, MONTH BY MONTH").font(VLTypography.eyebrow()).tracking(VLTypography.eyebrowTracking).foregroundStyle(VLColor.textMuted)
                if report.trend.isEmpty {
                    Text("No monthly history loaded.").font(VLTypography.caption()).foregroundStyle(VLColor.textMuted)
                } else {
                    Chart {
                        ForEach(report.trend, id: \.0) { m in
                            BarMark(x: .value("Month", m.0), y: .value("Revenue", m.1.majorUnitsDouble))
                                .foregroundStyle(by: .value("Series", "Revenue"))
                            LineMark(x: .value("Month", m.0), y: .value("Net income", m.2.majorUnitsDouble))
                                .foregroundStyle(by: .value("Series", "Net income"))
                                .symbol(.circle)
                        }
                        RuleMark(y: .value("Zero", 0)).foregroundStyle(VLColor.textMuted.opacity(0.5))
                    }
                    .chartForegroundStyleScale(["Revenue": VLColor.cyan.opacity(0.55), "Net income": VLStatus.verified.color])
                    .frame(height: 240)
                }
            }
        }
    }

    // MARK: Explanation (AI, prose only)

    private var explainCard: some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.sm) {
                HStack {
                    Text("FOR THE CLIENT").font(VLTypography.eyebrow()).tracking(VLTypography.eyebrowTracking).foregroundStyle(VLColor.textMuted)
                    Spacer()
                    Button(isExplaining ? "Writing…" : (explanation == nil ? "Explain in plain English" : "Rewrite"), action: onExplain)
                        .disabled(isExplaining)
                }
                if let explanation {
                    Text(explanation).font(VLTypography.body()).foregroundStyle(VLColor.textPrimary).textSelection(.enabled)
                    Text("Written by AI from the items above only; any figure not in them is removed before you see it.")
                        .font(.system(size: 10)).foregroundStyle(VLColor.textMuted)
                } else if let explainError {
                    Text(explainError).font(VLTypography.caption()).foregroundStyle(VLStatus.urgent.color)
                } else {
                    Text("A short summary you can read to the owner, built only from the items above.")
                        .font(VLTypography.caption()).foregroundStyle(VLColor.textMuted)
                }
            }
        }
    }
}
