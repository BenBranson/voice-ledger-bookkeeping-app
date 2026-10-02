import Testing
@testable import Voice

@Suite("Did-you-mean suggestions and remembered offers (owner test 2026-10-02)")
struct VoiceSuggestionTests {
    @Test("Near-misses of real commands get a suggestion")
    func nearMisses() {
        #expect(VoiceIntentRouter.suggestion(for: "vendor by spinned") != nil)
        #expect(VoiceIntentRouter.suggestion(for: "working capitol") == "working capital")
        #expect(VoiceIntentRouter.suggestion(for: "go to balance shit") != nil)
    }

    @Test("Real questions are left for the AI, not 'corrected'")
    func noFalseSuggestions() {
        #expect(VoiceIntentRouter.suggestion(for: "why did expenses jump this month compared to last") == nil)
        #expect(VoiceIntentRouter.suggestion(for: "summarize the month for the client") == nil)
        #expect(VoiceIntentRouter.suggestion(for: "hi") == nil)
    }

    @Test("An AI offer to run a command is captured; a plain answer is not")
    func offers() {
        #expect(VoiceIntentRouter.offeredCommand(in: "I think you said vendor by spend. I can pull up the chart if you want.") == "vendor by spend")
        #expect(VoiceIntentRouter.offeredCommand(in: "Would you like me to open “top vendors”?") == "top vendors")
        #expect(VoiceIntentRouter.offeredCommand(in: "Revenue rose because of more invoices in July.") == nil)
    }

    @Test("A yes with a pending suggestion confirms it; a bare yes answers instantly")
    func yes() {
        var context = VoiceSessionContext.empty
        #expect(VoiceIntentRouter.match(text: "yes", context: context) != .confirmPending)
        #expect(VoiceIntentRouter.isBareYesOrNo("yes"))
        context.pendingAction = VoicePendingAction(kind: .runCommand, summary: "top vendors", commandText: "top vendors")
        #expect(VoiceIntentRouter.match(text: "yeah", context: context) == .confirmPending)
        #expect(VoiceIntentRouter.match(text: "no", context: context) == .rejectPending)
    }

    @Test("Cleanup loop commands")
    func cleanupLoop() {
        #expect(VoiceIntentRouter.match(text: "open it in QuickBooks", context: .empty) == .openInQuickBooks)
        #expect(VoiceIntentRouter.match(text: "is it fixed", context: .empty) == .checkCurrentFixed)
        #expect(VoiceIntentRouter.match(text: "I fixed it", context: .empty) == .checkCurrentFixed)
    }
}

@Suite("Offers the model makes are remembered")
struct OfferMemoryTests {
    @Test("Offer wording is recognized, plain answers are not")
    func offerWording() {
        #expect(VoiceIntentRouter.isOffer("Do you want me to pull this up?"))
        #expect(VoiceIntentRouter.isOffer("I can pull up the chart if you want."))
        #expect(VoiceIntentRouter.isOffer("Would you like me to open that finding?"))
        #expect(!VoiceIntentRouter.isOffer("Revenue was higher because of three large invoices."))
    }

    @Test("Only a yes accepts; no, cancel and stop never do")
    func yesOnly() {
        #expect(VoiceIntentRouter.isBareYes("yes") && VoiceIntentRouter.isBareYes("Yeah.") && VoiceIntentRouter.isBareYes("sure"))
        #expect(!VoiceIntentRouter.isBareYes("no") && !VoiceIntentRouter.isBareYes("cancel") && !VoiceIntentRouter.isBareYes("stop"))
    }

    @Test("A pending offer is confirmed by yes")
    func pendingOffer() {
        var context = VoiceSessionContext.empty
        context.pendingAction = VoicePendingAction(kind: .acceptOffer, summary: "show me that", commandText: "Do you want me to pull this up?")
        #expect(VoiceIntentRouter.match(text: "yes", context: context) == .confirmPending)
    }
}

@Suite("Practice tools by voice (2026-10-02)")
struct PracticeToolsVoiceTests {
    func route(_ s: String) -> VoiceIntent { VoiceIntentRouter.match(text: s, context: .empty) }

    @Test("New pages open by name")
    func pages() {
        #expect(route("go to compliance calendar") == .navigate(.complianceCalendar))
        #expect(route("open scope requests") == .navigate(.scopeRequests))
        #expect(route("industry setup") == .navigate(.industrySetup))
        #expect(route("go to scope and period lock") == .navigate(.scopeAndPeriodLock))
    }

    @Test("Deadlines and new accounts are answered in code")
    func questions() {
        #expect(route("what's due") == .upcomingDeadlines)
        #expect(route("When is sales tax due?") == .upcomingDeadlines)
        #expect(route("any new accounts") == .newAccounts)
    }
}
