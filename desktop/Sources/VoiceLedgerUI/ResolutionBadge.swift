import SwiftUI
import Core
import DesignSystem

/// Where a finding gets resolved. A manual-QBO fix with a known record
/// becomes a live "Open in QBO ↗" link instead of a static badge.
struct ResolutionBadge: View {
    let action: ProposedAction
    let qboURL: URL?

    /// A link to QBO's blank entry form rather than an existing record.
    private var isNewEntry: Bool { qboURL.map { $0.path.hasSuffix("/expense") && $0.query == nil } ?? false }

    var body: some View {
        if action.resolution == .manualQBO, let qboURL {
            Link(destination: qboURL) {
                Label(isNewEntry ? "Enter in QBO" : "Open in QBO", systemImage: isNewEntry ? "square.and.pencil" : "arrow.up.right.square")
                    .font(VLTypography.caption())
            }
            .help(qboURL.absoluteString)
        } else {
            VLStatusPill(StatusMapping.resolutionStatus(action.resolution), label: action.resolution == .manualQBO ? "Manual QBO" : "Staged")
        }
    }
}
