import SwiftUI

/// A categorical series palette for charts — Balance Sheet donuts, P&L
/// waterfalls, expense-driver bars.
///
/// Real, reported problem with the first version of this file (2026-08-29):
/// it cycled `cyan`/`teal`/`cyanBright`/`blue` — four hues that are all in
/// the same cyan/blue family, which made adjacent donut slices genuinely
/// hard to tell apart ("colors are too similar"). This version spreads six
/// NEW hues around the color wheel instead (orange, magenta, indigo, lime,
/// alongside the existing cyan/teal) so neighboring slices are actually
/// distinguishable without relying on the legend alone.
///
/// These are deliberately NEW hex values, not reused from anywhere else in
/// `DesignSystem` — checked directly against `VLStatus`'s private hues
/// (`0x3ECF8E` green, `0xF4B860` amber, `0xF06472` coral, `0x4FA3E8`
/// informational blue) and `VLEnvironment`'s (`0xD98E3B` sandbox,
/// `0x3A5A82` production border) to confirm no literal collision — a chart
/// segment must never accidentally BE a status/environment color, per
/// `VLColor.swift`'s own "accent vs status vs environment are separate
/// vocabularies" rule and its Decision 1 history. `violet` stays excluded
/// — reserved for AI/automation affordances, never a plain data series.
public enum VLChartPalette {
    public static let series: [Color] = [
        VLColor.cyan,
        Color(hex: 0xF0954D), // orange
        Color(hex: 0xEC6FAE), // magenta/pink
        VLColor.teal,
        Color(hex: 0x7C89F5), // indigo
        Color(hex: 0xA8D94A)  // lime
    ]

    /// Cycles the palette for a series longer than 6 categories.
    public static func color(at index: Int) -> Color {
        series[index % series.count]
    }
}
