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

@Suite("Insight card phrases (2026-10-02)")
struct InsightCardPhraseTests {
    func route(_ s: String) -> VoiceIntent { VoiceIntentRouter.match(text: s, context: .empty) }

    @Test("Chart and card phrases route; bare KPI questions still answer as numbers")
    func phrases() {
        #expect(route("revenue by month") == .chart(.revenueTrend))
        #expect(route("chart revenue") == .chart(.revenueTrend))
        #expect(route("net income trend") == .chart(.netIncomeTrend))
        #expect(route("receivables chart") == .chart(.receivables))
        #expect(route("payables aging") == .chart(.payables))
        #expect(route("will we run out of cash") == .cashOutlook)
        #expect(route("cash outlook") == .cashOutlook)
        #expect(route("what's our revenue") == .kpi(.revenue, .current))
        #expect(route("go to aged receivables") == .navigate(.agedReceivablesReport))
        #expect(route("cash flow forecast") == .navigate(.cashFlowForecast))
    }
}

@Suite("Charts & Cards page entries are real commands")
struct CardCatalogTests {
    @Test("Every clickable entry routes to a command (never to the AI model)")
    func allRoute() {
        for section in CardCatalog.sections {
            for item in section.items {
                let intent = VoiceIntentRouter.match(text: item.phrase, context: .empty)
                if case .unrecognized = intent { Issue.record("\(item.phrase) is not a command") }
            }
        }
        #expect(VoiceIntentRouter.match(text: CardCatalog.vendorPhrase("Hicks Hardware"), context: .empty) == .searchVendor("hicks hardware"))
        #expect(VoiceIntentRouter.match(text: CardCatalog.accountPhrase("Mastercard"), context: .empty) == .accountBalance("mastercard"))
    }

    @Test("'who owes us the most' and 'who do we owe the most' are instant commands")
    func topBalance() {
        #expect(VoiceIntentRouter.match(text: "which customer owes us the most", context: .empty) == .topBalance(receivables: true))
        #expect(VoiceIntentRouter.match(text: "Who owes us the most?", context: .empty) == .topBalance(receivables: true))
        #expect(VoiceIntentRouter.match(text: "who do we owe the most", context: .empty) == .topBalance(receivables: false))
    }

    @Test("'how many open findings' answers with the count, not just the page")
    func howMany() {
        for p in ["how many open findings", "how many findings", "how many issues"] {
            if case .findingsGroup = VoiceIntentRouter.match(text: p, context: .empty) {} else { Issue.record("\(p) -> \(VoiceIntentRouter.match(text: p, context: .empty))") }
        }
    }

    @Test("Owner test batch 3 (2026-10-02): plain-English questions route to instant commands")
    func batch3() {
        func r(_ p: String) -> VoiceIntent { VoiceIntentRouter.match(text: p, context: .empty) }
        #expect(r("how much did we make this month") == .kpi(.netIncome, .current))
        #expect(r("how much did we make last month") == .kpi(.netIncome, .priorMonth))
        #expect(r("are we profitable") == .kpi(.netIncome, .current))
        #expect(r("how much does freeman sporting goods owe us") == .customerOwes("freeman sporting goods"))
        #expect(r("what does video games by dan owe us") == .customerOwes("video games by dan"))
        #expect(r("show me the biggest expenses") == .chart(.expenseDrivers))
        #expect(r("what do we owe norton lumber") == .vendorOwed("norton lumber"))
        #expect(r("is there anything unusual with VL Spike Permian Supply") == .nameFindings("vl spike permian supply"))
        #expect(r("any issues with cool cars") == .nameFindings("cool cars"))
        var ctx = VoiceSessionContext.empty
        ctx.routineStep = 1
        ctx.pendingAction = VoicePendingAction(kind: .runCommand, summary: "x", commandText: "top vendors")
        #expect(VoiceIntentRouter.match(text: "stop", context: ctx) == .routineStop)
    }

    @Test("'show <trend> chart' phrasing is a command; 'show vendors' is still a page")
    func showTrend() {
        #expect(VoiceIntentRouter.match(text: "show net income trend", context: .empty) == .chart(.netIncomeTrend))
        #expect(VoiceIntentRouter.match(text: "pull up revenue by month", context: .empty) == .chart(.revenueTrend))
        #expect(VoiceIntentRouter.match(text: "show me the cash outlook", context: .empty) == .chart(.cashOutlook))
        if case .chart = VoiceIntentRouter.match(text: "show vendors", context: .empty) { Issue.record("show vendors became a chart") }
    }
}
