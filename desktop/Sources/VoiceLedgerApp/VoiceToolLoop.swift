import Foundation
import Core
import Voice
import IntegrationsQuickBooks

/// Owner directive (2026-09-06): "let's move away from phrase matching and
/// move to understand me no matter how I say it." `VoiceIntentRouter`'s
/// exact-phrase lists can only ever cover phrasings someone already
/// noticed and added — this replaces the FALLBACK path (anything the
/// router doesn't match) with real tool-calling: the model decides which
/// of a fixed, deterministic set of tools to call from whatever was
/// actually said, and this app's own code executes it. The router itself
/// is untouched and still runs first as a zero-latency fast path for its
/// existing exact matches — nothing is now WORSE for a phrase that already
/// worked; everything that used to fall through to narrate-only now gets
/// real capability instead.
///
/// **The same safety property, a different mechanism** — see
/// `VoiceUIAction`'s own doc comment. The model never gets to just SAY it
/// did something; it has to emit a real, structured tool call, which
/// `execute(_:)` below is the ONLY thing that ever turns into an actual
/// `AppState` mutation. Free prose (`speech`) is narration, exactly as
/// it always was.
///
/// **Model choice**: `gemma4:12b` by default, not the faster `gemma4:e4b`
/// this app uses for plain narration — owner directive 2026-09-06 ("pick
/// whichever llm... if its gemma 12b which is slower but responds the best
/// then pick that one"). Tool selection accuracy matters more here than
/// latency: a wrong tool call is a wrong ACTION, not just a slower
/// sentence. Owner directive (2026-09-07): "connect Claude API... for the
/// tool loop" — `claude-haiku-4-5` is now a selectable alternative
/// (`VoiceToolLoopPreference`, set from the Connection page's AI
/// Connection card), for exactly the same reason: real, live-observed
/// tool-selection misses on Gemma this session.
extension VoiceEngine {
    static var toolLoopModel: String { VoiceToolLoopPreference.current.rawValue }
    private static let toolLoopContextKey = "voice-tool-loop"

    /// Called from `.unrecognized` instead of `reasoningFallback` — see
    /// `handle(_:)`'s own call site.
    func handleWithTools(rawText: String) async -> VoiceTurn {
        // Short non-question noise should never wake the local model. A
        // malformed two-word transcript such as "boom boom" previously
        // spent 30+ seconds in the tool loop even though it could not name
        // a page, fact, or action. All supported two-word commands are
        // resolved by VoiceIntentRouter before this fallback is reached.
        if VoiceIntentRouter.isLikelyShortNoise(rawText) {
            return VoiceTurn(speech: "I didn't recognize that as a command. Name the page, account, vendor, or finding you want.")
        }
        let tools = Self.toolDefinitions
        // Preserves what the old narration-only fallback already got
        // right: if a specific finding is currently open on screen, an
        // open-ended follow-up about it should stay grounded in that
        // finding's own real fields, not just the generic tool system
        // prompt — same `AskAIContext.compose(finding:)` boundary every
        // other per-finding surface in this app already uses.
        var context = Self.toolLoopSystemContext

        // CRITICAL: Always state the current page first, before any other context,
        // to override any stale page knowledge from previous turns
        let currentPageContext = appState.currentPageAskAIContext()
        context += "\n\n" + currentPageContext

        if let activeCompanyName = appState.companyInfo?.companyName {
            context += "\n\nThe ACTIVE client right now is \"\(activeCompanyName)\" — every tool already operates on this client. Mentioning this same name in a question (e.g. \"what's \(activeCompanyName)'s revenue\") is just identifying which client the question is about, NOT a request to switch — do not call switch_client unless the person is clearly asking to change to a DIFFERENT client (e.g. \"switch to X,\" \"the other client,\" \"pull up Y instead\")."
        }
        // A compact index, not the full narrative: the model only needs enough
        // to pick a tool and an ID (docs/MONEYPENNY_CONSISTENCY_DESIGN.md Part 2).
        let allOpenFindings = FindingTriage.sorted(appState.findings.filter { $0.status == .open })
        if !allOpenFindings.isEmpty {
            var lines = ["OPEN FINDINGS INDEX (\(allOpenFindings.count)) — id | amount | vendor | title:"]
            for finding in allOpenFindings.prefix(40) {
                let title = ClientText.polish(finding.title).split(separator: " ").prefix(8).joined(separator: " ")
                lines.append("\(finding.id.prefix(12)) | \(finding.dollarExposure.accountingDescription) | \(finding.vendorName ?? "-") | \(title)")
            }
            if allOpenFindings.count > 40 { lines.append("...and \(allOpenFindings.count - 40) more") }
            context += "\n" + lines.joined(separator: "\n")
        }
        // Stated last so it is the most salient: bare "this"/"it" means the
        // open finding, but a named amount/vendor/title overrides it.
        if let entityRef = self.context.currentEntity, entityRef.type == .finding, let finding = appState.finding(id: entityRef.id) {
            context += "\n\n🔴 THE PERSON HAS THIS FINDING OPEN ON SCREEN. \"This,\" \"it,\" and \"this one\" mean THIS finding. If they name a DIFFERENT amount, vendor, or title, that named finding wins — call open_findings with its ID.\n" + AskAIContext.compose(finding: finding)
        }

        let decision: (answer: String, toolCalls: [AIToolCall])
        do {
            decision = try await appState.askAIWithTools(
                question: rawText,
                context: context,
                history: recentHistory(),
                model: Self.toolLoopModel,
                tools: tools
            )
        } catch {
            return VoiceTurn(speech: "I couldn't get an answer from the local AI (\(String(describing: error))). Try again in a moment.")
        }

        guard !decision.toolCalls.isEmpty else {
            guard !decision.answer.isEmpty else {
                return VoiceTurn(speech: "I couldn't resolve that request to an app action or a verified answer. Try naming the page, account, vendor, or finding you want.")
            }
            let lowered = decision.answer.lowercased()
            let falseActionClaims = ["i opened ", "i've opened ", "i have opened ", "i navigated to ", "i've navigated to ", "i took you to ", "i've taken you to ", "i pulled up ", "i've pulled up "]
            if falseActionClaims.contains(where: lowered.contains) {
                return VoiceTurn(speech: "I didn't change the screen. Try the command again, or name the page you want.")
            }
            let guarded = NumberGuard.check(decision.answer, source: context)
            if guarded.replacedSentences > 0 { await recordTranscript(speaker: .assistant, text: "[guard replaced \(guarded.replacedSentences) sentence(s) with unverified figures]") }
            return VoiceTurn(speech: guarded.text)
        }
        guard !Task.isCancelled else { return VoiceTurn(speech: "") }

        var resultLines: [String] = []
        var uiAction: VoiceUIAction?
        for call in decision.toolCalls {
            let result = await execute(call)
            resultLines.append("\(call.name) → \(result.resultText)")
            if let action = result.uiAction { uiAction = action }
        }

        // Speak the actual tool result. A model rewrite can claim a different
        // action and used to delay navigation by a second inference request.
        let speech = resultLines.map { String($0.split(separator: "→", maxSplits: 1).last ?? "").trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
        return VoiceTurn(speech: ClientText.polish(speech), uiAction: uiAction)
    }
}
