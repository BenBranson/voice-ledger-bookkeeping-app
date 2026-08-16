import SwiftUI

/// The Midnight Neon palette. Every color in the app comes from here —
/// nothing hard-codes a hex value at a call site.
///
/// Two rules govern this file, and they are not stylistic:
///
/// 1. **Accent colors and status colors are separate vocabularies.**
///    `VLColor.cyan` means "active / connected / selected." It does NOT mean
///    "good." Accounting status lives in `VLStatus` (VLStatus.swift).
///
/// 2. **Status hues do not live here.** `verified`/`reviewNeeded`/`urgent`
///    (green/amber/coral) are declared `private` inside `VLStatus.swift`,
///    reachable ONLY through `VLStatus.color`. This is a structural guard,
///    not a convention: no other file in this module can spell the literal
///    green/amber/coral value, so a careless future edit cannot make some
///    unrelated badge "borrow" a status color the way the environment
///    badge originally (and wrongly) borrowed coral and amber — see
///    docs/design/DESIGN_SYSTEM.md, Decision 1. Environment colors have
///    their own equally-isolated pool in `VLEnvironment.swift`.
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
    /// live connection indicators. Safe as TEXT on any surface token below —
    /// see VLContrast.swift's validated pair catalog (8.94:1 on surfaceCard).
    public static let cyan = Color(hex: 0x29D3F2)
    /// Highlight cyan for small illuminated details and hover states.
    public static let cyanBright = Color(hex: 0x67E8F9)
    /// ⚠️ NOT a text-safe color on `surfaceCard` or `surfaceElevated` — measures
    /// 4.29:1 there, below the 4.5:1 WCAG AA threshold for normal text
    /// (docs/design/DESIGN_SYSTEM.md, Decision 2). Safe for borders, strokes,
    /// chart series, and icon fills, which only need 3:1. For blue-family TEXT
    /// on a card, use `cyan` or `cyanBright` instead.
    public static let blue = Color(hex: 0x2788D9)
    public static let teal = Color(hex: 0x32C7A3)
    /// Reserved for AI / automation affordances (Ask Claude, generated prose).
    /// Violet marks guidance, never a deterministic accounting result.
    public static let violet = Color(hex: 0x9B6EF3)

    // MARK: - Text

    public static let textPrimary = Color(hex: 0xF4F8FC)
    public static let textSecondary = Color(hex: 0xB8C7D9)
    /// #7E92AA — raised from the original #71849B (measured 4.19:1 on
    /// surfaceCard, failing WCAG AA). This value clears 4.5:1 on every
    /// surface token in the system; worst case is surfaceCard at 5.03:1.
    /// See docs/design/DESIGN_SYSTEM.md Decision 2 and VLContrast.swift,
    /// which asserts this holds. Still: never use textMuted for essential
    /// information (a coverage state, a dollar figure) regardless of
    /// contrast — reserve it for captions, timestamps, provenance chips.
    public static let textMuted = Color(hex: 0x7E92AA)

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
