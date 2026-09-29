import SwiftUI
import Core
import DesignSystem

/// docs/VOICE_LEDGER_SPEC.md Page 8: "Strongest API coverage" — Balance
/// Sheet, Trial Balance, General Ledger, Account List, Transaction List,
/// journal entries, bills/payments/deposits/purchases/transfers,
/// attachments. **Read-only**, and grown well past the original two-rule
/// slice: `VL-BS-NEGBAL-001` (negative balances), `VL-OBE-BALANCE-001`
/// (Opening Balance Equity), `VL-BS-UNDEP-001` (undeposited-funds aging),
/// `VL-FORCED-RECON-001` (forced reconciliation), `VL-REPORT-TIE-001`
/// (report tie-out), `VL-CLOSED-PERIOD-DRIFT-001` (a locked period's
/// numbers moving after close), and `VL-BS-DRCR-001` (Income/Expense
/// accounts on the wrong side of the Trial Balance) — corrected 2026-09-11:
/// the last two were already filed under `CleanupCategory
/// .balanceSheetIntegrity` but a stale hand-typed literal in `AppState`
/// (`balanceSheetIntegrityRuleIDs`) had never been updated to include them,
/// so neither ever rendered here despite being fully built and tested.
/// **Still genuinely not built**: suspense-activity and stale-clearing-
/// account rules (no such rule exists yet — would need this sandbox to
/// have a real suspense/clearing account to verify against first, per
/// `CLAUDE.md` rule 6), and Balance Sheet/Trial Balance/General Ledger
/// report DATA is not rendered on this page itself — each has its own
/// dedicated report page instead.
public struct BalanceSheetIntegrityView: View {
    public struct RuleSummary: Identifiable {
        public let ruleID: String
        public let title: String
        public let findings: [Finding]
        public var id: String { ruleID }

        public init(ruleID: String, title: String, findings: [Finding]) {
            self.ruleID = ruleID
            self.title = title
            self.findings = findings
        }
    }

    private let qboURL: (Finding) -> URL?
    private let environment: VLEnvironmentTone
    private let coverageStatus: VLStatus
    private let coverageDetail: String
    private let summaries: [RuleSummary]
    private let onSelectFinding: (Finding) -> Void
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
        environment: VLEnvironmentTone,
        coverageStatus: VLStatus,
        coverageDetail: String,
        summaries: [RuleSummary],
        onSelectFinding: @escaping (Finding) -> Void,
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
        alternateModelTiers: [TwoTierAskAIPanel.AlternateModelTier] = [],
        qboURL: @escaping (Finding) -> URL? = { _ in nil }
    ) {
        self.qboURL = qboURL
        self.environment = environment
        self.coverageStatus = coverageStatus
        self.coverageDetail = coverageDetail
        self.summaries = summaries
        self.onSelectFinding = onSelectFinding
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

    private var totalFindingCount: Int { summaries.reduce(0) { $0 + $1.findings.count } }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VLSpacing.md) {
                HStack {
                    Text("Balance Sheet Integrity")
                        .font(VLTypography.pageTitle())
                        .foregroundStyle(VLColor.textPrimary)
                    Spacer()
                    SyncButton(isSyncing: isSyncing, onSync: onSync)
                    VLEnvironmentBadge(environment)
                }

                Text("Read-only. Checks account balances and Trial Balance structure against expected signals (sign convention, account subtype, a locked period's numbers staying put). Suspense-activity and stale-clearing-account checks aren't built yet — this sandbox has no such account to verify a rule against.")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textMuted)

                VLCoverageStrip(
                    dataAvailable: coverageStatus,
                    dataDetail: coverageDetail,
                    checksCompleted: coverageStatus,
                    checksDetail: "\(summaries.count) rule\(summaries.count == 1 ? "" : "s")",
                    exceptions: totalFindingCount == 0 ? .verified : .reviewNeeded,
                    exceptionsDetail: totalFindingCount == 0 ? "None" : "\(totalFindingCount) open"
                )

                if summaries.isEmpty {
                    VLCard {
                        Text("No Balance Sheet Integrity rules registered.")
                            .foregroundStyle(VLColor.textMuted)
                    }
                } else {
                    ForEach(summaries) { summary in
                        ruleSection(summary)
                    }
                }

                TwoTierAskAIPanel(
                    aiStatus: aiStatus,
                    placeholder: "Ask a question about this page",
                    primaryDisclaimer: "Answers are grounded in the findings on this page, plus a summary of every other open finding across the app — it cannot state a dollar figure, severity, or judgment beyond what's already computed, and it never gives tax or legal advice.",
                    primaryAnswer: askAIAnswer,
                    isAskingPrimary: isAskingAI,
                    primaryError: askAIError,
                    onAskPrimary: onAskAI,
                    secondOpinionConfigured: secondOpinionConfigured,
                    secondOpinionDisclaimer: "Sends this page's findings, plus a summary of every other open finding across the app, to OpenAI's API for a second opinion. This costs money per question and only runs when you ask. Still cannot state a dollar figure or judgment beyond what's already computed, and never gives tax or legal advice.",
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

    private func ruleSection(_ summary: RuleSummary) -> some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.sm) {
                HStack {
                    Text(summary.title)
                        .font(VLTypography.cardTitle())
                        .foregroundStyle(VLColor.textPrimary)
                    Spacer()
                    VLStatusPill(summary.findings.isEmpty ? .verified : .reviewNeeded, label: "\(summary.findings.count)")
                }
                if summary.findings.isEmpty {
                    Text("None found.")
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textMuted)
                } else {
                    ForEach(summary.findings) { finding in
                        HStack {
                            Button {
                                onSelectFinding(finding)
                            } label: {
                                HStack {
                                    Text(ClientText.polish(finding.title))
                                        .font(VLTypography.body())
                                        .foregroundStyle(VLColor.textSecondary)
                                    Spacer()
                                    Text(finding.dollarExposure.accountingDescription)
                                        .font(VLTypography.tabularNumeric())
                                        .foregroundStyle(VLColor.textPrimary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if let action = finding.proposedActions.first {
                                ResolutionBadge(action: action, qboURL: qboURL(finding))
                            }
                        }
                    }
                }
            }
        }
    }
}
