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
    /// docs/VOICE_LEDGER_SPEC.md's Firm Cockpit Close Package "carry-forward
    /// items" — `nil` when this finding has no active mark.
    private let carryForwardMark: CarryForwardMark?
    /// Owner directive (2026-08-29): "I pressed mark as done... yet after
    /// doing this the page still looks the same" — `true` right after an
    /// attestation's immediate resync confirmed the underlying issue is
    /// STILL present, so the screen can say so explicitly instead of
    /// silently looking unchanged (which is indistinguishable from nothing
    /// having happened at all).
    private let justAttestedStillOpen: Bool
    private let onStartProcedure: (ProposedAction) -> Void
    private let onApplyFix: () -> Void
    private let onSendClientQuestion: (String) -> Void
    /// The most recently sent client question for this finding, from the
    /// Activity Log (`ActivityKind.clientQuestionDrafted`) — `nil` when
    /// none has been sent yet. Lets this view offer "record the answer"
    /// without itself reading the log (it stays a dumb rendering of
    /// whatever it's given, same posture as `hasClientMemoryRule`).
    private let lastSentClientQuestion: String?
    /// The recorded client reply (`ActivityKind.clientQuestionAnswered`),
    /// when one exists.
    private let clientQuestionAnswer: String?
    private let onRecordClientQuestionAnswer: (String) -> Void
    /// docs/VOICE_LEDGER_HANDOFF.md D4's write journal — non-`nil` when a
    /// prior write attempt against this finding's exact purchase+line is
    /// still `.submitted`/`.unknown`. While set, `applyFixSection` blocks
    /// "Apply Fix" and offers "Resolve Pending Write" instead — the same
    /// block `AppState.applyStagedFix` itself enforces, made visible here
    /// so a bookkeeper isn't left guessing why the button doesn't work.
    private let pendingWriteJournalEntry: WriteJournalEntry?
    private let isResolvingPendingWrite: Bool
    private let onResolvePendingWrite: () -> Void
    private let onRememberVendor: () -> Void
    private let onDismiss: () -> Void
    /// Owner directive (2026-08-29): "a checkmark ... or a button saying
    /// finished." Same underlying verified-not-self-reported mechanism as
    /// `GuidedProcedureView`'s "I completed this in QBO" (records the
    /// attestation, then `AppState.attestCompletion` immediately re-syncs
    /// so the finding only actually clears once QBO confirms it) — this is
    /// just a faster path to it for a bookkeeper who already knows what
    /// they did and doesn't need the steps/pitfalls walkthrough first. Only
    /// offered alongside `Approve`/`Dismiss` (manualQBO resolution) — a
    /// `.stagedAPI` finding's "done" action already is Apply Fix.
    private let onMarkDone: (String?) -> Void
    private let onMarkCarriedForward: (String?) -> Void
    private let onUnmarkCarriedForward: () -> Void
    /// docs/VOICE_LEDGER_SPEC.md's Ask [AI] panel — `nil` `aiStatus` means
    /// it hasn't been checked yet (never assumed available).
    private let aiStatus: AIStatus?
    private let askAIAnswer: String?
    private let isAskingAI: Bool
    private let askAIError: String?
    private let onAskAI: (String) -> Void
    /// Owner directive (2026-08-29): the opt-in "second opinion" tier —
    /// separate answer/error/in-flight state from the free tier above so
    /// both can be visible at once, never one overwriting the other.
    private let secondOpinionAnswer: String?
    private let isAskingSecondOpinion: Bool
    private let secondOpinionError: String?
    private let onAskSecondOpinion: (String) -> Void
    /// `nil` until `/ai/status` has actually been checked — never assumed
    /// available, same posture as `aiStatus` itself.
    private let secondOpinionConfigured: Bool
    /// Owner directive (2026-08-31): "a 'Draft a message to the client
    /// about this' button" — separate answer/error/in-flight state from
    /// `askAIAnswer` above, same reasoning as the second-opinion tier: a
    /// different `AppState.draftClientMessage` call, different
    /// `contextKey`, must never overwrite the regular Q&A panel's answer.
    private let clientMessageAnswer: String?
    private let isDraftingClientMessage: Bool
    private let clientMessageError: String?
    private let onDraftClientMessage: (String) -> Void
    /// Navigates back to the Findings list. Owner directive (2026-08-29):
    /// "there needs to be a back button in findings especially when
    /// looking at the individual finding screens."
    private let onBack: () -> Void

    @State private var isConfirmingApplyFix = false
    @State private var isDraftingClientQuestion = false
    @State private var draftedQuestionText = ""
    @State private var isRecordingAnswer = false
    @State private var answerDraft = ""
    @State private var isConfirmingRememberVendor = false
    @State private var isDraftingCarryForwardReason = false
    @State private var carryForwardReasonDraft = ""
    /// Owner directive (2026-08-29): "for every finding I can mark what I
    /// did to resolve it" — a resolution type + free-text detail, combined
    /// into the same `note` `onMarkDone` already accepts (see
    /// `ResolutionType.combinedNote`'s doc comment for why this isn't a new
    /// persisted field).
    @State private var isLoggingResolution = false
    @State private var resolutionTypeDraft: ResolutionType?
    @State private var resolutionDetailDraft = ""

    public init(
        finding: Finding,
        writeAccessEnabled: Bool,
        isApplyingFix: Bool,
        applyFixError: String?,
        findingActionError: String? = nil,
        isFindingActionInFlight: Bool = false,
        hasClientMemoryRule: Bool = false,
        carryForwardMark: CarryForwardMark? = nil,
        justAttestedStillOpen: Bool = false,
        onStartProcedure: @escaping (ProposedAction) -> Void,
        onApplyFix: @escaping () -> Void,
        onSendClientQuestion: @escaping (String) -> Void,
        lastSentClientQuestion: String? = nil,
        clientQuestionAnswer: String? = nil,
        onRecordClientQuestionAnswer: @escaping (String) -> Void = { _ in },
        pendingWriteJournalEntry: WriteJournalEntry? = nil,
        isResolvingPendingWrite: Bool = false,
        onResolvePendingWrite: @escaping () -> Void = {},
        onRememberVendor: @escaping () -> Void = {},
        onDismiss: @escaping () -> Void,
        onMarkDone: @escaping (String?) -> Void = { _ in },
        onMarkCarriedForward: @escaping (String?) -> Void = { _ in },
        onUnmarkCarriedForward: @escaping () -> Void = {},
        aiStatus: AIStatus? = nil,
        askAIAnswer: String? = nil,
        isAskingAI: Bool = false,
        askAIError: String? = nil,
        onAskAI: @escaping (String) -> Void = { _ in },
        secondOpinionAnswer: String? = nil,
        isAskingSecondOpinion: Bool = false,
        secondOpinionError: String? = nil,
        onAskSecondOpinion: @escaping (String) -> Void = { _ in },
        secondOpinionConfigured: Bool = false,
        clientMessageAnswer: String? = nil,
        isDraftingClientMessage: Bool = false,
        clientMessageError: String? = nil,
        onDraftClientMessage: @escaping (String) -> Void = { _ in },
        onBack: @escaping () -> Void = {}
    ) {
        self.finding = finding
        self.writeAccessEnabled = writeAccessEnabled
        self.isApplyingFix = isApplyingFix
        self.applyFixError = applyFixError
        self.findingActionError = findingActionError
        self.isFindingActionInFlight = isFindingActionInFlight
        self.hasClientMemoryRule = hasClientMemoryRule
        self.carryForwardMark = carryForwardMark
        self.justAttestedStillOpen = justAttestedStillOpen
        self.onStartProcedure = onStartProcedure
        self.onApplyFix = onApplyFix
        self.onSendClientQuestion = onSendClientQuestion
        self.lastSentClientQuestion = lastSentClientQuestion
        self.clientQuestionAnswer = clientQuestionAnswer
        self.onRecordClientQuestionAnswer = onRecordClientQuestionAnswer
        self.pendingWriteJournalEntry = pendingWriteJournalEntry
        self.isResolvingPendingWrite = isResolvingPendingWrite
        self.onResolvePendingWrite = onResolvePendingWrite
        self.onRememberVendor = onRememberVendor
        self.onDismiss = onDismiss
        self.onMarkDone = onMarkDone
        self.onMarkCarriedForward = onMarkCarriedForward
        self.onUnmarkCarriedForward = onUnmarkCarriedForward
        self.aiStatus = aiStatus
        self.askAIAnswer = askAIAnswer
        self.isAskingAI = isAskingAI
        self.askAIError = askAIError
        self.onAskAI = onAskAI
        self.secondOpinionAnswer = secondOpinionAnswer
        self.isAskingSecondOpinion = isAskingSecondOpinion
        self.secondOpinionError = secondOpinionError
        self.onAskSecondOpinion = onAskSecondOpinion
        self.secondOpinionConfigured = secondOpinionConfigured
        self.clientMessageAnswer = clientMessageAnswer
        self.isDraftingClientMessage = isDraftingClientMessage
        self.clientMessageError = clientMessageError
        self.onDraftClientMessage = onDraftClientMessage
        self.onBack = onBack
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VLSpacing.md) {
                Button(action: onBack) {
                    HStack(spacing: VLSpacing.xxs) {
                        Image(systemName: "chevron.left")
                        Text("Back to Findings")
                    }
                    .font(VLTypography.label())
                }
                .buttonStyle(.plain)
                .foregroundStyle(VLColor.textSecondary)

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
                clientMessageSection
                if let vendorName = finding.vendorName {
                    clientMemorySection(vendorName)
                }
                carryForwardSection
                askAISection
                if secondOpinionConfigured {
                    secondOpinionSection
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

    /// docs/VOICE_LEDGER_SPEC.md's Firm Cockpit Close Package "carry-forward
    /// items" — a human's explicit decision to defer this finding to next
    /// period rather than resolve or dismiss it now. Never changes the
    /// finding's own status; it stays exactly as open as it already was and
    /// keeps appearing everywhere it normally would.
    private var carryForwardSection: some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.sm) {
                Text("CARRY FORWARD")
                    .font(VLTypography.eyebrow())
                    .tracking(VLTypography.eyebrowTracking)
                    .foregroundStyle(VLColor.textMuted)

                if let carryForwardMark {
                    Text("Marked to carry forward by \(carryForwardMark.markedBy) on \(carryForwardMark.markedAt.formatted(date: .abbreviated, time: .shortened))\(carryForwardMark.reason.map { " — \($0)" } ?? "").")
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textSecondary)
                    Button("Remove Carry-Forward Mark") { onUnmarkCarriedForward() }
                        .buttonStyle(.bordered)
                        .disabled(isFindingActionInFlight)
                } else if isDraftingCarryForwardReason {
                    Text("Defers this finding to next period's Close Package list. It stays open and keeps appearing everywhere it already does — this only adds a note that it was deliberately deferred, not forgotten.")
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textMuted)
                    TextField("Optional reason", text: $carryForwardReasonDraft)
                        .textFieldStyle(.roundedBorder)
                    HStack(spacing: VLSpacing.sm) {
                        Button("Confirm — Carry Forward") {
                            onMarkCarriedForward(carryForwardReasonDraft.isEmpty ? nil : carryForwardReasonDraft)
                            isDraftingCarryForwardReason = false
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isApplyingFix || isFindingActionInFlight)
                        Button("Cancel") { isDraftingCarryForwardReason = false }
                            .buttonStyle(.bordered)
                    }
                } else {
                    Button("Carry Forward to Next Period") { isDraftingCarryForwardReason = true }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    /// docs/VOICE_LEDGER_SPEC.md's Ask [AI] panel — "every page ends with
    /// an Ask [AI] panel, because the moment of uncertainty is exactly
    /// when you need to ask rather than guess." OpenAI-backed. The AI only
    /// ever sees this finding's own already-computed fields
    /// (`AskAIContext.compose`, Core, pure) — it cannot invent a number
    /// this screen doesn't already show, per CLAUDE.md rule 1's boundary,
    /// enforced independently again by the backend's own system prompt.
    /// Owner directive (2026-08-29): "use gemma:e4b ... to write out why the
    /// discrepancy needs investigation, list out options and give a
    /// recommendation and then write out why it's recommended." The
    /// underlying facts (evidence, the accounting principle, the one
    /// proposed action, its consequences, `riskIfIgnored`) are already all
    /// deterministic Core output, shown above — this button just asks the
    /// same grounded Ask AI pipeline `AskAIPanelView` already uses (backend
    /// `AskAIContext.compose`, currently Ollama `gemma4:12b`) to narrate
    /// them in plain English in one click, instead of requiring the owner
    /// to type a question every time. CLAUDE.md rule 1 is unaffected: this
    /// asks for PROSE about facts already computed and rendered on screen,
    /// never a new number, severity, or recommendation of its own.
    private static let explainPrompt = "In plain English: why does this discrepancy need investigating, what's the recommended fix, and why is that the right call here?"

    private var askAISection: some View {
        AskAIPanelView(
            disclaimer: "Answers are grounded strictly in this finding's own fields shown above — it cannot state a dollar figure, severity, or judgment beyond what's already here, and it never gives tax or legal advice.",
            placeholder: "Ask a question about this finding",
            aiStatus: aiStatus,
            answer: askAIAnswer,
            isAsking: isAskingAI,
            error: askAIError,
            onAsk: onAskAI,
            quickAskLabel: "Explain This Finding",
            onQuickAsk: { onAskAI(Self.explainPrompt) }
        )
    }

    /// Owner directive (2026-08-29): an opt-in, per-question "second
    /// opinion" from OpenAI, distinct from the free/local panel above —
    /// never automatic, always a deliberate click, since every question
    /// here is a real, non-free API request. The disclaimer states plainly
    /// what is and isn't sent, matching `AskAIContext.composeRedacted`'s
    /// own honest-scope doc comment: the vendor name is redacted, dollar
    /// amounts/dates/the finding's own description are not.
    private var secondOpinionSection: some View {
        AskAIPanelView(
            title: "SECOND OPINION (OPENAI)",
            disclaimer: "Sends this finding's numbers, dates, and description to OpenAI's API for a second opinion — the vendor name and any account named in the recommended fix are redacted first, but other details (like account names only mentioned in the explanation text) are not. This costs money per question and only runs when you ask. Still cannot state a dollar figure or judgment beyond what's already on this screen, and never gives tax or legal advice.",
            placeholder: "Ask OpenAI for a second opinion",
            // This section only renders once `secondOpinionConfigured` is
            // already true (the caller checked `/ai/status` for real) — no
            // separate `AIStatus` needed here. `nil` renders the panel's
            // normal content (not a "not configured"/"disabled" message);
            // the app-wide AI kill switch is still enforced server-side for
            // this tier exactly the same as the free one.
            aiStatus: nil,
            answer: secondOpinionAnswer,
            isAsking: isAskingSecondOpinion,
            error: secondOpinionError,
            onAsk: onAskSecondOpinion,
            quickAskLabel: "Get a Second Opinion (OpenAI)",
            onQuickAsk: { onAskSecondOpinion(Self.explainPrompt) }
        )
    }

    /// Owner directive (2026-08-31): "a 'Draft a message to the client
    /// about this' button." A DIFFERENT feature from `clientQuestionSection`
    /// below — that one is a fixed, non-AI template for "I'm not sure, can
    /// you confirm this?" uncertain findings. This one is AI-narrated
    /// (`format: .clientMessage`, its own client-facing system prompt on
    /// the backend — no internal tool jargon, no invented figures), for
    /// when the bookkeeper already knows what's going on and wants a
    /// flexible, plain-English update explaining it to the client.
    private var clientMessageSection: some View {
        AskAIPanelView(
            title: "DRAFT CLIENT MESSAGE",
            disclaimer: "AI-drafted, grounded strictly in this finding's own fields shown above — always review and edit before sending, Voice Ledger never sends anything itself. Different from the Client Question above: this explains what's going on, in plain language with no internal jargon, rather than asking the client to confirm something.",
            placeholder: "Ask for a different version (e.g. \"make it more formal\")",
            aiStatus: aiStatus,
            answer: clientMessageAnswer,
            isAsking: isDraftingClientMessage,
            error: clientMessageError,
            onAsk: onDraftClientMessage,
            quickAskLabel: "Draft a Message",
            onQuickAsk: { onDraftClientMessage(Self.draftClientMessageDefaultPrompt) }
        )
    }

    private static let draftClientMessageDefaultPrompt = "Draft a short, professional message explaining this to the client and what, if anything, is needed from them."

    /// docs/VOICE_LEDGER_SPEC.md's Firm Cockpit "Client Question Builder" —
    /// see `ClientQuestionDrafter`'s doc comment for exactly what this is
    /// and isn't (a template-generated starting draft, always shown
    /// editable before anything is recorded as sent). Once sent
    /// (`lastSentClientQuestion` non-nil), also offers recording the
    /// client's reply — the bookkeeper types in what the client said, same
    /// "recorded, not verified by the app" posture as everything else
    /// `.manualQBO` on this screen.
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

                if let lastSentClientQuestion {
                    Divider()
                    Text("SENT")
                        .font(VLTypography.eyebrow())
                        .tracking(VLTypography.eyebrowTracking)
                        .foregroundStyle(VLColor.textMuted)
                    Text(lastSentClientQuestion)
                        .font(VLTypography.body())
                        .foregroundStyle(VLColor.textSecondary)

                    if let clientQuestionAnswer {
                        Text("ANSWER")
                            .font(VLTypography.eyebrow())
                            .tracking(VLTypography.eyebrowTracking)
                            .foregroundStyle(VLColor.textMuted)
                        Text(clientQuestionAnswer)
                            .font(VLTypography.body())
                            .foregroundStyle(VLColor.textPrimary)
                            .padding(VLSpacing.xs)
                            .background(VLColor.background)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(VLColor.border))
                    } else if isRecordingAnswer {
                        TextEditor(text: $answerDraft)
                            .font(VLTypography.body())
                            .frame(minHeight: 100)
                            .padding(VLSpacing.xs)
                            .background(VLColor.background)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(VLColor.border))
                        HStack(spacing: VLSpacing.sm) {
                            Button("Save Answer") {
                                onRecordClientQuestionAnswer(answerDraft)
                                isRecordingAnswer = false
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(answerDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isApplyingFix || isFindingActionInFlight)
                            Button("Cancel") { isRecordingAnswer = false }
                                .buttonStyle(.bordered)
                        }
                    } else {
                        Button("Record Client's Answer") {
                            answerDraft = ""
                            isRecordingAnswer = true
                        }
                        .buttonStyle(.bordered)
                    }
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

    /// Owner directive (2026-08-29): "I pressed mark as done... yet after
    /// doing this the page still looks the same." Root-caused: this
    /// section never checked `finding.status` at all — a finding that
    /// genuinely became `.resolved` (or `.dismissed`) after a successful
    /// re-check looked byte-for-byte identical to one still `.open`,
    /// because the exact same Approve/Mark as Done/Dismiss row rendered
    /// regardless. `@ViewBuilder` so the resolved/dismissed branch can be a
    /// visually distinct card instead of reusing this one's shape.
    @ViewBuilder
    private func actionSection(_ action: ProposedAction) -> some View {
        if finding.status != .open {
            resolvedOrDismissedCard
        } else {
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
                } else if isLoggingResolution {
                    resolutionLogSection
                } else {
                    VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                        // Owner directive (2026-08-29): "I pressed mark as
                        // done... yet after doing this the page still looks
                        // the same" — because the re-check correctly found
                        // the issue still open in QBO, which is honest, but
                        // silent. Says so explicitly instead of leaving the
                        // owner to wonder whether the click did anything.
                        if justAttestedStillOpen {
                            Text("Checked against QBO just now — this issue is still there. If you already fixed it, give QBO a moment to save the change, then try again.")
                                .font(VLTypography.caption())
                                .foregroundStyle(.orange)
                        }
                        HStack(spacing: VLSpacing.sm) {
                            Button("Approve") { onStartProcedure(action) }
                                .buttonStyle(.borderedProminent)
                            // Owner directive (2026-08-29): a fast "I already
                            // did this in QBO" path that doesn't require
                            // stepping through Approve's guided procedure
                            // first — same verified-on-resync mechanism as
                            // that screen's "I completed this in QBO"
                            // (`AppState.attestCompletion`), just reachable
                            // in one click for a bookkeeper working a long
                            // triage queue. Reveals `resolutionLogSection`
                            // rather than firing immediately — the owner's
                            // own ask (2026-08-29): "for every finding I can
                            // mark what I did to resolve it," so the client
                            // value report has something real to report
                            // beyond "N findings resolved."
                            Button("Mark as Done") { isLoggingResolution = true }
                                .buttonStyle(.bordered)
                                .disabled(isFindingActionInFlight)
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
                        Text("Mark as Done re-checks this against QBO right now — it only clears if the underlying issue is actually gone. Dismiss suppresses this exact finding permanently — it will not reappear on future syncs unless something about these two transactions changes.")
                            .font(VLTypography.caption())
                            .foregroundStyle(VLColor.textMuted)
                    }
                    .padding(.top, VLSpacing.xs)
                }
            }
        }
        }
    }

    /// The confirmation state a bookkeeper actually gets when a finding is
    /// no longer `.open` — replaces the Approve/Mark as Done/Dismiss row
    /// entirely, so a genuinely successful resolution is unmistakable
    /// rather than looking identical to an untouched finding.
    private var resolvedOrDismissedCard: some View {
        VLCard(accentRail: finding.status == .resolved ? VLStatus.verified.color : VLColor.textMuted) {
            VStack(alignment: .leading, spacing: VLSpacing.xs) {
                Text(finding.status == .resolved ? "✓ Resolved" : "Dismissed")
                    .font(VLTypography.cardTitle())
                    .foregroundStyle(finding.status == .resolved ? VLStatus.verified.color : VLColor.textMuted)
                Text(finding.status == .resolved
                     ? "The next sync confirmed this is actually fixed in QBO."
                     : "Reviewed and dismissed as not a real issue — it will not reappear unless something about these transactions changes.")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textSecondary)
            }
        }
    }

    /// Owner directive (2026-08-29): "for every finding I can mark what I
    /// did to resolve it... maybe by a dropdown menu with clickable
    /// options or even have an empty field option to personally write out
    /// what I did." Both, combined via `ResolutionType.combinedNote` into
    /// the one `note` `AppState.attestCompletion` already persists and the
    /// Client Value Report already reads back out — no new schema, no new
    /// report payload field, just a better-filled-in version of a field
    /// that already existed and already flowed through.
    private var resolutionLogSection: some View {
        VStack(alignment: .leading, spacing: VLSpacing.sm) {
            // Owner directive (2026-08-29): "the finding isn't resolved
            // until I click or type in what I did to resolve it" — a
            // deliberate change from the first version of this section,
            // which offered this as optional. Picking a category OR typing
            // a detail (either is enough) is now required before the
            // button below will actually fire.
            Text("What did you do to resolve this? Pick a category, or type it out — the Client Value Report will quote this back to show your work.")
                .font(VLTypography.caption())
                .foregroundStyle(VLColor.textSecondary)

            Picker("Type", selection: $resolutionTypeDraft) {
                Text("Choose a category (optional)").tag(ResolutionType?.none)
                ForEach(ResolutionType.allCases) { type in
                    Text(type.label).tag(ResolutionType?.some(type))
                }
            }
            .labelsHidden()

            TextEditor(text: $resolutionDetailDraft)
                .font(VLTypography.body())
                .frame(minHeight: 70)
                .padding(VLSpacing.xs)
                .background(VLColor.background)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(VLColor.border))

            HStack(spacing: VLSpacing.sm) {
                Button(isFindingActionInFlight ? "Checking…" : "Save & Mark as Done") {
                    onMarkDone(ResolutionType.combinedNote(type: resolutionTypeDraft, detail: resolutionDetailDraft))
                    isLoggingResolution = false
                    resolutionTypeDraft = nil
                    resolutionDetailDraft = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(isFindingActionInFlight || (resolutionTypeDraft == nil && resolutionDetailDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                Button("Cancel") { isLoggingResolution = false }
                    .buttonStyle(.bordered)
                    .disabled(isFindingActionInFlight)
            }
        }
        .padding(.top, VLSpacing.xs)
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

            if let pending = pendingWriteJournalEntry {
                pendingWriteSection(pending)
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
                    .disabled(isApplyingFix || pendingWriteJournalEntry != nil)
                    Button("Cancel") { isConfirmingApplyFix = false }
                        .buttonStyle(.bordered)
                        .disabled(isApplyingFix)
                }
            } else {
                HStack(spacing: VLSpacing.sm) {
                    Button("Apply Fix") { isConfirmingApplyFix = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(!writeAccessEnabled || pendingWriteJournalEntry != nil)
                    Button("Dismiss") { onDismiss() }
                        .buttonStyle(.bordered)
                        .disabled(isFindingActionInFlight)
                }
            }
        }
        .padding(.top, VLSpacing.xs)
    }

    /// docs/VOICE_LEDGER_HANDOFF.md D4: a `.submitted`/`.unknown` journal
    /// entry blocks further writes to this exact purchase+line until a
    /// resolution probe settles it — this is that block, made visible.
    private func pendingWriteSection(_ pending: WriteJournalEntry) -> some View {
        VStack(alignment: .leading, spacing: VLSpacing.xs) {
            Text(pending.state == .unknown ? "A previous write's outcome is unknown" : "A previous write is still in progress")
                .font(VLTypography.body())
                .foregroundStyle(.orange)
            Text(pending.state == .unknown
                 ? "The last attempt to apply this fix didn't get a confirmed answer from QBO — it may or may not have landed. Applying again is blocked until this is resolved, so the change can't be sent twice."
                 : "Recorded \(pending.submittedAt.formatted(date: .abbreviated, time: .shortened)) and still in progress.")
                .font(VLTypography.caption())
                .foregroundStyle(VLColor.textMuted)
            Button(isResolvingPendingWrite ? "Checking…" : "Resolve Pending Write") {
                onResolvePendingWrite()
            }
            .buttonStyle(.bordered)
            .disabled(isResolvingPendingWrite)
        }
        .padding(VLSpacing.xs)
        .background(VLColor.background)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.orange))
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
