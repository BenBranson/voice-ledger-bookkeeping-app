import SwiftUI
import Core
import DesignSystem

/// docs/VOICE_LEDGER_SPEC.md Page 11 (Type A + C), checklist/dependencies/
/// approvals slice — see `MonthEndChecklist.swift`'s doc comment for what's
/// deliberately not included (QBO close-date reading, a full validation
/// scan).
public struct MonthEndCloseView: View {
    public struct ItemState: Identifiable {
        public let item: ChecklistItem
        public let isUnlocked: Bool
        public let completion: ChecklistItemCompletion?
        /// Computed from real `Finding` data, never a manual guess
        /// (`CLAUDE.md` rule 1) — `nil` when this item has no automatic
        /// readiness signal (e.g. the QBO-side reconciliation/closing-date
        /// steps, which Voice Ledger cannot verify itself).
        public let readyDetail: String?
        public var id: ChecklistItemID { item.id }

        public init(item: ChecklistItem, isUnlocked: Bool, completion: ChecklistItemCompletion?, readyDetail: String?) {
            self.item = item
            self.isUnlocked = isUnlocked
            self.completion = completion
            self.readyDetail = readyDetail
        }
    }

    private let environment: VLEnvironmentTone
    private let items: [ItemState]
    private let onComplete: (ChecklistItemID, _ note: String?) -> Void
    private let onUncomplete: (ChecklistItemID) -> Void

    @State private var noteDrafts: [ChecklistItemID: String] = [:]

    public init(
        environment: VLEnvironmentTone,
        items: [ItemState],
        onComplete: @escaping (ChecklistItemID, _ note: String?) -> Void,
        onUncomplete: @escaping (ChecklistItemID) -> Void
    ) {
        self.environment = environment
        self.items = items
        self.onComplete = onComplete
        self.onUncomplete = onUncomplete
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VLSpacing.md) {
                HStack {
                    Text("Month-End Close")
                        .font(VLTypography.pageTitle())
                        .foregroundStyle(VLColor.textPrimary)
                    Spacer()
                    VLEnvironmentBadge(environment)
                }

                Text("A fixed checklist for this period. Completing an item is your own attestation, not something Voice Ledger verifies for you — where a real signal exists (open findings on another page), it's shown alongside the checkbox, not in place of it.")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textMuted)

                ForEach(items) { state in
                    itemCard(state)
                }
            }
            .padding(VLSpacing.pageGutter)
        }
        .background(VLColor.background)
    }

    private func itemCard(_ state: ItemState) -> some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.sm) {
                HStack {
                    VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                        Text(state.item.title)
                            .font(VLTypography.cardTitle())
                            .foregroundStyle(state.isUnlocked ? VLColor.textPrimary : VLColor.textMuted)
                        Text(state.item.description)
                            .font(VLTypography.caption())
                            .foregroundStyle(VLColor.textMuted)
                    }
                    Spacer()
                    if let completion = state.completion {
                        VLStatusPill(.verified, label: "Done")
                            .help("Completed by \(completion.completedBy) on \(completion.completedAt.formatted(date: .abbreviated, time: .shortened))")
                    } else if !state.isUnlocked {
                        VLStatusPill(.notChecked, label: "Locked")
                    } else {
                        VLStatusPill(.reviewNeeded, label: "Open")
                    }
                }

                if let readyDetail = state.readyDetail {
                    Text(readyDetail)
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textSecondary)
                }

                if let completion = state.completion {
                    HStack {
                        if let note = completion.note, !note.isEmpty {
                            Text("Note: \(note)")
                                .font(VLTypography.caption())
                                .foregroundStyle(VLColor.textMuted)
                        }
                        Spacer()
                        Button("Undo") { onUncomplete(state.item.id) }
                    }
                } else if state.isUnlocked {
                    HStack {
                        TextField("Optional note", text: Binding(
                            get: { noteDrafts[state.item.id] ?? "" },
                            set: { noteDrafts[state.item.id] = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        Button("Mark Complete") {
                            let note = noteDrafts[state.item.id]
                            onComplete(state.item.id, (note?.isEmpty ?? true) ? nil : note)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    Text("Complete the prerequisite step(s) above first.")
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textMuted)
                }
            }
        }
    }
}
