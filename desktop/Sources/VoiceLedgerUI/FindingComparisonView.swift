import SwiftUI
import Core
import DesignSystem

/// Owner directive (2026-09-06): "if I ask to see two different
/// transactions it should be able to pull both up... like looking at a
/// line of suspects and questioning them to find the real culprit."
/// Presented as a `.sheet` by `RootView`, bound to
/// `AppState.comparedFindingIDs`. Each card is independently closable (the
/// owner's own words: "an x at the top right to close") — closing one
/// just removes it from the array; the sheet itself dismisses once the
/// array is empty, no separate "close everything" action needed.
///
/// This is exactly the UI several real rules already call for:
/// `DuplicatePostedExpenseRule`/`VendorDescriptionMismatchRule`/
/// `VendorPriceIncreaseRule` are all inherently about comparing TWO real
/// things — this view is a more honest presentation of what those rules
/// already assert, not a new kind of claim.
public struct FindingComparisonView: View {
    private let findings: [Finding]
    private let onSelectFinding: (Finding) -> Void
    private let onClose: (Finding) -> Void

    public init(findings: [Finding], onSelectFinding: @escaping (Finding) -> Void, onClose: @escaping (Finding) -> Void) {
        self.findings = findings
        self.onSelectFinding = onSelectFinding
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: VLSpacing.md) {
            Text("Comparing \(findings.count) Finding\(findings.count == 1 ? "" : "s")")
                .font(VLTypography.pageTitle())
                .foregroundStyle(VLColor.textPrimary)

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: VLSpacing.md) {
                    ForEach(findings) { finding in
                        card(for: finding)
                            .frame(width: 320)
                    }
                }
                .padding(.bottom, VLSpacing.sm)
            }
        }
        .padding(VLSpacing.pageGutter)
        .frame(minWidth: 400, minHeight: 420)
        .background(VLColor.background)
    }

    private func card(for finding: Finding) -> some View {
        VLCard(accentRail: finding.severity == .high ? VLColor.violet : nil) {
            VStack(alignment: .leading, spacing: VLSpacing.sm) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                        Text(finding.title)
                            .font(VLTypography.cardTitle())
                            .foregroundStyle(VLColor.textPrimary)
                        if let vendorName = finding.vendorName {
                            Text(vendorName)
                                .font(VLTypography.caption())
                                .foregroundStyle(VLColor.textSecondary)
                        }
                    }
                    Spacer()
                    Button {
                        onClose(finding)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(VLColor.textMuted)
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: VLSpacing.sm) {
                    VLStatusPill(finding.severity == .high ? .urgent : .verified, label: finding.severity.rawValue)
                    Text("Confidence: \(finding.confidence.rawValue)")
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textMuted)
                }

                Text(finding.dollarExposure.description)
                    .font(VLTypography.metricLarge())
                    .foregroundStyle(VLColor.textPrimary)

                if let narrative = finding.narrative {
                    Text(narrative)
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textSecondary)
                        .lineLimit(4)
                }

                if !finding.proposedActions.isEmpty {
                    Divider().overlay(VLColor.border)
                    Text("RECOMMENDATIONS")
                        .font(VLTypography.eyebrow())
                        .tracking(VLTypography.eyebrowTracking)
                        .foregroundStyle(VLColor.textMuted)
                    ForEach(Array(finding.proposedActions.enumerated()), id: \.offset) { _, action in
                        Text("• \(action.title)")
                            .font(VLTypography.caption())
                            .foregroundStyle(VLColor.textSecondary)
                    }
                }

                Button("View Full Detail") { onSelectFinding(finding) }
                    .buttonStyle(.bordered)
            }
        }
    }
}
