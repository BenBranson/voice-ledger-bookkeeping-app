import SwiftUI
import DesignSystem

/// A row of small metric cards for the Balance Sheet/P&L visual layer —
/// working capital, current ratio, gross margin, etc. Primitive params
/// only (plain strings, no `Core` dependency), matching this module's
/// existing boundary.
public struct KPICardRow: View {
    /// Owner directive (2026-09-06): "does the dashboard have all the
    /// KPIs I need" — a snapshot number alone doesn't say whether things
    /// are getting better or worse. Deliberately no color-coding by
    /// direction (no green-up/red-down): CLAUDE.md's status vocabulary is
    /// reserved for `VLStatus`, and "up" isn't universally "good" for
    /// every KPI here (rising expenses is up and bad; rising working
    /// capital is up and good) — the arrow states the fact, in a neutral
    /// color, and leaves the judgment to the reader.
    public struct Trend {
        public enum Direction { case up, down, flat }
        public let direction: Direction
        /// Pre-formatted, e.g. "12.4% vs last month" — this view has no
        /// opinion about number formatting, same as `CardData.value`.
        public let label: String

        public init(direction: Direction, label: String) {
            self.direction = direction
            self.label = label
        }

        private var glyph: String {
            switch direction {
            case .up: return "▲"
            case .down: return "▼"
            case .flat: return "–"
            }
        }

        var text: String { "\(glyph) \(label)" }
    }

    public struct CardData: Identifiable {
        public let id: String
        public let label: String
        public let value: String
        /// `false` renders the value muted/gray instead of the accent
        /// color — CLAUDE.md rule 5: a KPI that couldn't be computed
        /// (a required QBO report line wasn't found) must never look the
        /// same as one that's real.
        public let isAvailable: Bool
        public let trend: Trend?
        /// A free-form subtitle unrelated to period-over-period change —
        /// e.g. "23% overdue" on an Accounts Receivable card. Kept
        /// separate from `trend` rather than overloading it, since a
        /// direction arrow next to "overdue" would misleadingly imply a
        /// comparison this card isn't actually making.
        public let detail: String?
        /// Owner directive (2026-09-06): "the cards on the dashboard
        /// should be clickable to take the user to where it was
        /// calculated" — e.g. Net Margin to Profit & Loss. `nil` (the
        /// default) renders a plain, non-interactive card, unchanged from
        /// before this existed.
        public let onTap: (() -> Void)?

        public init(label: String, value: String, isAvailable: Bool = true, trend: Trend? = nil, detail: String? = nil, onTap: (() -> Void)? = nil) {
            self.id = label
            self.label = label
            self.value = value
            self.isAvailable = isAvailable
            self.trend = trend
            self.detail = detail
            self.onTap = onTap
        }
    }

    private let cards: [CardData]

    public init(cards: [CardData]) {
        self.cards = cards
    }

    /// Owner directive (2026-09-06): flagged during testing — a plain
    /// `HStack` doesn't reflow, so a row of 4-5 cards squeezes unreadably
    /// (or overflows past the window edge with no way to scroll to it) on
    /// a laptop-width window, even though it looked fine on the wide
    /// external monitor this was built and tested against. Originally a
    /// `LazyVGrid` with an adaptive column, which gave every card a real
    /// minimum width and wrapped extra cards onto a new row with no
    /// per-window-size logic to maintain — switched to
    /// `AdaptiveCardFlowRow` (2026-09-27) once `LazyVGrid` was confirmed
    /// to render blank in a PDF export whenever this row wasn't already
    /// scrolled into view; see that type's own doc comment (it also
    /// explains why a custom `Layout`-protocol replacement was tried
    /// first and reverted after it crashed in isolated testing). Same
    /// visual wrap behavior, just not lazy — this row is always a small,
    /// fixed handful of cards, so there was never a real performance
    /// reason for laziness here.
    public var body: some View {
        AdaptiveCardFlowRow(itemCount: cards.count, spacing: VLSpacing.sm) { index in
            let card = cards[index]
            if let onTap = card.onTap {
                Button(action: onTap) {
                    cardBody(card, isClickable: true)
                }
                .buttonStyle(.plain)
                .help("Open the report this was calculated from")
            } else {
                cardBody(card, isClickable: false)
            }
        }
    }

    private func cardBody(_ card: CardData, isClickable: Bool) -> some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                HStack {
                    Text(card.label.uppercased())
                        .font(VLTypography.eyebrow())
                        .tracking(VLTypography.eyebrowTracking)
                        .foregroundStyle(VLColor.textMuted)
                    if isClickable {
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(VLColor.textMuted)
                    }
                }
                Text(card.value)
                    .font(VLTypography.metricMedium())
                    .foregroundStyle(card.isAvailable ? VLColor.cyan : VLColor.textMuted)
                if let trend = card.trend {
                    Text(trend.text)
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textMuted)
                }
                if let detail = card.detail {
                    Text(detail)
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textMuted)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}
