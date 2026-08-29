import Testing
@testable import Voice
import Core

@Suite("VoiceIntentRouter.match")
struct VoiceIntentRouterTests {
    // MARK: Navigation

    @Test("Matches a bare page name")
    func matchesBarePageName() {
        #expect(VoiceIntentRouter.match(text: "Cleanup Assessment", context: .empty) == .navigate(.cleanupAssessment))
    }

    @Test("Matches a page name with a natural filler prefix")
    func matchesPageNameWithFillerPrefix() {
        #expect(VoiceIntentRouter.match(text: "take me to the firm cockpit", context: .empty) == .navigate(.firmCockpit))
        #expect(VoiceIntentRouter.match(text: "go to cleanup assessment", context: .empty) == .navigate(.cleanupAssessment))
        #expect(VoiceIntentRouter.match(text: "show me the bank feed", context: .empty) == .navigate(.bankFeedCleanup))
    }

    @Test("Tolerates Whisper's real hyphenation quirk — 'clean-up assessment' still matches, live-verified against the real STT service")
    func tolerantOfHyphenation() {
        #expect(VoiceIntentRouter.match(text: "clean-up assessment", context: .empty) == .navigate(.cleanupAssessment))
    }

    @Test("Is case-insensitive and tolerates trailing punctuation")
    func caseInsensitiveAndPunctuationTolerant() {
        #expect(VoiceIntentRouter.match(text: "CLEANUP ASSESSMENT.", context: .empty) == .navigate(.cleanupAssessment))
        #expect(VoiceIntentRouter.match(text: "Firm Cockpit!", context: .empty) == .navigate(.firmCockpit))
    }

    @Test("An unrelated sentence that happens to contain a page name substring does not match")
    func doesNotSubstringMatch() {
        let result = VoiceIntentRouter.match(text: "what do you think about the cleanup assessment page design", context: .empty)
        if case .navigate = result {
            Issue.record("expected NOT to match navigation — this is a question about the page, not a command to go there")
        }
    }

    // MARK: Confirmation — only when a pending action actually exists

    @Test("A bare 'yes' with no pending action does NOT confirm anything")
    func yesWithNoPendingActionDoesNotConfirm() {
        let result = VoiceIntentRouter.match(text: "yes", context: .empty)
        if result == .confirmPending {
            Issue.record("must never confirm when nothing is pending — this is the exact 'yeah mid-conversation' bug the reference app found live")
        }
    }

    @Test("A bare 'yes' WITH a pending action confirms it")
    func yesWithPendingActionConfirms() {
        var ctx = VoiceSessionContext.empty
        ctx.pendingAction = VoicePendingAction(kind: .dismissFinding, findingID: "f1", summary: "dismiss this finding")
        #expect(VoiceIntentRouter.match(text: "yes", context: ctx) == .confirmPending)
    }

    @Test("Confirmation words with trailing text still match — a real reply has extra words")
    func confirmationToleratesTrailingWords() {
        var ctx = VoiceSessionContext.empty
        ctx.pendingAction = VoicePendingAction(kind: .dismissFinding, findingID: "f1", summary: "dismiss this finding")
        #expect(VoiceIntentRouter.match(text: "yes please go ahead", context: ctx) == .confirmPending)
        #expect(VoiceIntentRouter.match(text: "no, cancel that", context: ctx) == .rejectPending)
    }

    @Test("Reject words with a pending action reject it")
    func rejectWithPendingActionRejects() {
        var ctx = VoiceSessionContext.empty
        ctx.pendingAction = VoicePendingAction(kind: .completeChecklistItem, checklistItemID: "x", summary: "mark this complete")
        #expect(VoiceIntentRouter.match(text: "no", context: ctx) == .rejectPending)
    }

    // MARK: Review queue commands — only meaningful with a real queue

    @Test("'Next' with no review queue does not match queueNext")
    func nextWithNoQueueDoesNotMatch() {
        let result = VoiceIntentRouter.match(text: "next", context: .empty)
        #expect(result != .queueNext)
    }

    @Test("'Next' with a real review queue matches queueNext")
    func nextWithQueueMatches() {
        var ctx = VoiceSessionContext.empty
        ctx.reviewQueue = ["f1", "f2"]
        #expect(VoiceIntentRouter.match(text: "next", context: ctx) == .queueNext)
        #expect(VoiceIntentRouter.match(text: "skip it", context: ctx) == .queueNext)
    }

    @Test("'What's left' with no queue does not match queueStatus")
    func queueStatusRequiresQueue() {
        let result = VoiceIntentRouter.match(text: "what's left", context: .empty)
        #expect(result != .queueStatus)
    }

    // MARK: Other deterministic intents

    @Test("'Go back' matches regardless of context")
    func goBackMatches() {
        #expect(VoiceIntentRouter.match(text: "go back", context: .empty) == .goBack)
    }

    @Test("'That one' only matches when there's a last-viewed entity")
    func thatOneRequiresLastViewedEntity() {
        #expect(VoiceIntentRouter.match(text: "that one", context: .empty) != .openLastEntity)
        var ctx = VoiceSessionContext.empty
        ctx.lastViewedEntities = [VoiceEntityRef(type: .finding, id: "f1")]
        #expect(VoiceIntentRouter.match(text: "that one", context: ctx) == .openLastEntity)
    }

    @Test("'Why' matches explainCurrent")
    func whyMatchesExplainCurrent() {
        #expect(VoiceIntentRouter.match(text: "why", context: .empty) == .explainCurrent)
        #expect(VoiceIntentRouter.match(text: "why is this flagged?", context: .empty) == .explainCurrent)
    }

    @Test("An open-ended question falls through to unrecognized, carrying the original text")
    func unmatchedFallsThroughWithOriginalText() {
        let result = VoiceIntentRouter.match(text: "Why did expenses jump this month compared to last?", context: .empty)
        #expect(result == .unrecognized("Why did expenses jump this month compared to last?"))
    }

    @Test("Empty or whitespace-only input is unrecognized, not a crash")
    func emptyInputIsUnrecognized() {
        #expect(VoiceIntentRouter.match(text: "", context: .empty) == .unrecognized(""))
        #expect(VoiceIntentRouter.match(text: "   ", context: .empty) == .unrecognized("   "))
    }
}
