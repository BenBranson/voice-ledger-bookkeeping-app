import SwiftUI

/// Renders a `VLStatus` as icon + colored dot + written label.
///
/// This component exists so that "never communicate status through color
/// alone" (docs/VOICE_LEDGER_SPEC.md; WCAG) is satisfied by construction.
/// There is no initializer that produces a bare colored dot — the label is
/// not optional, because a status without a label is the accessibility
/// failure this type is here to prevent.
///
/// The environment marker (`VLEnvironmentBadge`) deliberately lives in its
/// own file, `VLEnvironment.swift` — see that file's doc comment for why
/// environment is a third vocabulary, not a variant of status.
public struct VLStatusPill: View {
    private let status: VLStatus
    private let overrideLabel: String?

    /// - Parameter overrideLabel: replaces the default label text (e.g.
    ///   "Coverage incomplete" instead of "Not checked"). It cannot be
    ///   omitted entirely — passing nil uses `status.label`, never nothing.
    public init(_ status: VLStatus, label overrideLabel: String? = nil) {
        self.status = status
        self.overrideLabel = overrideLabel
    }

    private var text: String { overrideLabel ?? status.label }

    public var body: some View {
        HStack(spacing: VLSpacing.xxs) {
            Image(systemName: status.iconName)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(VLTypography.label())
        }
        .foregroundStyle(status.color)
        .padding(.horizontal, VLSpacing.xs)
        .padding(.vertical, VLSpacing.xxs)
        .background(
            RoundedRectangle(cornerRadius: VLRadius.chip)
                .fill(status.isOutlined ? Color.clear : status.color.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: VLRadius.chip)
                .strokeBorder(
                    status.color.opacity(status.isOutlined ? 0.55 : 0.25),
                    style: StrokeStyle(
                        lineWidth: VLBorder.hairline,
                        // The outlined "action required" state uses a dashed
                        // border so it is distinguishable from the solid
                        // "not checked" gray by form, not just by fill.
                        dash: status.isOutlined ? [3, 2] : []
                    )
                )
        )
        // One accessibility label carrying the meaning, so VoiceOver reads
        // "Status: Review needed" rather than announcing an icon name.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Status: \(text)")
    }
}
