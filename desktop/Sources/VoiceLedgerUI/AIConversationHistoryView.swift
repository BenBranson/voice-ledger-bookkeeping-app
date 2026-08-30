import SwiftUI
import DesignSystem

/// Owner directive (2026-08-29): "change voice history section to the
/// conversation [I] have from asking gemma and or open ai" — voice is
/// being deprioritized in favor of the Ask AI panels, so this replaces
/// `VoiceHistoryView` as the sidebar's history screen. Every real
/// question/answer exchange across every panel (per-finding explain/
/// second-opinion, the two report buttons and their follow-up questions,
/// voice's own reasoning fallback — which already routes through the same
/// backend call), most recent first. Primitive params only, same
/// "no VoiceLedgerApp dependency" boundary every other view in this module
/// keeps.
public struct AIConversationHistoryView: View {
    public struct Row: Identifiable {
        public let id: String
        /// What this exchange was about — a finding's title, "Book Health
        /// Report," or "Client Value Summary."
        public let contextLabel: String
        /// "Gemma (local, free)" / "OpenAI" — which tier actually answered.
        public let tierLabel: String
        public let question: String
        public let answer: String
        public let timeLabel: String

        public init(id: String, contextLabel: String, tierLabel: String, question: String, answer: String, timeLabel: String) {
            self.id = id
            self.contextLabel = contextLabel
            self.tierLabel = tierLabel
            self.question = question
            self.answer = answer
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
                Text("AI Conversations")
                    .font(VLTypography.pageTitle())
                    .foregroundStyle(VLColor.textPrimary)

                Text("Every question you've asked Gemma or OpenAI, and its answer — including the two Generate Report buttons. Most recent first.")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textMuted)

                if rows.isEmpty {
                    Text("No conversations yet. Ask a question on any finding, or generate a report on Findings, to start one.")
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
            VStack(alignment: .leading, spacing: VLSpacing.sm) {
                HStack {
                    Text(row.contextLabel.uppercased())
                        .font(VLTypography.eyebrow())
                        .tracking(VLTypography.eyebrowTracking)
                        .foregroundStyle(VLColor.textMuted)
                    Spacer()
                    Text(row.timeLabel)
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textMuted)
                }

                VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                    Text("YOU")
                        .font(VLTypography.eyebrow())
                        .tracking(VLTypography.eyebrowTracking)
                        .foregroundStyle(VLColor.cyan)
                    Text(row.question)
                        .font(VLTypography.body())
                        .foregroundStyle(VLColor.textPrimary)
                        .textSelection(.enabled)
                }

                VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                    Text(row.tierLabel.uppercased())
                        .font(VLTypography.eyebrow())
                        .tracking(VLTypography.eyebrowTracking)
                        .foregroundStyle(VLColor.violet)
                    Text(row.answer)
                        .font(VLTypography.body())
                        .foregroundStyle(VLColor.textPrimary)
                        .textSelection(.enabled)
                }
            }
        }
    }
}
