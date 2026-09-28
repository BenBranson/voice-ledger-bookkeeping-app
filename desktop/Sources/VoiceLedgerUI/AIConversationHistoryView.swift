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
    private let onExport: (ReportExportFormat) -> Void
    /// Owner directive (2026-09-28): "she needs a working memory... make
    /// it where I can delete it, especially between clients" — this
    /// history is what the AI's follow-up questions draw continuity from
    /// (`recentHistory()`), so clearing it between engagements is real
    /// data hygiene, not just tidiness: nothing from a prior client's
    /// conversation should be able to bleed into a new one's context.
    private let onClearHistory: () -> Void
    @State private var showingClearConfirmation = false

    public init(rows: [Row], onExport: @escaping (ReportExportFormat) -> Void = { _ in }, onClearHistory: @escaping () -> Void = {}) {
        self.rows = rows
        self.onExport = onExport
        self.onClearHistory = onClearHistory
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VLSpacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                        Text("AI Conversations")
                            .font(VLTypography.pageTitle())
                            .foregroundStyle(VLColor.textPrimary)
                        Text("Every question you've asked Gemma or OpenAI, and its answer — including the two Generate Report buttons. Most recent first.")
                            .font(VLTypography.caption())
                            .foregroundStyle(VLColor.textMuted)
                    }
                    Spacer()
                    if !rows.isEmpty {
                        ExportMenuButton(onExport: onExport)
                        Button(role: .destructive) {
                            showingClearConfirmation = true
                        } label: {
                            Label("Clear History", systemImage: "trash")
                        }
                    }
                }

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
        .alert("Clear AI Conversation History?", isPresented: $showingClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) { onClearHistory() }
        } message: {
            Text("Removes every question and answer in this client's AI conversation history. This can't be undone — export it first if you want to keep a copy. Nothing else (findings, activity log) is affected.")
        }
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
