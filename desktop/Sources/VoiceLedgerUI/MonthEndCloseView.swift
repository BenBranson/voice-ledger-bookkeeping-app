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
        /// Owner directive (2026-08-29): backs the "Review Findings" link
        /// — `nil`/`0` hides it (nothing to review, or this item has no
        /// automatic readiness signal at all).
        public let openFindingsCount: Int?
        /// docs/VOICE_LEDGER_HANDOFF.md D3 — `MonthEndChecklist.isStale`,
        /// computed by the caller (this view has no watermark of its own
        /// to compare against). Meaningless when `completion` is `nil`.
        public let isStale: Bool
        public var id: ChecklistItemID { item.id }

        public init(item: ChecklistItem, isUnlocked: Bool, completion: ChecklistItemCompletion?, readyDetail: String?, openFindingsCount: Int? = nil, isStale: Bool = false) {
            self.item = item
            self.isUnlocked = isUnlocked
            self.completion = completion
            self.readyDetail = readyDetail
            self.openFindingsCount = openFindingsCount
            self.isStale = isStale
        }
    }

    private let environment: VLEnvironmentTone
    private let items: [ItemState]
    private let onComplete: (ChecklistItemID, _ note: String?) -> Void
    private let onUncomplete: (ChecklistItemID) -> Void
    /// Owner directive (2026-08-29): "a direct 'Go review these findings'
    /// link on each locked/open item." `nil` (the default) renders no
    /// link — only the caller (`RootView`) knows how to actually navigate
    /// to another screen, so this stays a plain pass-through.
    private let onReviewFindings: ((ChecklistItemID) -> Void)?
    /// docs/VOICE_LEDGER_SPEC.md Page 11: "carry-forward items" — items a
    /// human explicitly deferred to next period (`CarryForwardMark`, marked
    /// from `FindingDetailView`). Was persisted and displayed on the Close
    /// Package page only; this page never showed it despite being the one
    /// the spec names for it (2026-09-11 fix). Never affects `isUnlocked`/
    /// completion — purely informational, so a bookkeeper closing the
    /// period sees what was knowingly pushed to next month without having
    /// to separately open Close Package to find out.
    private let carryForwardItems: [(mark: CarryForwardMark, findingTitle: String, dollarExposure: Money)]
    /// Owner directive (2026-08-30): "a lot of the sections say unsynced
    /// yet there is no refresh button for them to sync" — see `SyncButton`.
    private let isSyncing: Bool
    private let onSync: () -> Void
    /// Owner directive (2026-08-30): every page ends in a two-tier Ask AI
    /// panel — see `TwoTierAskAIPanel`.
    private let aiStatus: AIStatus?
    private let askAIAnswer: String?
    private let isAskingAI: Bool
    private let askAIError: String?
    private let onAskAI: (String) -> Void
    private let secondOpinionConfigured: Bool
    private let secondOpinionAnswer: String?
    private let isAskingSecondOpinion: Bool
    private let secondOpinionError: String?
    private let onAskSecondOpinion: (String) -> Void
    private let alternateModelTiers: [TwoTierAskAIPanel.AlternateModelTier]

    @State private var noteDrafts: [ChecklistItemID: String] = [:]

    public init(
        environment: VLEnvironmentTone,
        items: [ItemState],
        onComplete: @escaping (ChecklistItemID, _ note: String?) -> Void,
        onUncomplete: @escaping (ChecklistItemID) -> Void,
        onReviewFindings: ((ChecklistItemID) -> Void)? = nil,
        carryForwardItems: [(mark: CarryForwardMark, findingTitle: String, dollarExposure: Money)] = [],
        isSyncing: Bool = false,
        onSync: @escaping () -> Void = {},
        aiStatus: AIStatus? = nil,
        askAIAnswer: String? = nil,
        isAskingAI: Bool = false,
        askAIError: String? = nil,
        onAskAI: @escaping (String) -> Void = { _ in },
        secondOpinionConfigured: Bool = false,
        secondOpinionAnswer: String? = nil,
        isAskingSecondOpinion: Bool = false,
        secondOpinionError: String? = nil,
        onAskSecondOpinion: @escaping (String) -> Void = { _ in },
        alternateModelTiers: [TwoTierAskAIPanel.AlternateModelTier] = []
    ) {
        self.environment = environment
        self.items = items
        self.onComplete = onComplete
        self.onUncomplete = onUncomplete
        self.onReviewFindings = onReviewFindings
        self.carryForwardItems = carryForwardItems
        self.isSyncing = isSyncing
        self.onSync = onSync
        self.aiStatus = aiStatus
        self.askAIAnswer = askAIAnswer
        self.isAskingAI = isAskingAI
        self.askAIError = askAIError
        self.onAskAI = onAskAI
        self.secondOpinionConfigured = secondOpinionConfigured
        self.secondOpinionAnswer = secondOpinionAnswer
        self.isAskingSecondOpinion = isAskingSecondOpinion
        self.secondOpinionError = secondOpinionError
        self.onAskSecondOpinion = onAskSecondOpinion
        self.alternateModelTiers = alternateModelTiers
    }

    /// Owner directive (2026-08-29): "light visual grouping... over the
    /// same five steps." Reuses the sidebar's own existing CLEANUP/CLOSE
    /// vocabulary (`AppSidebar.swift`'s section titles) rather than
    /// inventing new stage names — the same five real items, just labeled
    /// consistently with how the rest of the app already groups them.
    private static let stageForItemID: [String: String] = [
        "resolve-cleanup-assessment": "CLEANUP",
        "review-balance-sheet-integrity": "CLEANUP",
        "review-bank-feed": "RECONCILIATION",
        "reconcile-bank-accounts": "RECONCILIATION",
        "set-qbo-closing-date": "CLOSE"
    ]

    private var stages: [(label: String, items: [ItemState])] {
        var seen: [String] = []
        var buckets: [String: [ItemState]] = [:]
        for state in items {
            let label = Self.stageForItemID[state.item.id.rawValue] ?? "OTHER"
            if buckets[label] == nil { seen.append(label) }
            buckets[label, default: []].append(state)
        }
        return seen.map { (label: $0, items: buckets[$0] ?? []) }
    }

    /// Owner directive (2026-08-29): "a real progress indicator ('3 of 5
    /// steps complete')... not a fabricated health score, just surfacing a
    /// number that already exists." Derived directly from `items` (each
    /// already carries whether it has a real completion) rather than a
    /// second source of truth — the same count
    /// `MonthEndChecklist.completionStatus` computes, just read here from
    /// what's already on screen.
    private var completedCount: Int { items.filter { $0.completion != nil }.count }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VLSpacing.md) {
                HStack {
                    Text("Month-End Close")
                        .font(VLTypography.pageTitle())
                        .foregroundStyle(VLColor.textPrimary)
                    Spacer()
                    SyncButton(isSyncing: isSyncing, onSync: onSync)
                    VLEnvironmentBadge(environment)
                }

                Text("A fixed checklist for this period. Completing an item is your own attestation, not something Voice Ledger verifies for you — where a real signal exists (open findings on another page), it's shown alongside the checkbox, not in place of it.")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textMuted)

                progressBar

                ForEach(stages, id: \.label) { stage in
                    VStack(alignment: .leading, spacing: VLSpacing.sm) {
                        Text(stage.label)
                            .font(VLTypography.eyebrow())
                            .tracking(VLTypography.eyebrowTracking)
                            .foregroundStyle(VLColor.textMuted)
                        ForEach(stage.items) { state in
                            itemCard(state)
                        }
                    }
                }

                if !carryForwardItems.isEmpty {
                    carryForwardSection
                }

                TwoTierAskAIPanel(
                    aiStatus: aiStatus,
                    placeholder: "Ask a question about this page",
                    primaryDisclaimer: "Answers are grounded in the checklist items on this page, plus a summary of every other open finding across the app — it cannot state a dollar figure, severity, or judgment beyond what's already computed, and it never gives tax or legal advice.",
                    primaryAnswer: askAIAnswer,
                    isAskingPrimary: isAskingAI,
                    primaryError: askAIError,
                    onAskPrimary: onAskAI,
                    secondOpinionConfigured: secondOpinionConfigured,
                    secondOpinionDisclaimer: "Sends this page's checklist status, plus a summary of every other open finding across the app, to OpenAI's API for a second opinion. This costs money per question and only runs when you ask. Still cannot state a dollar figure or judgment beyond what's already computed, and never gives tax or legal advice.",
                    secondOpinionAnswer: secondOpinionAnswer,
                    isAskingSecondOpinion: isAskingSecondOpinion,
                    secondOpinionError: secondOpinionError,
                    onAskSecondOpinion: onAskSecondOpinion,
                    alternateModelTiers: alternateModelTiers
                )
            }
            .padding(VLSpacing.pageGutter)
        }
        .background(VLColor.background)
    }

    private var progressBar: some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.xs) {
                HStack {
                    Text(verbatim: "\(completedCount) of \(items.count) steps complete")
                        .font(VLTypography.cardTitle())
                        .foregroundStyle(VLColor.textPrimary)
                    Spacer()
                }
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(VLColor.border)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(VLColor.cyan)
                            .frame(width: items.isEmpty ? 0 : geometry.size.width * CGFloat(completedCount) / CGFloat(items.count))
                    }
                }
                .frame(height: 6)
            }
        }
    }

    private var carryForwardSection: some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.xs) {
                Text("CARRY-FORWARD ITEMS")
                    .font(VLTypography.eyebrow())
                    .tracking(VLTypography.eyebrowTracking)
                    .foregroundStyle(VLColor.textMuted)
                Text("Findings explicitly deferred to next period rather than resolved or dismissed now — still open, still on their normal pages, listed here only so closing this period doesn't lose track of what was knowingly pushed forward.")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textMuted)
                ForEach(carryForwardItems, id: \.mark.id) { item in
                    VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                        HStack {
                            Text(item.findingTitle)
                                .font(VLTypography.body())
                                .foregroundStyle(VLColor.textPrimary)
                            Spacer()
                            Text(item.dollarExposure.accountingDescription)
                                .font(VLTypography.tabularNumeric())
                                .foregroundStyle(VLColor.textPrimary)
                        }
                        Text("Marked by \(item.mark.markedBy)\(item.mark.reason.map { " — \($0)" } ?? "")")
                            .font(VLTypography.caption())
                            .foregroundStyle(VLColor.textMuted)
                    }
                }
            }
        }
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
                    if let completion = state.completion, state.isStale {
                        // docs/VOICE_LEDGER_HANDOFF.md D3: the rules or
                        // materiality policy that produced the evidence
                        // this was completed against have since changed —
                        // CLAUDE.md rule 5's "unknown is never green"
                        // applied to an attestation, not just a check.
                        VLStatusPill(.reviewNeeded, label: "Stale — re-verify")
                            .help("Completed by \(completion.completedBy) on \(completion.completedAt.formatted(date: .abbreviated, time: .shortened)), but the rules or materiality policy used to evaluate this have changed since — re-check before trusting this as still complete.")
                    } else if let completion = state.completion {
                        VLStatusPill(.verified, label: "Done")
                            .help("Completed by \(completion.completedBy) on \(completion.completedAt.formatted(date: .abbreviated, time: .shortened))")
                    } else if !state.isUnlocked {
                        VLStatusPill(.notChecked, label: "Locked")
                    } else {
                        VLStatusPill(.reviewNeeded, label: "Open")
                    }
                }

                if let readyDetail = state.readyDetail {
                    HStack(spacing: VLSpacing.xs) {
                        Text(readyDetail)
                            .font(VLTypography.caption())
                            .foregroundStyle(VLColor.textSecondary)
                        if let onReviewFindings, let count = state.openFindingsCount, count > 0 {
                            Button("Review Findings →") { onReviewFindings(state.item.id) }
                                .buttonStyle(.plain)
                                .font(VLTypography.caption())
                                .foregroundStyle(VLColor.cyan)
                        }
                    }
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
