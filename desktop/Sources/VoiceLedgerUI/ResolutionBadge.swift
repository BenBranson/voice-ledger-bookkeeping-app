import SwiftUI
import Core
import DesignSystem

/// Where a finding gets resolved. A manual-QBO fix with a known record
/// becomes a live "Open in QBO ↗" link instead of a static badge.
struct ResolutionBadge: View {
    let action: ProposedAction
    let qboURL: URL?

    var body: some View {
        if action.resolution == .manualQBO, let qboURL {
            Link(destination: qboURL) {
                Label("Open in QBO", systemImage: "arrow.up.right.square")
                    .font(VLTypography.caption())
            }
            .help(qboURL.absoluteString)
        } else {
            VLStatusPill(StatusMapping.resolutionStatus(action.resolution), label: action.resolution == .manualQBO ? "Manual QBO" : "Staged")
        }
    }
}
