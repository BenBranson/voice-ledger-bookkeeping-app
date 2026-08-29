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
    private static let navigationPrefixes = [
        "go to the ", "go to ", "open the ", "open ", "show me the ", "show the ",
        "show me ", "take me to the ", "take me to ", "navigate to the ", "navigate to "
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
        (.bankFeedCleanup, ["bank feed cleanup", "bank feed", "bank"]),
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
    private static let nextPhrases: Set<String> = ["next", "next one", "skip", "skip it", "skip this", "skip that", "skip this one", "skip that one", "move on"]
    private static let openLastEntityPhrases: Set<String> = ["that one", "open that", "show me that", "open it", "show that", "show it"]
    private static let recapPhrases: Set<String> = ["what were we doing", "what was i doing", "where were we"]
    private static let queueStatusPhrases: Set<String> = [
        "what's left", "whats left", "what is left", "what have we fixed", "what have we fixed so far",
        "what's our progress", "whats our progress", "how many are left", "how much is left"
    ]
    private static let startReviewPhrases: Set<String> = [
        "review this client", "start my review", "start review", "review my findings", "check these books",
        "start month end review", "start the review", "begin review", "start daily review"
    ]
    private static let explainPhrases: Set<String> = [
        "why", "why is this flagged", "why is this a problem", "why is this here", "explain this", "explain that",
        "what's unusual about this", "whats unusual about this", "show me the evidence", "what's wrong with this",
        "whats wrong with this"
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
        if nextPhrases.contains(normalized), !context.reviewQueue.isEmpty { return .queueNext }
        if openLastEntityPhrases.contains(normalized), context.lastViewedEntities.first != nil { return .openLastEntity }
        if recapPhrases.contains(normalized) { return .recapContext }
        if queueStatusPhrases.contains(normalized), !context.reviewQueue.isEmpty { return .queueStatus }
        if startReviewPhrases.contains(normalized) { return .startReviewQueue }
        if explainPhrases.contains(normalized) { return .explainCurrent }

        return .unrecognized(text)
    }

    /// Lowercase, trailing punctuation stripped, hyphens flattened to
    /// spaces (Whisper's `base.en` model, live-verified 2026-08-29,
    /// transcribes "Cleanup" as "clean-up" — a real transcription quirk,
    /// not a hypothetical one, discovered testing the actual STT/TTS
    /// round-trip against this exact page name before this router was
    /// even written), whitespace collapsed.
    static func normalize(_ text: String) -> String {
        var t = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = t.last, ".!?,".contains(last) { t.removeLast() }
        t = t.replacingOccurrences(of: "-", with: " ")
        t = t.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
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
