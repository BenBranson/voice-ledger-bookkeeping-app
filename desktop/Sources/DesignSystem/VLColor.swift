import SwiftUI

/// The Midnight Neon palette. Every color in the app comes from here —
/// nothing hard-codes a hex value at a call site.
///
/// Two rules govern this file, and they are not stylistic:
///
/// 1. **Accent colors and status colors are separate vocabularies.**
///    `VLColor.cyan` means "active / connected / selected." It does NOT mean
///    "good." Accounting status lives in `VLStatus` (VLStatus.swift) and is
///    the only thing allowed to communicate a finding's meaning.
///
/// 2. **`verifiedGreen` is not a general-purpose success color.** See
///    `VLStatus.verified`'s documentation and CLAUDE.md rule 5. It is
///    deliberately not named `success` so that reaching for it casually
///    looks wrong.
public enum VLColor {

    // MARK: - Surfaces (dark navy, never pure black)

    /// App background. Deliberately #07111F, not #000 — pure black kills the
    /// sense of depth the layered surfaces below depend on.
    public static let background = Color(hex: 0x07111F)
    public static let backgroundSecondary = Color(hex: 0x0A1728)
    public static let surfaceElevated = Color(hex: 0x0E1D30)
    public static let surfaceCard = Color(hex: 0x102238)
    /// Inset surfaces — form inputs, code blocks, wells. Recedes rather than lifts.
    public static let surfaceInset = Color(hex: 0x0B192A)

    // MARK: - Accents (interaction and emphasis — NOT status)

    /// Primary interactive accent: active nav, focus rings, selected rows,
    /// live connection indicators.
    public static let cyan = Color(hex: 0x29D3F2)
    /// Highlight cyan for small illuminated details and hover states.
    public static let cyanBright = Color(hex: 0x67E8F9)
    public static let blue = Color(hex: 0x2788D9)
    public static let teal = Color(hex: 0x32C7A3)
    /// Reserved for AI / automation affordances (Ask Claude, generated prose).
    /// Violet marks guidance, never a deterministic accounting result.
    public static let violet = Color(hex: 0x9B6EF3)

    // MARK: - Status hues
    //
    // Raw hues only. Do not use these directly in views — go through
    // `VLStatus` so that every status rendering carries an icon and a text
    // label alongside the color (WCAG, and the spec's "never communicate
    // status through color alone").

    /// Green means VERIFIED — see VLStatus.verified for the four preconditions.
    public static let verifiedGreen = Color(hex: 0x3ECF8E)
    /// Amber: human review required. Also used for the SANDBOX environment
    /// marker, which is differentiated by FORM (stripes) not hue — see
    /// docs/design/DESIGN_SYSTEM.md §"Amber collision".
    public static let amber = Color(hex: 0xF4B860)
    /// Coral: urgent, materially risky, overdue, or destructive.
    public static let coral = Color(hex: 0xF06472)

    // MARK: - Text

    public static let textPrimary = Color(hex: 0xF4F8FC)
    public static let textSecondary = Color(hex: 0xB8C7D9)
    public static let textMuted = Color(hex: 0x71849B)

    // MARK: - Borders

    public static let border = Color(red: 66 / 255, green: 153 / 255, blue: 225 / 255, opacity: 0.22)
    public static let borderActive = Color(red: 41 / 255, green: 211 / 255, blue: 242 / 255, opacity: 0.70)
    /// For decorative technical detail (circuit paths, dot grids, node lines).
    /// Deliberately near-invisible: these must never compete with data.
    public static let decorativeLine = Color(red: 41 / 255, green: 211 / 255, blue: 242 / 255, opacity: 0.06)
}

extension Color {
    /// Hex initializer used only inside `VLColor`. Kept internal-ish by
    /// convention — views should reference named tokens, never raw hex.
    init(hex: UInt32, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }
}
