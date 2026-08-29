import SwiftUI
import DesignSystem

/// "When I open the app I should be able to read previous conversations" —
/// the persisted-transcript half of that ask (`VoiceEngine.transcriptHistory`,
/// backed by `ClientStore.appendVoiceTranscriptEntry`/`loadVoiceTranscript`).
/// Primitive params only, same "no VoiceLedgerApp dependency" boundary every
/// other view in this module already keeps — the row shape below stands in
/// for `VoiceTranscriptEntry` without this module needing to import `Core`.
public struct VoiceHistoryView: View {
    public struct Row: Identifiable {
        public let id: String
        public let isUser: Bool
        public let text: String
        public let timeLabel: String

        public init(id: String, isUser: Bool, text: String, timeLabel: String) {
            self.id = id
            self.isUser = isUser
            self.text = text
            self.timeLabel = timeLabel
        }
    }

    private let rows: [Row]

    public init(rows: [Row]) {
        self.rows = rows
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VLSpacing.md) {
                Text("Voice History")
                    .font(VLTypography.pageTitle())
                    .foregroundStyle(VLColor.textPrimary)

                if rows.isEmpty {
                    Text("No voice conversations yet. Say \"start a conversation\" to begin one.")
                        .font(VLTypography.body())
                        .foregroundStyle(VLColor.textMuted)
                } else {
                    ForEach(rows) { row in
                        rowView(row)
                    }
                }
            }
            .padding(VLSpacing.pageGutter)
        }
        .background(VLColor.background)
    }

    private func rowView(_ row: Row) -> some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                HStack {
                    Text(row.isUser ? "YOU" : "VOICE LEDGER")
                        .font(VLTypography.eyebrow())
                        .tracking(VLTypography.eyebrowTracking)
                        .foregroundStyle(row.isUser ? VLColor.cyan : VLColor.violet)
                    Spacer()
                    Text(row.timeLabel)
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textMuted)
                }
                Text(row.text)
                    .font(VLTypography.body())
                    .foregroundStyle(VLColor.textPrimary)
            }
        }
    }
}
