import SwiftUI

/// The base card surface. Most cards in the app should look like this one:
/// calm, dark navy, hairline blue border, barely lifted. Illumination is
/// opt-in via `isActive` and should be rare — if every card glows, a glowing
/// card stops meaning "this one matters."
public struct VLCard<Content: View>: View {
    private let isActive: Bool
    private let accentRail: Color?
    private let content: Content

    /// - Parameters:
    ///   - isActive: applies the cyan illumination reserved for the selected
    ///     or currently-relevant card.
    ///   - accentRail: optional 3pt leading-edge rail. Use it to carry
    ///     page-type or status meaning, never as decoration.
    public init(
        isActive: Bool = false,
        accentRail: Color? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.isActive = isActive
        self.accentRail = accentRail
        self.content = content()
    }

    public var body: some View {
        content
            .padding(VLSpacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: VLRadius.card)
                    .fill(VLColor.surfaceCard)
            )
            .overlay(alignment: .leading) {
                if let accentRail {
                    UnevenRoundedRectangle(
                        topLeadingRadius: VLRadius.card,
                        bottomLeadingRadius: VLRadius.card,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0
                    )
                    .fill(accentRail)
                    .frame(width: VLBorder.accentRail)
                    .accessibilityHidden(true)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: VLRadius.card)
                    .strokeBorder(
                        isActive ? VLColor.borderActive : VLColor.border,
                        lineWidth: isActive ? VLBorder.emphasis : VLBorder.hairline
                    )
            )
            .vlShadow(isActive ? VLElevation.activeGlow : VLElevation.card)
    }
}

/// The three-column strip that sits at the top of every workflow page:
/// DATA AVAILABLE · CHECKS COMPLETED · EXCEPTIONS FOUND.
///
/// This is the clearest UI expression of CLAUDE.md rule 5 — a page cannot
/// claim a clean result without first showing that the data was there and the
/// checks actually ran. Reading left to right answers "can I trust this
/// screen?" before it answers "what did it find?"
public struct VLCoverageStrip: View {
    private let dataAvailable: VLStatus
    private let dataDetail: String
    private let checksCompleted: VLStatus
    private let checksDetail: String
    private let exceptions: VLStatus
    private let exceptionsDetail: String

    public init(
        dataAvailable: VLStatus, dataDetail: String,
        checksCompleted: VLStatus, checksDetail: String,
        exceptions: VLStatus, exceptionsDetail: String
    ) {
        self.dataAvailable = dataAvailable
        self.dataDetail = dataDetail
        self.checksCompleted = checksCompleted
        self.checksDetail = checksDetail
        self.exceptions = exceptions
        self.exceptionsDetail = exceptionsDetail
    }

    public var body: some View {
        HStack(spacing: VLSpacing.sm) {
            column("DATA AVAILABLE", dataAvailable, dataDetail)
            divider
            column("CHECKS COMPLETED", checksCompleted, checksDetail)
            divider
            column("EXCEPTIONS FOUND", exceptions, exceptionsDetail)
        }
        .padding(VLSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: VLRadius.card)
                .fill(VLColor.surfaceInset)
        )
        .overlay(
            RoundedRectangle(cornerRadius: VLRadius.card)
                .strokeBorder(VLColor.border, lineWidth: VLBorder.hairline)
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(VLColor.border)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .accessibilityHidden(true)
    }

    private func column(_ title: String, _ status: VLStatus, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: VLSpacing.xxs) {
            Text(title)
                .font(VLTypography.eyebrow())
                .tracking(VLTypography.eyebrowTracking)
                .foregroundStyle(VLColor.textMuted)
            VLStatusPill(status, label: detail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
