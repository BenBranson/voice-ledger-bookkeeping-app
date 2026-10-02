import SwiftUI
import Core
import DesignSystem

/// docs/VOICE_LEDGER_SPEC.md Page 6 (Type A + C), duplicate-candidate
/// detection slice — see `Core/ChartOfAccountsCleanup.swift`'s doc comment
/// for why matching requires `FullyQualifiedName` and why the merge itself
/// stays a guided manual procedure, never an automated write.
public struct ChartOfAccountsCleanupView: View {
    @Environment(\.qboLinks) private var qboLinks
    public struct ViewState {
        public let environment: VLEnvironmentTone
        public let totalAccountsCount: Int
        /// How many of `totalAccountsCount` decoded a real
        /// `fullyQualifiedName` — the honesty signal (`CLAUDE.md` rule 5):
        /// zero coverage means this scan couldn't run, not that zero
        /// duplicates exist.
        public let accountsWithFullyQualifiedNameCount: Int
        public let groups: [DuplicateAccountCandidateGroup]

        public init(environment: VLEnvironmentTone, totalAccountsCount: Int, accountsWithFullyQualifiedNameCount: Int, groups: [DuplicateAccountCandidateGroup]) {
            self.environment = environment
            self.totalAccountsCount = totalAccountsCount
            self.accountsWithFullyQualifiedNameCount = accountsWithFullyQualifiedNameCount
            self.groups = groups
        }
    }

    private let state: ViewState
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

    public init(
        state: ViewState,
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
        self.state = state
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

    private var hasUsableCoverage: Bool {
        state.totalAccountsCount > 0 && state.accountsWithFullyQualifiedNameCount > 0
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VLSpacing.md) {
                HStack {
                    Text("Chart of Accounts Cleanup")
                        .font(VLTypography.pageTitle())
                        .foregroundStyle(VLColor.textPrimary)
                    Spacer()
                    SyncButton(isSyncing: isSyncing, onSync: onSync)
                    VLEnvironmentBadge(state.environment)
                }

                Text("Detects duplicate-account candidates by comparing each account's full parent path, type, and detail type — never by name alone (a naive name match produces real false positives from QuickBooks' own industry templates). Voice Ledger does not merge accounts itself: merges are permanent, can silently lose reconciliation history, and require matching account/detail types — that stays a manual QBO step by design, not an API gap.")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textMuted)

                if state.totalAccountsCount == 0 {
                    VLCard {
                        Text("No accounts loaded yet. Sync first.")
                            .foregroundStyle(VLColor.textMuted)
                    }
                } else if !hasUsableCoverage {
                    VLCard(accentRail: VLColor.violet) {
                        VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                            HStack {
                                VLStatusPill(.notChecked, label: "Coverage incomplete")
                                Spacer()
                            }
                            Text("None of \(state.totalAccountsCount) synced accounts carried a full parent path (`FullyQualifiedName`) this sync. This scan cannot safely run without it — leaf account names alone are known to produce false-positive matches, so it does not fall back to them. This is not the same as \"zero duplicates found.\"")
                                .font(VLTypography.caption())
                                .foregroundStyle(VLColor.textSecondary)
                        }
                    }
                } else {
                    HStack {
                        VLStatusPill(state.groups.isEmpty ? .verified : .reviewNeeded, label: state.groups.isEmpty ? "No candidates found" : "\(state.groups.count) candidate group(s)")
                        Spacer()
                        Text(verbatim: "\(state.accountsWithFullyQualifiedNameCount) of \(state.totalAccountsCount) accounts checked")
                            .font(VLTypography.caption())
                            .foregroundStyle(VLColor.textMuted)
                    }

                    if state.groups.isEmpty {
                        VLCard {
                            Text("No duplicate accounts found. Every account was compared by its full parent path, type and detail type, and no two match. Nothing to merge.")
                                .font(VLTypography.body())
                                .foregroundStyle(VLColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    ForEach(state.groups) { group in
                        groupCard(group)
                    }
                }

                TwoTierAskAIPanel(
                    aiStatus: aiStatus,
                    placeholder: "Ask a question about this page",
                    primaryDisclaimer: "Answers are grounded in the duplicate-account candidates on this page, plus a summary of every other open finding across the app — it cannot state a dollar figure, severity, or judgment beyond what's already computed, and it never gives tax or legal advice.",
                    primaryAnswer: askAIAnswer,
                    isAskingPrimary: isAskingAI,
                    primaryError: askAIError,
                    onAskPrimary: onAskAI,
                    secondOpinionConfigured: secondOpinionConfigured,
                    secondOpinionDisclaimer: "Sends this page's duplicate-account candidates, plus a summary of every other open finding across the app, to OpenAI's API for a second opinion. This costs money per question and only runs when you ask. Still cannot state a dollar figure or judgment beyond what's already computed, and never gives tax or legal advice.",
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

    private func groupCard(_ group: DuplicateAccountCandidateGroup) -> some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.sm) {
                Text(group.accounts.first?.fullyQualifiedName ?? "(unnamed)")
                    .font(VLTypography.cardTitle())
                    .foregroundStyle(VLColor.textPrimary)

                VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                    ForEach(group.accounts) { account in
                        HStack {
                            Text(account.name)
                                .font(VLTypography.body())
                                .foregroundStyle(VLColor.textSecondary)
                            Text("(\(account.accountType.rawValue)\(account.accountSubType.map { " · \($0)" } ?? ""))")
                                .font(VLTypography.caption())
                                .foregroundStyle(VLColor.textMuted)
                            Spacer()
                            Text(account.currentBalance.accountingDescription)
                                .font(VLTypography.tabularNumeric())
                                .foregroundStyle(VLColor.textMuted)
                            QBOLinkButton(qboLinks.account(id: account.id), compact: true)
                        }
                    }
                }

                Divider()

                Text("If these are genuinely the same account, merge in QuickBooks Online: open Settings > Chart of Accounts, open the account you want to keep, and rename the other to an identical Name and sub-account placement — QBO merges automatically when two accounts match exactly. Export a Balance Sheet and reconciliation reports for both accounts FIRST: a merge is permanent, moves all transaction history onto the surviving account, and cannot be undone.")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textSecondary)
            }
        }
    }
}
