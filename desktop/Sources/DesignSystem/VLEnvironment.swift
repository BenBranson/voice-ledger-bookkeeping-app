import SwiftUI

/// Environment hues — `private` to this file, for the same reason
/// `StatusHue` is private to `VLStatus.swift`. Environment is a **third
/// vocabulary**, separate from both accent and status. It borrows no status
/// hue at all — not coral, not amber, not the accent cyan family.
///
/// docs/design/DESIGN_SYSTEM.md, Decision 1: the original design inverted the
/// brief so production read serious via `VLColor.coral`. The reasoning was
/// right (under CLAUDE.md rule 7, the dangerous state is being in production
/// without noticing) but coral was the wrong instrument — coral means
/// `.urgent`, and once live with real clients, production is the *permanent
/// normal state*. A coral badge on screen every working hour trains the eye
/// to stop seeing coral, which defeats the reason coral means something at
/// all. Same failure shape as the amber/sandbox collision, one level up.
private enum EnvironmentHue {
    /// Deep, near-black surface — deliberately darker than `VLColor.background`
    /// (#07111F) so the production bar reads as its own distinct surface, not
    /// a variant of the app chrome. Appears nowhere else in the system.
    static let productionSurface = Color(hex: 0x050B14)
    static let productionBorder = Color(hex: 0x3A5A82)
    /// Amber-adjacent but a SEPARATE constant from any status hue — changing
    /// `StatusHue.reviewNeeded` can never accidentally change this, and vice
    /// versa, because neither file can see the other's private values.
    static let sandboxStripe = Color(hex: 0xD98E3B)
}

/// Environment marker. CLAUDE.md rule 7 and the spec require production and
/// sandbox be "visually unmistakable" from each other — and from every
/// status pill in the app, which is the part the original design missed.
///
/// The two cases render as genuinely different SHAPES, not just different
/// colors on the same chip, so "which environment am I in" survives a glance
/// from across two monitors without reading any text:
///
/// - **Sandbox** — the existing striped chip (`VLStatusPill`-sized). Loud on
///   purpose: it means "nothing here is real."
/// - **Production** — a solid filled bar, wider than any status pill, with a
///   shield icon and primary text on a dedicated near-black surface. Serious
///   by FORM and PERMANENCE, not by borrowing danger red. It means "this is
///   a client's actual books" — worth a persistently different treatment,
///   not a persistently alarming one.
public enum VLEnvironmentTone: Sendable {
    case production
    case sandbox

    public var label: String {
        switch self {
        case .production: return "PRODUCTION"
        case .sandbox: return "SANDBOX"
        }
    }

    public var iconName: String {
        switch self {
        case .production: return "shield.fill"
        case .sandbox: return "hammer.fill"
        }
    }
}

/// Renders `VLEnvironmentTone`. Two different component shapes by design —
/// see the type's documentation for why a shared "colored chip" shape would
/// undersell the distinction.
public struct VLEnvironmentBadge: View {
    private let tone: VLEnvironmentTone

    public init(_ tone: VLEnvironmentTone) {
        self.tone = tone
    }

    public var body: some View {
        switch tone {
        case .production: productionBar
        case .sandbox: sandboxChip
        }
    }

    // MARK: - Production: solid bar, appears nowhere else in the system

    private var productionBar: some View {
        HStack(spacing: VLSpacing.xs) {
            Image(systemName: tone.iconName)
                .font(.system(size: 12, weight: .bold))
            Text(tone.label)
                .font(VLTypography.eyebrow())
                .tracking(VLTypography.eyebrowTracking)
        }
        .foregroundStyle(VLColor.textPrimary)
        .padding(.horizontal, VLSpacing.sm)
        .padding(.vertical, VLSpacing.xxs)
        .background(
            RoundedRectangle(cornerRadius: VLRadius.control)
                .fill(EnvironmentHue.productionSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: VLRadius.control)
                .strokeBorder(EnvironmentHue.productionBorder, lineWidth: VLBorder.emphasis)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Environment: Production — this is a client's real QuickBooks company")
    }

    // MARK: - Sandbox: striped chip, matches the brief's original instinct

    private var sandboxChip: some View {
        HStack(spacing: VLSpacing.xxs) {
            Image(systemName: tone.iconName)
                .font(.system(size: 10, weight: .bold))
            Text(tone.label)
                .font(VLTypography.eyebrow())
                .tracking(VLTypography.eyebrowTracking)
        }
        .foregroundStyle(EnvironmentHue.sandboxStripe)
        .padding(.horizontal, VLSpacing.xs)
        .padding(.vertical, VLSpacing.xxs)
        .background(
            RoundedRectangle(cornerRadius: VLRadius.chip)
                .fill(EnvironmentHue.sandboxStripe.opacity(0.10))
                .overlay(VLDiagonalStripes(color: EnvironmentHue.sandboxStripe.opacity(0.22)))
                .clipShape(RoundedRectangle(cornerRadius: VLRadius.chip))
        )
        .overlay(
            RoundedRectangle(cornerRadius: VLRadius.chip)
                .strokeBorder(EnvironmentHue.sandboxStripe.opacity(0.65), lineWidth: VLBorder.emphasis)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Environment: Sandbox — test data only")
    }
}

/// Diagonal hazard stripes used only by the SANDBOX marker. Decorative and
/// hidden from assistive technology — the badge's accessibility label already
/// carries the meaning.
struct VLDiagonalStripes: View {
    let color: Color
    var spacing: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let width = geometry.size.width
                let height = geometry.size.height
                var x = -height
                while x < width + height {
                    path.move(to: CGPoint(x: x, y: height))
                    path.addLine(to: CGPoint(x: x + height, y: 0))
                    x += spacing
                }
            }
            .stroke(color, lineWidth: 1.5)
        }
        .accessibilityHidden(true)
    }
}

