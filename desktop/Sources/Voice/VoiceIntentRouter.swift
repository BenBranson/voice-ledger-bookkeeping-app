import Foundation
import Core

/// The deterministic fast path — ported from a design already battle-
/// tested in a separate app (`server/voiceRouter.js`'s `matchDirectIntent`),
/// where it was built specifically to avoid real, VERIFIED failure modes
/// of trusting an LLM with obvious commands: a model claiming "I've shown
/// you a chart" or "I've staged that correction" in plain prose with ZERO
/// tool call that turn — a hallucination of a completed action, not just
/// an invented number. Every branch here is unambiguous by construction;
/// anything not matched falls through to the reasoning path
/// (`AskAIContext` + the existing OpenAI Ask AI route) rather than being
/// guessed at.
///
/// **Confirmation only ever fires when something is genuinely pending** —
/// ported directly from the same real bug the reference app found live: a
/// bare "yeah" mid-conversation must never be misread as approving a
/// change nobody actually proposed. `context.pendingAction == nil` means
/// confirm/reject words are ordinary conversation, not a yes/no answer.
public enum VoiceIntentRouter {
    /// Prevents short ASR noise from entering the slow reasoning path. Short
    /// questions remain eligible because they can carry a real request.
    public static func isLikelyShortNoise(_ text: String) -> Bool {
        let words = text.split { $0.isWhitespace || $0.isPunctuation }
        guard words.count <= 2 else { return false }
        // A recognized page name is a command, however short.
        if matchDestination(normalize(text)) != nil { return false }
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let questionLead = ["why", "what", "how", "where", "when", "which", "who", "can", "could", "would", "tell", "give", "find", "search"]
        return !questionLead.contains { lower.hasPrefix($0 + " ") || lower == $0 }
    }

    /// Owner-reported gap (2026-09-06): "pull up X" / "bring up X" — the
    /// user's own words for asking to navigate somewhere — were only ever
    /// handled for a bare "pull it up"/"bring that up" referring to
    /// something ALREADY on screen (`openLastEntityPhrases` below), never
    /// for "pull up the cleanup assessment" naming a real destination.
    /// That phrase fell through every check here to the slow AI reasoning
    /// fallback, which only speaks — it never navigates — so the person's
    /// actual request (see the page) silently never happened.
    private static let navigationPrefixes = CommandGrammar.openVerbs.map { $0 + " " }

    /// Each destination's recognized phrases, already normalized (lowercase,
    /// no punctuation). Deliberately a plain alias SET, not a regex engine —
    /// this app's real page names are short enough that exact-phrase
    /// matching (after stripping a known filler prefix) is both simpler and
    /// safer than pattern cleverness; a false-positive match here is worse
    /// than falling through to the reasoning path.
    private static let destinationAliases: [(VoiceDestination, Set<String>)] = [
        (.dashboard, ["dashboard", "home", "client dashboard"]),
        (.findingsList, ["findings", "findings list", "list"]),
        (.cleanupAssessment, ["cleanup assessment", "cleanup", "clean up assessment", "clean up"]),
        (.balanceSheetIntegrity, ["balance sheet integrity"]),
        (.bankFeedCleanup, ["bank feed cleanup", "bank feed", "bank", "check bank feeds", "bank feeds"]),
        (.chartOfAccountsCleanup, ["chart of accounts cleanup", "chart of accounts"]),
        (.batchFixes, ["batch fixes", "batch fix"]),
        (.salesTaxReview, ["sales tax review", "sales tax"]),
        (.taxes, ["taxes", "tax"]),
        (.firmCockpit, ["firm cockpit", "cockpit"]),
        (.monthEndClose, [
            "month end close", "month end review", "month end", "monthly close",
            "end of month close", "close out the month", "close the month",
            "close out the books", "close the books", "close books", "month close", "wrap up the books",
            "wrap up the month", "month end checklist",
            "end clothes" // Clipped ASR phrase covered by the navigation regression suite.
        ]),
        (.activityLog, ["activity log", "activity and correction log", "correction log"]),
        (.closePackage, ["close package"]),
        (.clientMemory, ["client memory"]),
        (.balanceSheetReport, ["balance sheet", "balance sheet report"]),
        (.profitAndLossReport, ["profit and loss", "profit and loss report", "p and l", "p and l report"]),
        (.cashFlowReport, ["cash flow", "cash flow report"]),
        (.trialBalanceReport, ["trial balance", "trial balance report"]),
        (.agedReceivablesReport, ["aged receivables", "receivables", "accounts receivable"]),
        (.agedPayablesReport, ["aged payables", "payables", "accounts payable"]),
        (.generalLedgerReport, ["general ledger"]),
        (.aiConversations, ["ai conversations", "conversations", "conversation history", "ai history"]),
        (.cashFlowForecast, ["cash flow forecast", "forecast"]),
        (.recurringVendors, ["recurring vendors", "recurring"]),
        (.amountSearch, ["search by amount", "amount search", "search"]),
        (.clientDiagnostics, ["client diagnostics", "diagnostics"]),
        (.pricingCalculator, ["pricing calculator", "pricing"]),
        (.intakeQuestions, ["intake questions", "intake"]),
        (.complianceCalendar, ["compliance calendar", "compliance", "deadlines", "due dates", "filing calendar", "tax calendar", "calendar", "sales by state", "economic nexus", "nexus"]),
        (.scopeRequests, ["scope requests", "out of scope", "out of scope requests", "scope log", "add ons", "upsells"]),
        (.chartsGallery, ["charts and cards", "charts & cards", "chart gallery", "all charts", "all cards", "cards", "card list", "chart list", "list of charts"]),
        (.industrySetup, ["industry setup", "industry", "industry template", "chart of accounts template"])
    ]

