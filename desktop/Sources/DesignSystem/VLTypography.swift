import SwiftUI

/// Type scale. Two families, used for different jobs:
///
/// - **Condensed** for page titles and large numeric callouts. The brief named
///   Barlow/Roboto Condensed; neither ships with macOS, so this resolves to a
///   condensed system width and degrades cleanly rather than depending on a
///   font that may not be installed. If you later bundle Barlow Condensed,
///   change `displayFamily` here and nothing else.
/// - **The system sans** (SF Pro) for everything else: navigation, labels,
///   body copy, forms, tables.
///
/// Hard rule from the brief, worth restating: condensed type is never used for
/// paragraphs, inputs, or table data. It is a display face only.
public enum VLTypography {

    // MARK: - Display (condensed) — titles and big numbers only

    public static func pageTitle() -> Font {
        .system(size: 28, weight: .bold).width(.condensed)
    }

    public static func sectionTitle() -> Font {
        .system(size: 19, weight: .semibold).width(.condensed)
    }

    /// Large numeric callouts — dollar exposure, close readiness, counts.
    /// Always paired with `.monospacedDigit()` at the call site so figures
    /// don't jitter as they update.
    public static func metricLarge() -> Font {
        .system(size: 34, weight: .bold).width(.condensed).monospacedDigit()
    }

    public static func metricMedium() -> Font {
        .system(size: 22, weight: .semibold).width(.condensed).monospacedDigit()
    }

    // MARK: - Interface (standard width)

    public static func cardTitle() -> Font {
        .system(size: 15, weight: .semibold)
    }

    public static func body() -> Font {
        .system(size: 13, weight: .regular)
    }

    public static func bodyEmphasis() -> Font {
        .system(size: 13, weight: .medium)
    }

    /// Field labels, column headers. Slightly muted at the call site via
    /// `VLColor.textSecondary`.
    public static func label() -> Font {
        .system(size: 11, weight: .semibold)
    }

    /// Provenance chips, timestamps, rule IDs — the fine print that must stay
    /// legible without drawing attention.
    public static func caption() -> Font {
        .system(size: 11, weight: .regular)
    }

    /// Financial values in tables. Monospaced digits and right alignment are
    /// both required for columns of money to be scannable.
    public static func tabularNumeric() -> Font {
        .system(size: 13, weight: .regular).monospacedDigit()
    }

    public static func tabularNumericEmphasis() -> Font {
        .system(size: 13, weight: .semibold).monospacedDigit()
    }

    /// Uppercase section eyebrows ("DATA AVAILABLE", "COMMAND"). Pair with
    /// `.tracking(VLTypography.eyebrowTracking)`.
    public static func eyebrow() -> Font {
        .system(size: 10, weight: .semibold)
    }

    public static let eyebrowTracking: CGFloat = 0.8
}
