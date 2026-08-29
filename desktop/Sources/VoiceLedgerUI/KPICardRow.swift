import SwiftUI
import DesignSystem

/// A row of small metric cards for the Balance Sheet/P&L visual layer —
/// working capital, current ratio, gross margin, etc. Primitive params
/// only (plain strings, no `Core` dependency), matching this module's
/// existing boundary.
public struct KPICardRow: View {
    public struct CardData: Identifiable {
        public let id: String
        public let label: String
        public let value: String
        /// `false` renders the value muted/gray instead of the accent
        /// color — CLAUDE.md rule 5: a KPI that couldn't be computed
        /// (a required QBO report line wasn't found) must never look the
        /// same as one that's real.
        public let isAvailable: Bool

        public init(label: String, value: String, isAvailable: Bool = true) {
            self.id = label
            self.label = label
            self.value = value
            self.isAvailable = isAvailable
        }
    }

    private let cards: [CardData]

    public init(cards: [CardData]) {
        self.cards = cards
    }

    public var body: some View {
        HStack(spacing: VLSpacing.sm) {
            ForEach(cards) { card in
                VLCard {
                    VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                        Text(card.label.uppercased())
                            .font(VLTypography.eyebrow())
                            .tracking(VLTypography.eyebrowTracking)
                            .foregroundStyle(VLColor.textMuted)
                        Text(card.value)
                            .font(VLTypography.metricMedium())
                            .foregroundStyle(card.isAvailable ? VLColor.cyan : VLColor.textMuted)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
