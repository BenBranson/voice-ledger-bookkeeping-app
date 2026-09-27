import SwiftUI

/// A non-lazy replacement for `LazyVGrid(columns: [GridItem(.adaptive(minimum:))])`
/// — wraps a small, fixed-size row of cards onto additional rows on a
/// narrow window, using only stock `ViewThatFits`/`HStack`/`VStack`
/// (nothing here is lazy or virtualized).
///
/// Why this exists at all, instead of just using `LazyVGrid`: SwiftUI's
/// Lazy containers only materialize the children that intersect the
/// ACTUAL currently-visible scroll viewport — verified directly (not
/// guessed) against this app's real `ScrollView`-hosted pages, live-
/// reported: a `LazyVGrid`-based card row further down the Dashboard than
/// whatever the window happened to show came out completely blank when
/// captured via `NSScrollView.documentView` + `cacheDisplay`
/// (`RootView.exportCurrentPageAsPDF`), even though `documentView`'s
/// reported height correctly spans the full page. Both `LazyVGrid` call
/// sites in this codebase (this file's caller, and the Cash Flow Forecast
/// card) wrap a small, fixed-size handful of cards — genuinely nothing
/// here needed lazy evaluation's performance benefit, and it was actively
/// breaking a real feature.
///
/// **A custom `Layout`-protocol conformance was tried first and reverted
/// — it crashed.** Confirmed with an isolated standalone repro script (not
/// this app): a plain custom `Layout` hosted in a real `NSHostingView`
/// crashed during `NSHostingView.layout()` -> `minSize` ->
/// `invalidateSizeConstraintsIfNecessary`, on this machine's exact OS/
/// Swift toolchain, even with zero relation to scrolling or capture — a
/// real crash risk, not a hypothetical one, so it was not shipped.
/// `ViewThatFits` is a much older, more standard SwiftUI primitive with
/// no such issue in the same repro harness (tested at both a wide and a
/// narrow window, and again with the card positioned off-screen inside a
/// real `ScrollView`, matching the original bug's exact conditions).
public enum AdaptiveCardFlow {
    /// `columnCandidates` should be given widest-first, e.g. `[cards
    /// .count, 2, 1]` — `ViewThatFits` tries each in order and renders the
    /// first that fits the available width. The last candidate should
    /// always be `1` (one card per row), since that's the only shape
    /// guaranteed to fit any width.
    public static func chunked<Element>(_ items: [Element], into size: Int) -> [[Element]] {
        guard size > 0, !items.isEmpty else { return items.isEmpty ? [] : [items] }
        return stride(from: 0, to: items.count, by: size).map {
            Array(items[$0..<Swift.min($0 + size, items.count)])
        }
    }
}

/// A row of `content` that reflows onto additional rows as the available
/// width narrows — same visual behavior as the reverted `LazyVGrid`-based
/// approach, built from `ViewThatFits` instead. `itemCount` and
/// `spacing` describe the row being laid out; `content(index)` builds one
/// item.
public struct AdaptiveCardFlowRow<Content: View>: View {
    let itemCount: Int
    let spacing: CGFloat
    @ViewBuilder let content: (Int) -> Content

    public init(itemCount: Int, spacing: CGFloat, @ViewBuilder content: @escaping (Int) -> Content) {
        self.itemCount = itemCount
        self.spacing = spacing
        self.content = content
    }

    public var body: some View {
        let indices = Array(0..<itemCount)
        ViewThatFits(in: .horizontal) {
            HStack(spacing: spacing) {
                ForEach(indices, id: \.self) { content($0) }
            }
            // Wrap candidates, widest-to-narrowest. Three items (the Cash
            // Flow Forecast card's fixed count) never needs more than a
            // 2-per-row candidate before falling back to 1-per-row; a
            // `KPICardRow` with more cards benefits from a 3-per-row step
            // too. Extra candidates beyond what a given row actually
            // needs are harmless — `ViewThatFits` just never reaches them.
            rows(perRow: 3, indices: indices)
            rows(perRow: 2, indices: indices)
            rows(perRow: 1, indices: indices)
        }
    }

    private func rows(perRow: Int, indices: [Int]) -> some View {
        VStack(spacing: spacing) {
            ForEach(Array(AdaptiveCardFlow.chunked(indices, into: perRow).enumerated()), id: \.offset) { _, row in
                HStack(spacing: spacing) {
                    ForEach(row, id: \.self) { content($0) }
                }
            }
        }
    }
}
