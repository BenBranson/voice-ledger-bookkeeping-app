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
    /// Gauntlet Loop, Gauntlet B rounds 15-16 (2026-08-24): `AppState
    /// .dismissFinding` used to navigate back to the list unconditionally,
    /// even when the underlying write threw — a bookkeeper who clicked
    /// Dismiss during a real I/O error saw the SAME screen transition as a
    /// success, with the finding actually still open. Round 16 found
    /// "Remember this vendor" and "Send client question" — literally
    /// adjacent buttons on this same screen — had the identical shape
    /// (their local confirm/draft UI collapsed unconditionally on tap,
    /// regardless of outcome). One shared error string covers all three,
    /// since `AppState` only ever has one such action in flight/failed per
    /// finding at a time.
    private let findingActionError: String?
    /// Gauntlet Loop, Gauntlet B round 18 (2026-08-24): `dismissFinding`,
    /// `attestCompletion` (on `GuidedProcedureView`), `createClientMemoryRule`,
    /// and `recordClientQuestionSent` had no in-flight marker at all, unlike
    /// `applyStagedFix`'s `isApplyingFix` — so their buttons had nothing to
    /// disable, and an ordinary rapid double-tap fired two concurrent
    /// calls, producing duplicate Activity Log entries (or duplicate
    /// `ClientMemoryRule` rows) for one click.
    private let isFindingActionInFlight: Bool
    private let hasClientMemoryRule: Bool
    private let onStartProcedure: (ProposedAction) -> Void
    private let onApplyFix: () -> Void
    private let onSendClientQuestion: (String) -> Void
    private let onRememberVendor: () -> Void
    private let onDismiss: () -> Void

    @State private var isConfirmingApplyFix = false
    @State private var isDraftingClientQuestion = false
    @State private var draftedQuestionText = ""
    @State private var isConfirmingRememberVendor = false

    public init(
        finding: Finding,
        writeAccessEnabled: Bool,
        isApplyingFix: Bool,
        applyFixError: String?,
        findingActionError: String? = nil,
        isFindingActionInFlight: Bool = false,
        hasClientMemoryRule: Bool = false,
        onStartProcedure: @escaping (ProposedAction) -> Void,
        onApplyFix: @escaping () -> Void,
        onSendClientQuestion: @escaping (String) -> Void,
        onRememberVendor: @escaping () -> Void = {},
        onDismiss: @escaping () -> Void
    ) {
        self.finding = finding
        self.writeAccessEnabled = writeAccessEnabled
        self.isApplyingFix = isApplyingFix
        self.applyFixError = applyFixError
        self.findingActionError = findingActionError
        self.isFindingActionInFlight = isFindingActionInFlight
        self.hasClientMemoryRule = hasClientMemoryRule
        self.onStartProcedure = onStartProcedure
        self.onApplyFix = onApplyFix
        self.onSendClientQuestion = onSendClientQuestion
        self.onRememberVendor = onRememberVendor
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VLSpacing.md) {
                header
                // Gauntlet Loop, Gauntlet B round 17 (2026-08-24): a fresh
                // critic found this used to render inside `actionSection`,
                // ABOVE `clientQuestionSection`/`clientMemorySection` in
                // page order — a bookkeeper who scrolled down to draft a
                // client question or remember a vendor, and that specific
                // action failed, would see the error appear off-screen
                // above their scroll position with no auto-scroll and no
                // per-section inline error. Moved to a fixed position
                // right below the title, visible regardless of which
                // action further down the page actually failed.
                if let findingActionError {
                    Text(findingActionError)
                        .font(VLTypography.caption())
                        .foregroundStyle(.red)
                }
                evidenceSection
                if let principle = accountingPrinciple {
                    whyThisMattersSection(principle)
                }
                if let action = finding.proposedActions.first {
                    actionSection(action)
                }
                clientQuestionSection
                if let vendorName = finding.vendorName {
                    clientMemorySection(vendorName)
                }
            }
            .padding(VLSpacing.pageGutter)
        }
        .background(VLColor.background)
    }

    /// docs/VOICE_LEDGER_SPEC.md's Firm Cockpit "Client Memory, With
    /// Approval" — see `ClientMemoryRule`'s doc comment for the full scope
    /// and its deliberate conservatism (exact vendor match, scoped to one
    /// rule, never bundled into Dismiss). This button only appears when the
    /// finding has a clear vendor and no rule already covers it.
    private func clientMemorySection(_ vendorName: String) -> some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.sm) {
                Text("CLIENT MEMORY")
                    .font(VLTypography.eyebrow())
                    .tracking(VLTypography.eyebrowTracking)
                    .foregroundStyle(VLColor.textMuted)

                if hasClientMemoryRule {
                    Text("Findings like this for \(vendorName) are automatically dismissed per an existing client memory rule.")
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textMuted)
                } else if isConfirmingRememberVendor {
                    Text("Every future \(finding.ruleID.rawValue) finding for \(vendorName) will be automatically dismissed, not just this one. You can remove this later.")
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textSecondary)
                    HStack(spacing: VLSpacing.sm) {
                        // Gauntlet Loop, Gauntlet B round 17 (2026-08-24):
                        // disabled while an Apply Fix write is in flight for
                        // THIS finding — a fresh critic found tapping this
                        // mid-write would clear `findingActionError` before
                        // Apply Fix's own outcome was known, hiding a real,
                        // still-unresolved error.
                        Button("Confirm — Always Dismiss for \(vendorName)") {
                            onRememberVendor()
                            isConfirmingRememberVendor = false
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isApplyingFix || isFindingActionInFlight)
                        Button("Cancel") { isConfirmingRememberVendor = false }
                            .buttonStyle(.bordered)
                    }
                } else {
                    Button("Always Dismiss for \(vendorName)") { isConfirmingRememberVendor = true }
                        .buttonStyle(.bordered)
                }
            }
        }
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
                        // Same reasoning as `clientMemorySection`'s "Confirm"
                        // button — round 17.
                        Button("Mark as Sent") {
                            onSendClientQuestion(draftedQuestionText)
                            isDraftingClientQuestion = false
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(draftedQuestionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isApplyingFix || isFindingActionInFlight)
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
                Text("Source: \(sourceLabel)")
            }
            .font(VLTypography.caption())
            .foregroundStyle(VLColor.textMuted)
            // Gauntlet Loop, Gauntlet B (2026-08-23): a deterministic,
            // Core-computed plain-English sentence — see `Finding.narrative`'s
            // doc comment for why this is not the AI kill switch's
            // territory (no AI integration exists in this codebase at all
            // yet). Rules that haven't been given one yet leave this nil,
            // rendering nothing extra — no regression for the other 16.
            if let narrative = finding.narrative {
                Text(narrative)
                    .font(VLTypography.body())
                    .foregroundStyle(VLColor.textSecondary)
                    .padding(.top, VLSpacing.xxs)
            }
        }
    }

    /// docs/VOICE_LEDGER_SPEC.md's Firm Cockpit "Training Mode — every flag
    /// answers 'why was this flagged?' with the underlying accounting
    /// principle, not just the rule." **This is that answer, not the rest
    /// of Training Mode** (no broader tutorial/help system exists). Another
    /// case of a field every rule already computes (`RuleIdentity
    /// .accountingPrinciple`, plain English, written once per rule) that
    /// had zero UI call sites until now — found by the same read-the-real-
    /// call-sites check that caught the Dismiss and reversal gaps.
    /// Was hardcoded to `"QBO API"` — wrong for `VL-RECON-MISSING-001`/
    /// `VL-VENDOR-MISMATCH-001`, whose evidence includes an imported
    /// statement line, not just QBO-read data. Derived from the finding's
    /// real `provenance` instead, same fix pattern as the other three gaps
    /// found tonight (a real value existed, the UI just wasn't using it).
    private var sourceLabel: String {
        let sources = Set(finding.provenance.map { provenance -> String in
            switch provenance {
            case .qboAPI: return "QBO API"
            case .importedFile: return "Imported file"
            }
        })
        return sources.isEmpty ? "Unknown" : sources.sorted().joined(separator: " + ")
    }

    private var accountingPrinciple: String? {
        RuleRegistry.all.first { $0.identity.id == finding.ruleID }?.identity.accountingPrinciple
    }

    private func whyThisMattersSection(_ principle: String) -> some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.xs) {
                Text("WHY THIS MATTERS")
                    .font(VLTypography.eyebrow())
                    .tracking(VLTypography.eyebrowTracking)
                    .foregroundStyle(VLColor.textMuted)
                Text(principle)
                    .font(VLTypography.body())
                    .foregroundStyle(VLColor.textPrimary)
            }
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
                    VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                        Text("Transaction \(item.transactionID)")
                            .font(VLTypography.body())
                            .foregroundStyle(VLColor.textPrimary)
                        // Gauntlet Loop, Gauntlet B (2026-08-23): show the
                        // ACTUAL VALUE for each matched field, not just its
                        // name — "amount, date, paymentAccount" required
                        // opening QBO to find out what those fields actually
                        // contained. Falls back to field names alone
                        // (previous behavior) when a rule hasn't been given
                        // `fieldValues` yet, so the other 16 rules render
                        // exactly as before.
                        if item.fieldValues.isEmpty {
                            if !item.highlightedFields.isEmpty {
                                Text(item.highlightedFields.joined(separator: ", "))
                                    .font(VLTypography.caption())
                                    .foregroundStyle(VLColor.textMuted)
                            }
                        } else {
                            ForEach(item.highlightedFields, id: \.self) { field in
                                if let value = item.fieldValues[field] {
                                    HStack {
                                        Text(Self.evidenceFieldLabel(field))
                                            .font(VLTypography.caption())
                                            .foregroundStyle(VLColor.textMuted)
                                        Spacer()
                                        Text(value)
                                            .font(VLTypography.tabularNumeric())
                                            .foregroundStyle(VLColor.textSecondary)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, VLSpacing.xxs)
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

    private static func evidenceFieldLabel(_ field: String) -> String {
        switch field {
        case "paymentAccount": return "Payment account"
        case "docNumber": return "Reference number"
        default: return field.capitalized
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

                // Gauntlet Loop, Gauntlet B (2026-08-23): spec'd at
                // docs/phase-0/05_FINDING_SCHEMA.md §5.1 as the "Before
                // proceeding" note — never rendered anywhere until now.
                // Shown only when the rule populated it; empty for the
                // other 16 rules, so no change to their screens.
                if !finding.preApprovalChecklist.isEmpty {
                    VStack(alignment: .leading, spacing: VLSpacing.xs) {
                        Text("BEFORE YOU PROCEED")
                            .font(VLTypography.eyebrow())
                            .tracking(VLTypography.eyebrowTracking)
                            .foregroundStyle(VLColor.textMuted)
                        ForEach(finding.preApprovalChecklist, id: \.self) { step in
                            HStack(alignment: .top, spacing: VLSpacing.xs) {
                                Text("☐")
                                    .foregroundStyle(VLColor.textMuted)
                                Text(step)
                                    .font(VLTypography.caption())
                                    .foregroundStyle(VLColor.textSecondary)
                            }
                        }
                    }
                    .padding(.top, VLSpacing.xs)
                }

                // Gauntlet Loop, Gauntlet B critic pass (2026-08-23): a
                // fresh critic found the Approve path had dollar-denominated
                // consequences (above) while leaving the finding OPEN —
                // neither approved nor dismissed — had none stated anywhere.
                // Shown only when the rule populated `riskIfIgnored`; nil
                // for the other 16 rules, no change to their screens.
                if let riskIfIgnored = finding.riskIfIgnored {
                    VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                        Text("IF LEFT OPEN")
                            .font(VLTypography.eyebrow())
                            .tracking(VLTypography.eyebrowTracking)
                            .foregroundStyle(VLColor.textMuted)
                        Text(riskIfIgnored)
                            .font(VLTypography.caption())
                            .foregroundStyle(VLColor.textSecondary)
                    }
                    .padding(.top, VLSpacing.xs)
                }

                if let details = action.apiWriteDetails {
                    applyFixSection(details)
                } else {
                    VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                        HStack(spacing: VLSpacing.sm) {
                            Button("Approve") { onStartProcedure(action) }
                                .buttonStyle(.borderedProminent)
                            Button("Dismiss") { onDismiss() }
                                .buttonStyle(.bordered)
                                .disabled(isFindingActionInFlight)
                        }
                        // Gauntlet Loop, Gauntlet B critic pass (2026-08-23):
                        // Dismiss is a single click with no confirmation and
                        // no adjacent text at all — unlike "Always Dismiss
                        // for <vendor>" (Client Memory), which DOES get a
                        // confirm step. A bookkeeper had no way to know from
                        // the screen that Dismiss permanently suppresses
                        // re-detection of this exact transaction pair
                        // (`AppState.dismissFinding` feeds the id into
                        // `RuleContext.dismissedFindingIDs`, which every
                        // rule checks on every future sync) — not a snooze,
                        // not FYI-only.
                        Text("Dismiss suppresses this exact finding permanently — it will not reappear on future syncs unless something about these two transactions changes.")
                            .font(VLTypography.caption())
                            .foregroundStyle(VLColor.textMuted)
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
                        .disabled(isFindingActionInFlight)
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
