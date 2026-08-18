import SwiftUI
import Core
import DesignSystem

/// docs/VOICE_LEDGER_SPEC.md's Firm Cockpit: "Next Best Action — the app
/// says where to start." Firm Cockpit itself (every connected client on
/// one screen) is not built — this renders `NextBestAction.compute`'s
/// result for the one realm currently loaded.
public struct NextBestActionView: View {
    private let action: NextBestAction
    private let onNavigate: () -> Void

    public init(action: NextBestAction, onNavigate: @escaping () -> Void) {
        self.action = action
        self.onNavigate = onNavigate
    }

    private var label: String {
        switch action {
        case .reviewHighSeverityFindings(let count):
            return "Review \(count) high-severity finding\(count == 1 ? "" : "s")"
        case .importBankStatement:
            return "Import a bank/card statement to run Bank Feed Cleanup"
        case .completeChecklistItem(let item):
            return "Next: \(item.title)"
        case .allClear:
            return "Nothing urgent — you're caught up"
        }
    }

    private var isActionable: Bool {
        if case .allClear = action { return false }
        return true
    }

    public var body: some View {
        VLCard(accentRail: isActionable ? VLColor.violet : nil) {
            HStack {
                VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                    Text("NEXT BEST ACTION")
                        .font(VLTypography.eyebrow())
                        .tracking(VLTypography.eyebrowTracking)
                        .foregroundStyle(VLColor.textMuted)
                    Text(label)
                        .font(VLTypography.body())
                        .foregroundStyle(VLColor.textPrimary)
                }
                Spacer()
                if isActionable {
                    Button("Go") { onNavigate() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}