    private static let confirmWords = ["yes", "yeah", "yep", "yup", "confirm", "do it", "go ahead", "sounds good", "sure", "okay", "ok"]
    private static let rejectWords = ["no", "nah", "nope", "cancel", "never mind", "nevermind", "stop", "don't", "dont"]
    private static let goBackPhrases: Set<String> = ["go back", "back up", "previous page", "previous", "go back a page"]
    private static let nextPhrases: Set<String> = ["next", "next one", "skip", "skip it", "skip this", "skip that", "skip this one", "skip that one", "skip this for now", "move on"]
    private static let openLastEntityPhrases: Set<String> = [
        "that one", "open that", "show me that", "open it", "show that", "show it",
        "pull it up", "pull that up", "bring that up", "bring it up"
    ]
    private static let recapPhrases: Set<String> = ["what were we doing", "what was i doing", "where were we"]
    private static let queueStatusPhrases: Set<String> = [
        "what's left", "whats left", "what is left", "what have we fixed", "what have we fixed so far",
        "what's our progress", "whats our progress", "how many are left", "how much is left"
    ]
    private static let startReviewPhrases: Set<String> = [
        "review this client", "start my review", "start review", "review my findings", "check these books",
        "start month end review", "start the review", "begin review", "start daily review"
    ]
    /// "Show me anomalies" et al. route to the SAME `.startReviewQueue`
    /// intent `startReviewPhrases` already produces — a bare list with no
    /// way back in was the actual real complaint (2026-08-29 live test):
    /// asking about anomalies got a narrated list from the reasoning
    /// fallback with nothing to say "next" to, because nothing had
    /// actually been opened. Routing here instead means the first item is
    /// genuinely opened (`.openFinding`) and pushed into
    /// `lastViewedEntities`, so "pull it up"/"next" have something real to
    /// act on immediately afterward.
    private static let anomalyPhrases: Set<String> = [
        "anomalies", "anomaly", "show anomalies", "show me anomalies", "show me the anomalies",
        "find anomalies", "find the anomalies", "review anomalies", "check for anomalies",
        "what needs my attention", "what needs attention"
    ]
    private static let recheckPhrases: Set<String> = [
        "check again", "recheck", "check for anomalies again", "check for new anomalies",
        "any new anomalies", "scan again", "run the checks again", "run the check again",
        "are we done", "audit summary"
    ]
    private static let explainPhrases: Set<String> = [
        "why", "why is this flagged", "why is this a problem", "why is this here", "explain this", "explain that",
        "what's unusual about this", "whats unusual about this", "show me the evidence", "what's wrong with this",
        "whats wrong with this", "what should i do", "what would you do", "what do you recommend",
        "how should i fix this", "what's your recommendation", "whats your recommendation",
        "what caused this", "what are my options", "fix it", "let's fix it", "lets fix it", "how do i fix it"
    ]
    /// "Hi"/"status update" — real, requested phrasing (2026-08-29) for a
    /// deterministic greeting that actually says something (open-findings
    /// count + total exposure) instead of falling through to the reasoning
    /// path with nothing useful to answer.
    private static let statusOverviewPhrases: Set<String> = [
        "hi", "hello", "hey", "status update", "give me a status update", "how are things", "what's the status"
    ]

