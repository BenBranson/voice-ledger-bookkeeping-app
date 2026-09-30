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
        let allOpenFindings = FindingTriage.sorted(appState.findings.filter { $0.status == .open })
        if !allOpenFindings.isEmpty {
            var lines = ["", "ALL OF THIS CLIENT'S OPEN FINDINGS (reference for questions about specific issues):"]
            for finding in allOpenFindings.prefix(50) {
                lines.append("- \(finding.title) (\(finding.severity.rawValue) severity, \(finding.dollarExposure.description)) [ID: \(finding.id)]")
            }
            if allOpenFindings.count > 50 {
                lines.append("...and \(allOpenFindings.count - 50) more not listed here")
            }
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
            // The model answered directly with no tool call — either a
            // genuinely out-of-scope question it correctly declined (per
            // this file's system prompt), or a clarifying question back
            // to the user (e.g. "show me a chart" with nothing to chart).
            // Either way: narration only, exactly like the old reasoning
            // fallback — no `uiAction` is possible on this path.
            return VoiceTurn(speech: decision.answer.isEmpty ? "I'm not sure how to help with that — could you say it a different way?" : decision.answer)
        }

        var resultLines: [String] = []
        var uiAction: VoiceUIAction?
        for call in decision.toolCalls {
            let result = await execute(call)
            resultLines.append("\(call.name) → \(result.resultText)")
            if let action = result.uiAction { uiAction = action }
        }

        // Fact tools already return a complete, exact answer (with its data
        // scope) from `ClientFacts` — the same one the pages show. Speak it
        // verbatim: a model rewrite can only introduce errors here (seen
        // 2026-09-30: it described a different finding than the one opened).
        // Navigation / open_findings / charts still get the model's narration.
        let factTools: Set<String> = ["search_transactions", "get_account_balance", "get_vendor_details", "get_report_summary", "get_financial_summary",
                                      "get_chart_of_accounts", "get_sync_status", "find_findings", "list_vendors_by_spend"]
        if decision.toolCalls.allSatisfy({ factTools.contains($0.name) }) {
            return VoiceTurn(speech: ClientText.polish(resultLines.map { String($0.split(separator: "→", maxSplits: 1).last ?? "").trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")), uiAction: uiAction)
        }

        // Narrate the tool result(s) — a second, tool-free call so the
        // spoken answer is natural prose grounded in what the tool(s)
        // actually returned, same "code computed it, the model explains
        // it" boundary as every other Ask AI surface in this app.
        let narrationContext = context + "\n\nTOOL RESULTS (real, already-computed data — narrate this, do not recompute or contradict it). Copy every dollar amount exactly as written, keeping the $ sign and any parentheses — ($3,293.02) means negative/overdrawn, never write it as -3,293.02. If a result's data-status sentence says the data is saved (cached) or not yet synced, say so in one short closing sentence and offer to refresh:\n" + resultLines.joined(separator: "\n")
        let narration: (answer: String, toolCalls: [AIToolCall])
        do {
            narration = try await appState.askAIWithTools(
                question: rawText,
                context: narrationContext,
                history: recentHistory(),
                model: Self.toolLoopModel,
                tools: []
            )
        } catch {
            return VoiceTurn(speech: resultLines.joined(separator: ". "), uiAction: uiAction)
        }

        return VoiceTurn(speech: narration.answer.isEmpty ? resultLines.joined(separator: ". ") : narration.answer, uiAction: uiAction)
    }
}
