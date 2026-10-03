import SwiftUI
import Core
import DesignSystem

/// Body of a Moneypenny pop-up card: the answer, a chart, the records with
/// exact QuickBooks links, and what to do. Every value comes from Core.
public struct InsightCardView: View {
    let card: InsightCard
    @Environment(\.qboLinks) private var qboLinks
    @State private var selectedID: String?

    public init(card: InsightCard) { self.card = card }

    public var body: some View {
        VStack(alignment: .leading, spacing: VLSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.subtitle).font(VLTypography.caption()).foregroundStyle(VLColor.textMuted)
                    if let headline = card.headline {
                        Text(ClientText.minusSigns(headline)).font(VLTypography.metricLarge()).foregroundStyle(VLColor.cyan)
                    }
                }
                Spacer()
                if let target = card.headerLink { QBOLinkButton(qboLinks.url(for: target)) }
            }
            if let chart = card.chart {
                EChartView(kind: "insightChart", data: chart, allowedIDs: Set(chart.ids), selectedID: selectedID,
                           summary: "\(card.title) chart") { selectedID = $0 }
                    .frame(height: chart.type == .hbar || chart.type == .hstackedBar ? CGFloat(max(160, min(360, chart.categories.count * 30 + 40))) : 220)
            }
            if !card.recommendations.isEmpty {
                VLCard(accentRail: VLColor.violet) {
                    VStack(alignment: .leading, spacing: VLSpacing.xs) {
                        Text("WHAT TO DO").font(VLTypography.eyebrow()).tracking(VLTypography.eyebrowTracking).foregroundStyle(VLColor.violet)
                        ForEach(card.recommendations, id: \.self) { rec in
                            Text("• \(rec)").font(VLTypography.body()).foregroundStyle(VLColor.textSecondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            if !card.rows.isEmpty {
                VLCard {
                    VStack(alignment: .leading, spacing: VLSpacing.xs) {
                        ForEach(card.rows) { row in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.label).font(VLTypography.body()).foregroundStyle(row.warn ? .orange : VLColor.textPrimary)
                                    if !row.detail.isEmpty {
                                        Text(row.detail).font(VLTypography.caption()).foregroundStyle(VLColor.textMuted).fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                Spacer()
                                Text(ClientText.minusSigns(row.amountText)).font(VLTypography.tabularNumeric()).foregroundStyle(row.warn ? .orange : VLColor.textPrimary)
                                if let target = row.link { QBOLinkButton(qboLinks.url(for: target), compact: true).frame(width: 22) }
                            }
                            .padding(.vertical, 2)
                            .background(selectedID == row.id ? VLColor.cyan.opacity(0.12) : .clear)
                            if row.id != card.rows.last?.id { Divider().overlay(VLColor.border) }
                        }
                    }
                }
            }
            Text(card.footnote).font(VLTypography.caption()).foregroundStyle(VLColor.textMuted)
        }
    }
}