    private static let openInQuickBooksPhrases: Set<String> = [
        "open it in quickbooks", "open in quickbooks", "open this in quickbooks", "open that in quickbooks", "show me in quickbooks",
        "show it in quickbooks", "open quickbooks", "take me to quickbooks", "pull it up in quickbooks", "fix it in quickbooks",
        "open in qbo", "open it in qbo", "open the record", "open the transaction", "go to quickbooks", "open it in quick books",
        "open in quick books", "open quick books", "take me to quick books"
    ]
    private static let deadlinePhrases: Set<String> = [
        "what's due", "whats due", "what is due", "what's coming due", "whats coming due", "what's due next", "whats due next", "any deadlines",
        "what deadlines are coming up", "upcoming deadlines", "next deadline", "what's the next deadline", "whats the next deadline",
        "when is sales tax due", "when is the sales tax due", "what filings are due", "what's due this month", "whats due this month"
    ]
    private static let cashOutlookPhrases: Set<String> = [
        "cash outlook", "cash forecast", "13 week forecast", "thirteen week forecast", "13 week cash forecast", "thirteen week cash forecast",
        "will we run out of cash", "are we going to run out of cash", "will we run out of money", "are we going to run out of money",
        "what's our cash outlook", "whats our cash outlook", "how does cash look", "how is cash looking", "cash projection", "project our cash"
    ]
    private static let newAccountPhrases: Set<String> = [
        "any new accounts", "are there any new accounts", "new accounts", "did they open any new accounts", "did the client open any new accounts",
        "any new bank accounts", "any new credit cards", "new bank accounts", "new credit cards"
    ]
    private static let checkFixedPhrases: Set<String> = [
        "is it fixed", "is that fixed", "is this fixed", "did that fix it", "did it fix it", "did that work", "check it", "check this one",
        "check that one", "is it cleared", "did it clear", "did that clear", "i fixed it", "i fixed that", "it's fixed", "its fixed",
        "fixed it", "i'm done with that one", "im done with that one", "done with this one", "that's fixed", "thats fixed", "all fixed", "is it clean"
    ]

    /// Every phrase the app knows, for "did you mean". Each is a real
    /// command (the suggestion is verified to route before it is offered).
    static var knownPhrases: [String] {
        var all: [String] = []
        for (_, aliases) in destinationAliases { all += aliases.map { "go to \($0)" } + Array(aliases) }
        for d in VoiceDestination.allCases { all += spokenForms(of: d.menuTitle).map { "go to \($0)" } }
        all += Array(goBackPhrases) + Array(nextPhrases) + Array(recapPhrases) + Array(startReviewPhrases) + Array(anomalyPhrases)
            + Array(recheckPhrases) + Array(explainPhrases) + Array(openInQuickBooksPhrases) + Array(checkFixedPhrases)
            + Array(deadlinePhrases) + Array(newAccountPhrases) + Array(cashOutlookPhrases)
        all += CommandGrammar.knownPhrases
        return all
    }

    /// The closest known command to something that wasn't recognized, when
    /// it is close enough to be a mishearing ("vendor by spin" → "vendor by
    /// spend"). Nil when nothing is close, so real questions still reach the AI.
    public static func suggestion(for text: String) -> String? {
        let heard = CommandGrammar.normalize(text)
        guard heard.count >= 5 else { return nil }
        var best: (phrase: String, distance: Int)?
        for phrase in Set(knownPhrases) where abs(phrase.count - heard.count) <= max(3, heard.count / 4) {
            let d = editDistance(heard, phrase)
            if best == nil || d < best!.distance { best = (phrase, d) }
        }
        guard let best, best.distance > 0, Double(best.distance) <= max(2, Double(heard.count) * 0.2) else { return nil }
        guard case .unrecognized = match(text: best.phrase, context: .empty) else { return best.phrase }
        return nil
    }

