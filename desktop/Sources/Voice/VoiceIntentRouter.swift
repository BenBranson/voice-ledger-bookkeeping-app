import Foundation

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
    /// Owner-reported gap (2026-09-06): "pull up X" / "bring up X" — the
    /// user's own words for asking to navigate somewhere — were only ever
    /// handled for a bare "pull it up"/"bring that up" referring to
    /// something ALREADY on screen (`openLastEntityPhrases` below), never
    /// for "pull up the cleanup assessment" naming a real destination.
    /// That phrase fell through every check here to the slow AI reasoning
    /// fallback, which only speaks — it never navigates — so the person's
    /// actual request (see the page) silently never happened.
    private static let navigationPrefixes = [
        "go to the ", "go to ", "open the ", "open ", "show me the ", "show the ",
        "show me ", "take me to the ", "take me to ", "navigate to the ", "navigate to ",
        "pull up the ", "pull up ", "bring up the ", "bring up "
    ]

    /// Each destination's recognized phrases, already normalized (lowercase,
    /// no punctuation). Deliberately a plain alias SET, not a regex engine —
    /// this app's real page names are short enough that exact-phrase
    /// matching (after stripping a known filler prefix) is both simpler and
    /// safer than pattern cleverness; a false-positive match here is worse
    /// than falling through to the reasoning path.
    private static let destinationAliases: [(VoiceDestination, Set<String>)] = [
        (.findingsList, ["dashboard", "findings", "findings list", "home", "list"]),
        (.cleanupAssessment, ["cleanup assessment", "cleanup", "clean up assessment", "clean up"]),
        (.balanceSheetIntegrity, ["balance sheet integrity"]),
        (.bankFeedCleanup, ["bank feed cleanup", "bank feed", "bank", "check bank feeds", "bank feeds"]),
        (.chartOfAccountsCleanup, ["chart of accounts cleanup", "chart of accounts"]),
        (.batchFixes, ["batch fixes", "batch fix"]),
        (.salesTaxReview, ["sales tax review", "sales tax"]),
        (.taxes, ["taxes", "tax"]),
        (.firmCockpit, ["firm cockpit", "cockpit"]),
        (.monthEndClose, ["month end close", "month end review", "month end"]),
        (.activityLog, ["activity log", "activity and correction log", "correction log"]),
        (.closePackage, ["close package"]),
        (.clientMemory, ["client memory"]),
        (.balanceSheetReport, ["balance sheet", "balance sheet report"]),
        (.profitAndLossReport, ["profit and loss", "profit and loss report", "p and l", "p and l report"]),
        (.cashFlowReport, ["cash flow", "cash flow report"]),
        (.trialBalanceReport, ["trial balance", "trial balance report"]),
        (.agedReceivablesReport, ["aged receivables", "receivables", "accounts receivable"]),
        (.agedPayablesReport, ["aged payables", "payables", "accounts payable"]),
        (.generalLedgerReport, ["general ledger"])
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

    public static func match(text: String, context: VoiceSessionContext) -> VoiceIntent {
        let normalized = normalize(text)
        guard !normalized.isEmpty else { return .unrecognized(text) }

        if context.pendingAction != nil {
            if matchesLeading(normalized, any: confirmWords) { return .confirmPending }
            if matchesLeading(normalized, any: rejectWords) { return .rejectPending }
        }

        if let destination = matchDestination(normalized) {
            return .navigate(destination)
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

    private static func matchDestination(_ normalized: String) -> VoiceDestination? {
        var stripped = normalized
        for prefix in navigationPrefixes where stripped.hasPrefix(prefix) {
            stripped = String(stripped.dropFirst(prefix.count))
            break
        }
        for (destination, aliases) in destinationAliases where aliases.contains(stripped) {
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
