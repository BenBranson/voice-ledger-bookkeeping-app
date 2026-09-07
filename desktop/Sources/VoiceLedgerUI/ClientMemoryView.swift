import SwiftUI
import Core
import DesignSystem

/// docs/VOICE_LEDGER_SPEC.md's Firm Cockpit "Client Memory, With Approval."
/// Every rule created from `FindingDetailView`'s "Always Dismiss" button
/// needs somewhere visible to review and remove — a rule silently applying
/// forever with no way to see or undo it would be exactly the "silently"
/// the spec's own wording rules out.
public struct ClientMemoryView: View {
    private let environment: VLEnvironmentTone
    private let rules: [ClientMemoryRule]
    /// Owner-facing fix (2026-09-05, docs/VOICE_LEDGER_HANDOFF.md's
    /// documented double-tap gap): which rule ids currently have a
    /// "Forget" call in flight, and the last error for a given rule id, if
    /// any — see `AppState.removeClientMemoryRule`'s doc comment.
    private let inFlightRuleIDs: Set<String>
    private let actionError: (ruleID: String, message: String)?
    private let onForget: (ClientMemoryRule) -> Void
    /// Owner directive (2026-08-31): every page ends in a two-tier Ask AI
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
        rules: [ClientMemoryRule],
        inFlightRuleIDs: Set<String> = [],
        actionError: (ruleID: String, message: String)? = nil,
        onForget: @escaping (ClientMemoryRule) -> Void,
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
        self.rules = rules
        self.inFlightRuleIDs = inFlightRuleIDs
        self.actionError = actionError
        self.onForget = onForget
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

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VLSpacing.md) {
                HStack {
                    Text("Client Memory")
                        .font(VLTypography.pageTitle())
                        .foregroundStyle(VLColor.textPrimary)
                    Spacer()
                    VLEnvironmentBadge(environment)
                }

                Text("Rules created from a finding's \"Always Dismiss\" button. Each one auto-dismisses matching findings on every future sync — logged to the Activity Log every time, never silent.")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textMuted)

                if rules.isEmpty {
                    VLCard {
                        Text("No client memory rules yet.")
                            .foregroundStyle(VLColor.textMuted)
                    }
                } else {
                    ForEach(rules) { rule in
                        VLCard {
                            VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                                HStack {
                                    VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                                        Text("\(rule.ruleID.rawValue) — \(rule.vendorName)")
                                            .font(VLTypography.body())
                                            .foregroundStyle(VLColor.textPrimary)
                                        Text("Created by \(rule.createdBy)" + (rule.note.map { " — \($0)" } ?? ""))
                                            .font(VLTypography.caption())
                                            .foregroundStyle(VLColor.textMuted)
                                    }
                                    Spacer()
                                    Button(inFlightRuleIDs.contains(rule.id) ? "Forgetting…" : "Forget") { onForget(rule) }
                                        .buttonStyle(.bordered)
                                        .disabled(inFlightRuleIDs.contains(rule.id))
                                }
                                if actionError?.ruleID == rule.id {
                                    Text(actionError?.message ?? "")
                                        .font(VLTypography.caption())
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }
                }

                TwoTierAskAIPanel(
                    aiStatus: aiStatus,
                    placeholder: "Ask a question about these rules",
                    primaryDisclaimer: "Answers are grounded in the client memory rules on this page, plus a summary of every other open finding across the app — it cannot state a dollar figure or judgment beyond what's already computed, and it never gives tax or legal advice.",
                    primaryAnswer: askAIAnswer,
                    isAskingPrimary: isAskingAI,
                    primaryError: askAIError,
                    onAskPrimary: onAskAI,
                    secondOpinionConfigured: secondOpinionConfigured,
                    secondOpinionDisclaimer: "Sends this page's client memory rules, plus a summary of every other open finding across the app, to OpenAI's API for a second opinion. This costs money per question and only runs when you ask. Still cannot state a dollar figure or judgment beyond what's already computed, and never gives tax or legal advice.",
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
}