    /// True when the AI's reply ends by offering to do something.
    public static func isOffer(_ answer: String) -> Bool {
        let lowered = answer.lowercased()
        return ["if you want", "if you'd like", "would you like", "do you want", "want me to", "should i ", "shall i ", "i can pull", "i can open", "i can show"].contains(where: lowered.contains)
    }

    /// A command the AI's prose OFFERED to run ("I can pull up the vendor
    /// spend chart if you want"), so a "yes" can run it. Only offers count.
    public static func offeredCommand(in answer: String) -> String? {
        let lowered = answer.lowercased()
        let offerWords = ["if you want", "if you'd like", "would you like", "do you want", "want me to", "should i", "shall i", "i can "]
        guard offerWords.contains(where: lowered.contains) else { return nil }
        // A quoted phrase first: "did you mean “vendor by spend”".
        let quoted = answer.matches(of: /[“"']([^”"']{3,60})[”"']/).map { String($0.output.1) }
        for q in quoted { if case .unrecognized = match(text: q, context: .empty) { continue } else { return q } }
        let normalizedAnswer = CommandGrammar.normalize(lowered)
        for phrase in Set(knownPhrases).sorted(by: { $0.count > $1.count }) where phrase.count >= 8 && normalizedAnswer.contains(phrase) {
            if case .unrecognized = match(text: phrase, context: .empty) { continue }
            return phrase
        }
        return nil
    }

    /// A bare "yes"/"no" said when nothing is waiting on an answer.
    public static func isBareYesOrNo(_ text: String) -> Bool {
        let t = normalize(text)
        return confirmWords.contains(t) || rejectWords.contains(t)
    }

