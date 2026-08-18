import SwiftUI
import Core
import DesignSystem

/// docs/phase-0/11_VERTICAL_SLICE.md §11.4's worked example, rendered:
/// evidence, proposed action, and a button to act on it. Branch B
/// (`.manualQBO`) goes straight to the guided procedure, matching
/// acceptance criterion 12: never offered a write path it can't complete.
/// `.stagedAPI` actions (first consumer: `VL-CC-PAYMENT-001`'s structural
/// match) instead get an "Apply Fix" button — gated on `writeAccessEnabled`
/// and a separate explicit confirmation step showing before/after, per
/// CLAUDE.md rule 2's "detect -> draft -> review -> push."
public struct FindingDetailView: View {
    private let finding: Finding
    private let writeAccessEnabled: Bool
    private let isApplyingFix: Bool
    private let applyFixError: String?
    private let onStartProcedure: (ProposedAction) -> Void
    private let onApplyFix: () -> Void
    private let onSendClientQuestion: (String) -> Void
    private let onDismiss: () -> Void

    @State private var isConfirmingApplyFix = false
    @State private var isDraftingClientQuestion = false
    @State private var draftedQuestionText = ""

    public init(
        finding: Finding,
        writeAccessEnabled: Bool,
        isApplyingFix: Bool,
        applyFixError: String?,
        onStartProcedure: @escaping (ProposedAction) -> Void,
        onApplyFix: @escaping () -> Void,
        onSendClientQuestion: @escaping (String) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.finding = finding
        self.writeAccessEnabled = writeAccessEnabled
        self.isApplyingFix = isApplyingFix
        self.applyFixError = applyFixError
        self.onStartProcedure = onStartProcedure
        self.onApplyFix = onApplyFix
        self.onSendClientQuestion = onSendClientQuestion
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VLSpacing.md) {
                header
                evidenceSection
                if let action = finding.proposedActions.first {
                    actionSection(action)
                }
                clientQuestionSection
            }
            .padding(VLSpacing.pageGutter)
        }
        .background(VLColor.background)
    }

    /// docs/VOICE_LEDGER_SPEC.md's Firm Cockpit "Client Question Builder" —
    /// see `ClientQuestionDrafter`'s doc comment for exactly what this is
    /// and isn't (a template-generated starting draft, always shown
    /// editable before anything is recorded as sent; no answer-tracking).
    private var clientQuestionSection: some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.sm) {
                Text("CLIENT QUESTION")
                    .font(VLTypography.eyebrow())
                    .tracking(VLTypography.eyebrowTracking)
                    .foregroundStyle(VLColor.textMuted)

                if isDraftingClientQuestion {
                    Text("A starting draft — edit freely before sending. Voice Ledger does not send this itself; \"Mark as Sent\" only records that you did.")
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textMuted)
                    TextEditor(text: $draftedQuestionText)
                        .font(VLTypography.body())
                        .frame(minHeight: 160)
                        .padding(VLSpacing.xs)
                        .background(VLColor.background)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(VLColor.border))
                    HStack(spacing: VLSpacing.sm) {
                        Button("Mark as Sent") {
                            onSendClientQuestion(draftedQuestionText)
                            isDraftingClientQuestion = false
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(draftedQuestionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("Cancel") { isDraftingClientQuestion = false }
                            .buttonStyle(.bordered)
                    }
                } else {
                    Button("Draft Client Question") {
                        draftedQuestionText = ClientQuestionDrafter.draft(finding: finding, clientName: nil)
                        isDraftingClientQuestion = true
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: VLSpacing.xs) {
            HStack {
                Text(finding.title)
                    .font(VLTypography.pageTitle())
                    .foregroundStyle(VLColor.textPrimary)
                Spacer()
                VLStatusPill(StatusMapping.severityStatus(finding.severity), label: finding.severity == .high ? "High severity" : "Low severity")
            }
            HStack(spacing: VLSpacing.sm) {
                Text("Confidence: \(finding.confidence.rawValue.capitalized)")
                Text("·")
                Text("Detection: automatic")
                Text("·")
                Text("Source: QBO API")
            }
            .font(VLTypography.caption())
            .foregroundStyle(VLColor.textMuted)
        }
    }

    private var evidenceSection: some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.sm) {
                Text("EVIDENCE")
                    .font(VLTypography.eyebrow())
                    .tracking(VLTypography.eyebrowTracking)
                    .foregroundStyle(VLColor.textMuted)
                ForEach(finding.evidence, id: \.transactionID) { item in
                    HStack {
                        Text("Transaction \(item.transactionID)")
                            .font(VLTypography.body())
                            .foregroundStyle(VLColor.textPrimary)
                        Spacer()
                        if !item.highlightedFields.isEmpty {
                            Text(item.highlightedFields.joined(separator: ", "))
                                .font(VLTypography.caption())
                                .foregroundStyle(VLColor.textMuted)
                        }
                    }
                }
                HStack {
                    Text("Dollar exposure")
                        .foregroundStyle(VLColor.textMuted)
                    Spacer()
                    Text(finding.dollarExposure.description)
                        .font(VLTypography.tabularNumericEmphasis())
                        .foregroundStyle(VLColor.textPrimary)
                }
            }
        }
    }

    private func actionSection(_ action: ProposedAction) -> some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.sm) {
                HStack {
                    Text(action.title)
                        .font(VLTypography.cardTitle())
                        .foregroundStyle(VLColor.textPrimary)
                    Spacer()
                    VLStatusPill(StatusMapping.resolutionStatus(action.resolution), label: action.resolution == .manualQBO ? "Manual QBO" : "Staged")
                }

                if action.resolution == .manualQBO {
                    Text("Voice Ledger cannot complete this write — it requires action in QBO directly.")
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textMuted)
                }

                ForEach(consequenceLines(action.consequences), id: \.self) { line in
                    Text("• \(line)")
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textSecondary)
                }

                Text("Reversal: \(reversalLine(action.reversal))")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textSecondary)

                if let details = action.apiWriteDetails {
                    applyFixSection(details)
                } else {
                    HStack(spacing: VLSpacing.sm) {
                        Button("Approve") { onStartProcedure(action) }
                            .buttonStyle(.borderedProminent)
                        Button("Dismiss") { onDismiss() }
                            .buttonStyle(.bordered)
                    }
                    .padding(.top, VLSpacing.xs)
                }
            }
        }
    }

    /// The "review" step of CLAUDE.md rule 2's detect -> draft -> review ->
    /// push: before/after account names are shown and a second explicit tap
    /// is required (`isConfirmingApplyFix`) — approving isn't enough on its
    /// own to send a write.
    private func applyFixSection(_ details: StagedAPIWriteDetails) -> some View {
        VStack(alignment: .leading, spacing: VLSpacing.sm) {
            if !writeAccessEnabled {
                Text("Write access is off for this connection — enable it on the Connection page before applying this fix.")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textMuted)
            }

            HStack(spacing: VLSpacing.sm) {
                Text(details.currentAccountName)
                    .strikethrough()
                    .foregroundStyle(VLColor.textMuted)
                Text("→")
                    .foregroundStyle(VLColor.textMuted)
                Text(details.suggestedAccountName)
                    .foregroundStyle(VLColor.textPrimary)
            }
            .font(VLTypography.body())

            if let applyFixError {
                Text(applyFixError)
                    .font(VLTypography.caption())
                    .foregroundStyle(.red)
            }

            if isConfirmingApplyFix {
                Text("This sends a real write to QBO. Confirm the account change above is correct.")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textSecondary)
                HStack(spacing: VLSpacing.sm) {
                    Button(isApplyingFix ? "Applying…" : "Confirm Apply Fix") {
                        onApplyFix()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isApplyingFix)
                    Button("Cancel") { isConfirmingApplyFix = false }
                        .buttonStyle(.bordered)
                        .disabled(isApplyingFix)
                }
            } else {
                HStack(spacing: VLSpacing.sm) {
                    Button("Apply Fix") { isConfirmingApplyFix = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(!writeAccessEnabled)
                    Button("Dismiss") { onDismiss() }
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(.top, VLSpacing.xs)
    }

    /// `ProposedAction.reversal` was computed by every rule but never
    /// rendered anywhere — a real gap, found the same way `dismissedFindingIDs`'s
    /// wiring gap was: reading the actual call sites rather than assuming a
    /// value that exists in `Core` is necessarily reaching the screen.
    private func reversalLine(_ reversal: ReversalPlan) -> String {
        switch reversal {
        case .reversibleManually(let procedure): return procedure
        case .irreversible: return "This cannot be undone once done."
        }
    }

    private func consequenceLines(_ consequences: [Consequence]) -> [String] {
        consequences.map { consequence in
            switch consequence {
            case .reconciliation(let text): return "Reconciliation: \(text)"
            case .reporting(let text): return "Reporting: \(text)"
            case .auditTrail(let text): return "Audit trail: \(text)"
            }
        }
    }
}
