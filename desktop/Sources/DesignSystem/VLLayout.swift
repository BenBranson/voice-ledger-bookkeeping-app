import SwiftUI

/// Spacing, radii, and border weights. An 8-point grid with two half-steps
/// for dense areas (table cells, chip interiors) where a full 8pt step would
/// waste space a bookkeeper needs for data.
public enum VLSpacing {
    /// 2pt — chip interiors, icon-to-label gaps only.
    public static let hairline: CGFloat = 2
    /// 4pt — half-step for dense table and chip padding.
    public static let xxs: CGFloat = 4
    public static let xs: CGFloat = 8
    public static let sm: CGFloat = 12
    public static let md: CGFloat = 16
    public static let lg: CGFloat = 24
    public static let xl: CGFloat = 32
    public static let xxl: CGFloat = 48

    /// Standard card interior padding.
    public static let cardPadding: CGFloat = 16
    /// Main content area gutter.
    public static let pageGutter: CGFloat = 24
}

public enum VLRadius {
    /// Chips, pills, small badges.
    public static let chip: CGFloat = 6
    /// Buttons and inputs.
    public static let control: CGFloat = 8
    /// Cards and panels — the brief's 12–16pt range.
    public static let card: CGFloat = 12
    /// Large surfaces, dialogs.
    public static let panel: CGFloat = 16
}

public enum VLBorder {
    public static let hairline: CGFloat = 1
    /// Focus rings and selected states.
    public static let emphasis: CGFloat = 1.5
    /// The accent rail along a card's leading edge that carries page-type or
    /// status meaning.
    public static let accentRail: CGFloat = 3
}

/// Elevation is expressed as restrained shadow, and glow is used sparingly —
/// on borders, icons, active states, and important data, never around every
/// element. Most cards stay calm so that a highlighted card actually means
/// something (the brief's central visual restraint).
public enum VLElevation {

    public struct Shadow: Sendable {
        public let color: Color
        public let radius: CGFloat
        public let y: CGFloat
    }

    /// Default resting card — barely lifted.
    public static let card = Shadow(
        color: Color.black.opacity(0.35), radius: 8, y: 2
    )

    /// Hovered or focused card.
    public static let raised = Shadow(
        color: Color.black.opacity(0.45), radius: 14, y: 4
    )

    /// Dialogs and popovers.
    public static let overlay = Shadow(
        color: Color.black.opacity(0.55), radius: 28, y: 10
    )

    /// The cyan illumination reserved for the ACTIVE or SELECTED element.
    /// Deliberately low opacity — a glow that shouts stops meaning anything.
    public static let activeGlow = Shadow(
        color: VLColor.cyan.opacity(0.28), radius: 12, y: 0
    )
}

public extension View {
    /// Applies a VLElevation shadow. Kept as a helper so no view reaches for
    /// a raw `.shadow(color:radius:)` with invented values.
    func vlShadow(_ shadow: VLElevation.Shadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: 0, y: shadow.y)
    }
}
