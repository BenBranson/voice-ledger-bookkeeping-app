import SwiftUI

/// WCAG 2.1 contrast checking, as production code rather than test-only
/// scaffolding — so its correctness is verified by `swift build` even in an
/// environment where `swift test` can't run (see Tests/README.md).
///
/// docs/design/DESIGN_SYSTEM.md, Decision 2: two pairs failed AA when
/// measured (`textMuted` on `surfaceCard` at 4.19:1, `blue` on `surfaceCard`
/// at 4.29:1). The fix — raising `textMuted` to #7E92AA, and documenting
/// `blue` as non-text-safe — is only as good as the check that keeps it
/// true. `ContrastTests.swift` asserts `VLContrast.auditAllPairs().isEmpty`;
/// this file is where that assertion gets its teeth.
public enum VLContrast {

    /// Relative luminance per WCAG 2.1 §1.4.3 / §1.4.11.
    static func relativeLuminance(_ color: ResolvedRGB) -> Double {
        func channel(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(color.red) + 0.7152 * channel(color.green) + 0.0722 * channel(color.blue)
    }

    /// Contrast ratio between two colors, per WCAG 2.1 §1.4.3. Range 1:1 (no
    /// contrast) to 21:1 (black on white).
    public static func ratio(_ a: ResolvedRGB, _ b: ResolvedRGB) -> Double {
        let l1 = relativeLuminance(a)
        let l2 = relativeLuminance(b)
        let lighter = max(l1, l2)
        let darker = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// AA threshold for normal-size text. (Large text — 18pt+ or 14pt+ bold —
    /// only needs 3:1, but nothing in this catalog currently relies on that
    /// relaxation, so every pair is held to the stricter bar.)
    public static let minimumNormalTextRatio: Double = 4.5

    /// A resolved sRGB triple in 0...1, independent of `Color` — lets this
    /// module compute without depending on a live color-scheme environment,
    /// which `Color` alone can't guarantee outside a view context.
    public struct ResolvedRGB: Sendable {
        let red: Double
        let green: Double
        let blue: Double

        public init(hex: UInt32) {
            red = Double((hex >> 16) & 0xFF) / 255.0
            green = Double((hex >> 8) & 0xFF) / 255.0
            blue = Double(hex & 0xFF) / 255.0
        }
    }

    /// A declared text-color-on-surface pairing the design system considers
    /// valid to use for normal-size, essential text.
    public struct TextOnSurfacePair: Sendable {
        public let name: String
        public let foreground: ResolvedRGB
        public let background: ResolvedRGB
    }

    /// Every hex value here is a literal duplicate of the corresponding
    /// token's definition (`VLColor`, `VLStatus`'s private `StatusHue`,
    /// `VLEnvironment`'s private `EnvironmentHue`) — duplicated rather than
    /// referencing `Color` directly, because extracting RGB components back
    /// out of a `Color` requires a live color-scheme resolution context that
    /// isn't available here. If a token's hex value changes, this catalog
    /// must be updated in the same commit, or the audit is checking stale
    /// numbers. `ContrastTests.swift` is the trip-wire for exactly that:
    /// keep it green, and a forgotten update here shows up as a failing
    /// ratio the next time anyone actually looks.
    public static let declaredTextPairs: [TextOnSurfacePair] = {
        let surfaceCard = ResolvedRGB(hex: 0x102238)
        let elevated = ResolvedRGB(hex: 0x0E1D30)
        let appBg = ResolvedRGB(hex: 0x07111F)
        let inset = ResolvedRGB(hex: 0x0B192A)
        let productionSurface = ResolvedRGB(hex: 0x050B14)

        let textPrimary = ResolvedRGB(hex: 0xF4F8FC)
        let textSecondary = ResolvedRGB(hex: 0xB8C7D9)
        let textMuted = ResolvedRGB(hex: 0x7E92AA) // Decision 2's fix
        let cyan = ResolvedRGB(hex: 0x29D3F2)
        let cyanBright = ResolvedRGB(hex: 0x67E8F9)
        let teal = ResolvedRGB(hex: 0x32C7A3)
        let violet = ResolvedRGB(hex: 0x9B6EF3)
        let verifiedGreen = ResolvedRGB(hex: 0x3ECF8E)
        let reviewAmber = ResolvedRGB(hex: 0xF4B860)
        let urgentCoral = ResolvedRGB(hex: 0xF06472)
        let statusInformationalBlue = ResolvedRGB(hex: 0x4FA3E8)

        var pairs: [TextOnSurfacePair] = []
        let surfaces: [(String, ResolvedRGB)] = [
            ("surfaceCard", surfaceCard), ("surfaceElevated", elevated),
            ("background", appBg), ("surfaceInset", inset)
        ]
        let textColors: [(String, ResolvedRGB)] = [
            ("textPrimary", textPrimary), ("textSecondary", textSecondary), ("textMuted", textMuted),
            ("cyan", cyan), ("cyanBright", cyanBright), ("teal", teal), ("violet", violet),
            ("statusVerifiedGreen", verifiedGreen), ("statusReviewAmber", reviewAmber),
            ("statusUrgentCoral", urgentCoral), ("statusInformationalBlue", statusInformationalBlue)
        ]
        for (surfaceName, surface) in surfaces {
            for (textName, text) in textColors {
                pairs.append(TextOnSurfacePair(name: "\(textName) on \(surfaceName)", foreground: text, background: surface))
            }
        }
        // The environment production bar has its own dedicated surface,
        // checked separately since it's not part of the general surface set.
        pairs.append(TextOnSurfacePair(name: "textPrimary on environmentProductionSurface", foreground: textPrimary, background: productionSurface))

        return pairs
    }()

    public struct Violation: Sendable, CustomStringConvertible {
        public let pairName: String
        public let ratio: Double
        public var description: String {
            String(format: "%@ measures %.2f:1, below the %.1f:1 AA threshold", pairName, ratio, minimumNormalTextRatio)
        }
    }

    /// Checks every declared pair against the AA threshold. An empty result
    /// is the passing state — this is what `ContrastTests.swift` asserts.
    public static func auditAllPairs() -> [Violation] {
        declaredTextPairs.compactMap { pair in
            let measured = ratio(pair.foreground, pair.background)
            return measured < minimumNormalTextRatio
                ? Violation(pairName: pair.name, ratio: measured)
                : nil
        }
    }
}
