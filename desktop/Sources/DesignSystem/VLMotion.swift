import SwiftUI

/// Motion tokens. The brief's range is 150–220ms, and the restraint it asks
/// for is explicit: no constant pulsing, flickering, rotating backgrounds, or
/// moving circuit lines. Motion here exists to confirm an interaction
/// happened, not to entertain.
public enum VLMotion {

    public static let fast: Double = 0.15
    public static let standard: Double = 0.18
    public static let deliberate: Double = 0.22

    /// Hover elevation, border illumination, chip state changes.
    public static var interactive: Animation {
        .easeOut(duration: standard)
    }

    /// Sidebar collapse, panel expand/collapse.
    public static var panel: Animation {
        .easeInOut(duration: deliberate)
    }

    /// Chart and progress reveals.
    public static var dataReveal: Animation {
        .easeOut(duration: deliberate)
    }

    /// Honors the system Reduce Motion setting. Every animated view should
    /// route through this rather than calling `.animation` directly, so
    /// accessibility compliance is the default path and not an afterthought.
    ///
    /// Usage:
    /// ```
    /// @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// // ...
    /// .animation(VLMotion.respecting(reduceMotion, VLMotion.interactive), value: isActive)
    /// ```
    public static func respecting(_ reduceMotion: Bool, _ animation: Animation) -> Animation? {
        reduceMotion ? nil : animation
    }
}
