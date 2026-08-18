import SwiftUI
import Core
import DesignSystem

/// docs/phase-0/10_STAGING_APPROVAL_AUDIT.md §10.8: *Voice Ledger Activity &
/// Correction Log*, not "Audit Log" (`CLAUDE.md` terminology). Append-only,
/// rendered here in reverse-chronological order.
public struct ActivityLogView: View {
    private let entries: [ActivityLogEntry]

    public init(entries: [ActivityLogEntry]) {
        self.entries = entries
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VLSpacing.md) {
                Text("Activity & Correction Log")
                    .font(VLTypography.pageTitle())
                    .foregroundStyle(VLColor.textPrimary)

                Text("Can prove: what Voice Ledger detected, proposed, and submitted; what you approved; before/after entity snapshots. Cannot prove: who changed something directly in QBO outside the app.")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textMuted)

                if entries.isEmpty {
                    VLCard {
                        Text("No activity yet.")
                            .foregroundStyle(VLColor.textMuted)
                    }
                } else {
                    ForEach(entries.sorted(by: { $0.recordedAt > $1.recordedAt })) { entry in
                        EntryRow(entry: entry)
                    }
                }
            }
            .padding(VLSpacing.pageGutter)
        }
        .background(VLColor.background)
    }
}

private struct EntryRow: View {
    let entry: ActivityLogEntry

    var body: some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                HStack {
                    Text(kindLabel)
                        .font(VLTypography.cardTitle())
                        .foregroundStyle(VLColor.textPrimary)
                    Spacer()
                    Text(entry.recordedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textMuted)
                }
                Text(actorLabel)
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textSecondary)
                if let note = entry.note {
                    Text(note)
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textMuted)
                }
                if entry.beforeSnapshotJSON != nil || entry.afterSnapshotJSON != nil {
                    DisclosureGroup("Before / after entity snapshot") {
                        VStack(alignment: .leading, spacing: VLSpacing.xs) {
                            if let before = entry.beforeSnapshotJSON {
                                Text("BEFORE").font(VLTypography.eyebrow()).foregroundStyle(VLColor.textMuted)
                                Text(before).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            }
                            if let after = entry.afterSnapshotJSON {
                                Text("AFTER").font(VLTypography.eyebrow()).foregroundStyle(VLColor.textMuted)
                                Text(after).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            }
                        }
                        .padding(.top, VLSpacing.xs)
                    }
                    .font(VLTypography.caption())
                }
            }
        }
    }

    private var kindLabel: String {
        switch entry.kind {
        case .findingDetected: return "Finding detected"
        case .manualCompletionAttested: return "Manual completion attested"
        case .findingResolved: return "Finding resolved"
        case .apiWriteApplied: return "API write applied"
        case .clientQuestionDrafted: return "Client question sent"
        case .findingDismissed: return "Finding dismissed"
        case .clientMemoryRuleCreated: return "Client memory rule created"
        case .clientMemoryRuleRemoved: return "Client memory rule removed"
        case .findingAutoDismissedByClientMemory: return "Auto-dismissed (client memory)"
        }
    }

    private var actorLabel: String {
        switch entry.actor {
        case .user(let name): return "By \(name)"
        case .system: return "By Voice Ledger"
        }
    }
}