    public static func isBareYes(_ text: String) -> Bool { confirmWords.contains(normalize(text)) }

    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }

    public static func match(text: String, context: VoiceSessionContext) -> VoiceIntent {
        let normalized = normalize(correctCommonRecognition(text))
        guard !normalized.isEmpty else { return .unrecognized(text) }

        // "stop" while the month-end walkthrough runs ends the walkthrough, even when an
        // offer is also pending (owner test 2026-10-02: it answered "Okay, I won't do that").
        if context.routineStep != nil, MonthEndRoutine.command(for: text) == .stop { return .routineStop }

        if context.pendingAction != nil {
            if matchesLeading(normalized, any: confirmWords) { return .confirmPending }
            if matchesLeading(normalized, any: rejectWords) { return .rejectPending }
        }

        if let candidates = context.candidateFindingIDs, !candidates.isEmpty {
            let selection = CommandGrammar.strip(CommandGrammar.strip(CommandGrammar.normalize(text), CommandGrammar.openVerbs), CommandGrammar.articles)
            let ordinals = ["first", "second", "third", "fourth"]
            for (index, ordinal) in ordinals.enumerated() where index < candidates.count {
                if [ordinal, ordinal + " one", "number \(index + 1)", "\(index + 1)"].contains(selection) {
                    return .chooseFinding(index)
                }
            }
        }

        // The month-end walkthrough: its control words only mean something while it's running.
        if MonthEndRoutine.isStart(text) { return .startRoutine }
        if context.routineStep != nil, let command = MonthEndRoutine.command(for: text) {
            switch command {
            case .advance: return .routineAdvance
            case .repeat: return .routineRepeat
            case .previous: return .routinePrevious
            case .stop: return .routineStop
            case .where: return .routineWhere
            }
        }

        // "review September", "switch to August 2026": change the reviewed month. Checked before
        // page navigation; it only fires when the rest of the phrase is a month name.
        for lead in ["review ", "switch to ", "go to ", "look at ", "open ", "change the month to ", "switch the month to ", "change month to ", "let's do ", "lets do ", "work on "]
            where normalized.hasPrefix(lead) {
            let rest = CommandGrammar.strip(String(normalized.dropFirst(lead.count)), ["the month of", "the", "month of"])
            if let p = ReviewPeriod.spoken(rest, today: AccountingDate(date: Date())) { return .reviewMonth(p) }
        }

        if ["do the numbers tie", "do the numbers tie out", "does everything tie", "does everything tie out", "do the books tie", "check the math", "check the numbers",
            "tie out", "run the tie out", "run a tie out", "are the numbers right", "is the math right", "are the numbers correct", "verify the numbers",
            "do the numbers add up", "does it all add up", "numbers tie", "tie out the numbers"].contains(normalized) { return .tieOut }

        // "how many open findings / issues" wants the count spoken, not just the page.
        if normalized.hasPrefix("how many "), ["finding", "issue", "problem", "open item", "exception"].contains(where: { normalized.contains($0) }) {
            return .findingsGroup(.allOpen)
        }

        if let destination = matchDestination(normalized) {
            return .navigate(destination)
        }

        // Whisper and on-device recognition sometimes include the same short
        // page command more than once, or prepend a clipped word from the
        // previous utterance (e.g. "Close. Go to month and close. Month and
        // close."). Check punctuation-delimited command fragments so a clear
        // navigation phrase still takes the deterministic fast path instead
        // of falling through to a slow reasoning response that cannot navigate.
        for fragment in text.split(whereSeparator: { ".!?;\n".contains($0) }) {
            let candidate = normalize(correctCommonRecognition(String(fragment)))
            if let destination = matchDestination(candidate) {
                return .navigate(destination)
            }
        }

        if goBackPhrases.contains(normalized) { return .goBack }
        if statusOverviewPhrases.contains(normalized) { return .statusOverview }
        if nextPhrases.contains(normalized), !context.reviewQueue.isEmpty { return .queueNext }
        if openLastEntityPhrases.contains(normalized), context.lastViewedEntities.first != nil { return .openLastEntity }
        if recapPhrases.contains(normalized) { return .recapContext }
        if queueStatusPhrases.contains(normalized), !context.reviewQueue.isEmpty { return .queueStatus }
        if recheckPhrases.contains(normalized) { return .recheckAnomalies }
        if startReviewPhrases.contains(normalized) || anomalyPhrases.contains(normalized) { return .startReviewQueue }
        if explainPhrases.contains(normalized) { return .explainCurrent }
        if openInQuickBooksPhrases.contains(normalized) { return .openInQuickBooks }
        if checkFixedPhrases.contains(normalized) { return .checkCurrentFixed }
        if deadlinePhrases.contains(normalized) { return .upcomingDeadlines }
        if newAccountPhrases.contains(normalized) { return .newAccounts }
        if cashOutlookPhrases.contains(normalized) { return .cashOutlook }

        // The command grammar (2026-09-30) takes everything that used to fall
        // through to the model: finding groups, amounts, balances, vendors,
        // KPIs, freshness, charts. It runs last so no existing phrase changes.
        if let parsed = CommandGrammar.parse(text) { return parsed }

        return .unrecognized(text)
    }

    /// Lowercase, trailing punctuation stripped, hyphens flattened to
    /// spaces (Whisper's `base.en` model, live-verified 2026-08-29,
    /// transcribes "Cleanup" as "clean-up" — a real transcription quirk,
    /// not a hypothetical one, discovered testing the actual STT/TTS
    /// round-trip against this exact page name before this router was
    /// even written), whitespace collapsed, and a whole-phrase repeat
    /// collapsed to one copy.
    ///
    /// That last step is for a second real, live-observed transcription
    /// artifact (2026-08-29): saying "start review" once was transcribed
    /// as "start review start review" — the whole phrase duplicated, not
    /// stuttered mid-word. An exact-match Set lookup treats that as a
    /// completely different string, so it fell through to the slow
    /// reasoning fallback instead of the instant deterministic path —
    /// exactly the kind of thing that makes voice feel sluggish and
    /// "talks in circles" instead of sharp. `"a b a b"` -> `"a b"`;
    /// left alone if the two halves genuinely differ, so this never
    /// silently changes what a real two-part sentence meant.
    static func normalize(_ text: String) -> String {
        var t = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = t.last, ".!?,".contains(last) { t.removeLast() }
        t = t.replacingOccurrences(of: "-", with: " ")
        t = t.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")

        let words = t.split(separator: " ")
        if words.count >= 2, words.count % 2 == 0 {
            let half = words.count / 2
            if words[..<half].elementsEqual(words[half...]) {
                t = words[..<half].joined(separator: " ")
            }
        }
        return t
    }

    /// Every menu title as people say it: "profit and loss", "month end close",
    /// "scope and period lock", "p and l" (from the hand list), plus "the …".
    static func spokenForms(of title: String) -> Set<String> {
        let base = title.lowercased().replacingOccurrences(of: "&", with: "and").replacingOccurrences(of: "-", with: " ")
            .components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
        var forms: Set<String> = [base, base + " page", base + " section", base + " screen", base + " report", base + " tab"]
        forms.insert(base.replacingOccurrences(of: " and ", with: " "))
        return forms
    }

    private static func correctCommonRecognition(_ text: String) -> String {
        var value = text.lowercased()
        // Whisper repeatedly rendered the spoken “month-end close” as
        // “month and clothes” / “month end clothes”; resolve that known
        // phonetic error before it reaches the slower model fallback.
        for phrase in [
            "month and clothes", "month end clothes", "month in clothes",
            "month and cloths", "month and close", "month in close", "month end to close",
            "month end two close", "month send close", "month sent close", "month and to close"
        ] {
            value = value.replacingOccurrences(of: phrase, with: "month end close")
        }
        return value
    }

    private static func matchDestination(_ normalized: String) -> VoiceDestination? {
        var stripped = CommandGrammar.normalize(normalized)
        for prefix in navigationPrefixes.sorted(by: { $0.count > $1.count }) where stripped.hasPrefix(prefix) {
            stripped = String(stripped.dropFirst(prefix.count))
            break
        }
        if let destination = exactDestination(stripped) { return destination }

        // Recognition can prepend the page name it heard before the actual
        // navigation wording ("month end close take me to month end close").
        // A named navigation verb is an explicit request, so inspect only the
        // words after that verb and still require an exact destination alias.
        for prefix in navigationPrefixes.sorted(by: { $0.count > $1.count }) {
            // `navigationPrefixes` already includes its trailing space.
            guard let range = stripped.range(of: prefix) else { continue }
            let requestedPage = String(stripped[range.upperBound...])
            if let destination = exactDestination(requestedPage) { return destination }
            if resemblesMonthEndClose(requestedPage) { return .monthEndClose }
        }
        // Short bare page names are common spoken commands, and their three
        // words remain highly distinctive even when ASR substitutes a
        // near-homophone ("month send clothes"). Don't fuzzy-match arbitrary
        // long questions or unrelated menu destinations.
        if resemblesMonthEndClose(stripped) { return .monthEndClose }
        return nil
    }

    private static func resemblesMonthEndClose(_ phrase: String) -> Bool {
        let words = phrase.split(separator: " ").map(String.init)
        guard words.count == 3, words[0] == "month" else { return false }
        return editDistance(words[1], "end") <= 2 && editDistance(words[2], "close") <= 3
    }

    private static func exactDestination(_ phrase: String) -> VoiceDestination? {
        var value = phrase
        for article in ["the ", "my ", "our "] where value.hasPrefix(article) {
            value = String(value.dropFirst(article.count))
            break
        }
        for (destination, aliases) in destinationAliases where aliases.contains(value) {
            return destination
        }
        for destination in VoiceDestination.allCases where spokenForms(of: destination.menuTitle).contains(value) {
            return destination
        }
        return nil
    }

    /// True/false at the start of the sentence, not end-anchored — a real
    /// reply has trailing words ("yes please go ahead", "no, cancel that").
    /// Only ever tested when `context.pendingAction != nil`, so the space
    /// of "reasonable replies to a yes/no prompt" is already constrained;
    /// this never affects ordinary conversation.
    private static func matchesLeading(_ text: String, any words: [String]) -> Bool {
        words.contains { text == $0 || text.hasPrefix($0 + " ") || text.hasPrefix($0 + ",") }
    }
}
