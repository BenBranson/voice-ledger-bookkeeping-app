import SwiftUI

/// A categorical series palette for charts — Balance Sheet donuts, P&L
/// waterfalls, expense-driver bars. Pulls ONLY from the existing accent
/// vocabulary (`VLColor.swift`'s "accent colors and status colors are
/// separate vocabularies" rule) — never `VLStatus`'s private hues, which
/// would risk a chart segment accidentally reading as "this account is
/// broken" the way `VLColor.swift`'s own Decision 1 history warns against.
/// `violet` is deliberately excluded — it's reserved for AI/automation
/// affordances, never a plain data series.
public enum VLChartPalette {
    public static let series: [Color] = [
        VLColor.cyan,
        VLColor.teal,
        VLColor.cyanBright,
        VLColor.blue
    ]

    /// Cycles the palette for a series longer than 4 categories — better
    /// than adding new hues nobody has contrast-checked yet.
    public static func color(at index: Int) -> Color {
        series[index % series.count]
    }
}
