/**
 * POST /realms/:realmId/ask-ai — the Ask [AI] panel's only endpoint.
 * docs/VOICE_LEDGER_SPEC.md: "Every page ends with an Ask Claude panel"
 * (now OpenAI-backed per the owner's 2026-08-28 direction — see
 * docs/VOICE_LEDGER_HANDOFF.md).
 *
 * GET /ai/status and POST /ai/settings expose the kill switch spec calls
 * for: "a single toggle that disables all AI features app-wide... Every
 * deterministic rule, every finding, every calculation, and every report
 * still works with it off."
 *
 * CLAUDE.md rule 1's boundary lives in `SYSTEM_PROMPT` below: the model is
 * told, every single call, that it explains — it never asserts a number,
 * severity, or judgment the caller didn't already give it. This is the
 * ONLY place that boundary is enforced; `OpenAIClient` itself has no
 * opinion about what's said.
 */

import { Router, type RequestHandler } from "express";
import type { AIConfig } from "../config.js";
import type { AISettingsStore } from "../ai/aiSettingsStore.js";
import type { AIChatTurn, AICompletionClient } from "../ai/aiClient.js";
import { OpenAIClient, OpenAIApiError } from "../ai/openaiClient.js";
import { OllamaClient, OllamaApiError } from "../ai/ollamaClient.js";
import { logEvent } from "../logging/logger.js";

/**
 * Owner directive (2026-08-29): the two report buttons (health report,
 * client value summary) were reading noticeably thinner from the free
 * local tier than from OpenAI — investigation found the actual cause
 * wasn't model capability, it was this prompt. The closing instruction
 * below ("keep it to a few sentences, no bullet points") was written for
 * the voice assistant's SPOKEN answers and was being applied to EVERY
 * call through this one shared prompt, including the two report buttons,
 * which are read on screen, never spoken, and are explicitly supposed to
 * be thorough. That one line was capping how much real, already-computed
 * detail either model was allowed to include — a bigger local model was
 * tried and rejected first (gemma4:26b: confirmed live at ~32s just to
 * generate three sentences on this hardware, unusable for an interactive
 * button), so prompt-level headroom is the correct, working fix, not a
 * bigger/slower model.
 *
 * `format: "report"` swaps the closing instruction for a longer, more
 * structured one — used ONLY by the two report-generation buttons
 * (`AppState.generateHealthReport`/`generateValueSummary`, both tiers).
 * Every other caller (per-finding quick explain/second-opinion, voice's
 * reasoning fallback, free-text follow-up questions) keeps the original
 * concise/spoken-friendly behavior — those genuinely are read in a small
 * panel or spoken aloud, where brevity is the right call, not a
 * limitation to route around.
 */
const BASE_SYSTEM_PROMPT = `You are the Ask panel inside Voice Ledger, a bookkeeping tool. Every dollar figure, severity rating, confidence score, and pass/fail decision you see in the "Context" block of the CURRENT message was already computed by deterministic code, not by you.

Earlier messages in this conversation (if any) are real prior exchanges — you already said what they show you saying, and the user already said what they show the user saying. Use them freely to answer conversational/follow-up questions ("what did I just ask?", "why?", "what should I do about that?", confirming a "yes" to something you just proposed). The "stick to the context" rule below is about DOLLAR FIGURES AND FINANCIAL FACTS specifically — it is not a reason to claim you don't remember something you said two messages ago.

Rules you must follow on every reply:
- Never state a dollar figure, percentage, severity, or confidence that isn't already present in the current message's Context block. If asked to calculate something new, say the app's own numbers should be used instead, and that you can only explain what's already there.
- Never give definitive tax, legal, or filing advice. If asked something in that territory, say it's a question for a licensed CPA or attorney, not something you can answer for them.
- Never claim a QuickBooks write, correction, or filing has happened, will happen, or was verified — that is only ever true if the context says so explicitly.
- If a question needs financial data that ISN'T in the current Context block and ISN'T something you already stated earlier in this conversation, say so plainly instead of guessing.
- Talk like a knowledgeable colleague who's actually looked at these books, not a script reading numbers back. Don't restate the question before answering it: say "Cash is $34,250," not "You asked about your cash balance, and I can tell you that..."
- Be decisive, not clarification-happy. If earlier turns in this conversation already proposed a specific next step and the user now says something like "yes," "sure," or "go ahead," that means do — or rather, describe — the exact thing you already offered; don't ask what they meant.`;

const CONCISE_CLOSING = `- Be concise and plain-English — the person reading this is a bookkeeper, not an accountant, per the app's own design philosophy ("training wheels and bowling bumpers").
- This may be spoken aloud by a voice assistant, or read in a small on-screen panel — keep it to a few sentences, no bullet points or markdown formatting.
- Answer the SPECIFIC question asked, directly, in the first sentence. Do not restate or re-summarize the whole Context block — the person asking can already see it on screen. If they ask "what should I look at first," name the one or two most severe/highest-dollar items from the Context and say why, not a repeat of the whole picture. Only give a full overview if they explicitly ask for one (e.g. "summarize this" or "give me the full picture").`;

const REPORT_CLOSING = `- This is a written report, read on screen — not spoken aloud and not a quick answer. Use as much of the real, already-computed detail in the Context block as is genuinely useful. Do not compress for brevity if there's real signal to convey.
- Write it as a few well-organized paragraphs, in this order where the Context block has the material for it: (1) overall health in plain terms, (2) the negative — open issues, what's wrong and how material it is, (3) the positive — what's already been fixed or resolved, (4) the key financial metrics and what they mean for someone running this business, (5) how things have changed since the last report, if that's in the Context block. Skip any section the Context block has nothing for, rather than padding it out.
- Plain prose paragraphs, not bullet points or markdown headers — but each paragraph should be genuinely substantive, not a single compressed sentence.
- Still plain-English for a bookkeeper, not an accountant — thorough does not mean jargon-heavy.`;

function systemPrompt(format: "concise" | "report"): string {
  return `${BASE_SYSTEM_PROMPT}\n${format === "report" ? REPORT_CLOSING : CONCISE_CLOSING}`;
}

const MAX_QUESTION_LENGTH = 2000;
const MAX_CONTEXT_LENGTH = 8000;
/// Prior-turn replay for voice follow-ups (added 2026-08-29 — see
/// `AIChatTurn`'s doc comment). Budgeted the same way as question/context
/// above: hard caps enforced server-side regardless of what the client
/// sends, and a per-turn cap so one oversized entry can't eat the whole
/// budget alone.
const MAX_HISTORY_TURNS = 12;
const MAX_HISTORY_TOTAL_CHARS = 3000;
const MAX_HISTORY_TURN_CHARS = 800;

/** Never trusts the client's history blindly — validates shape, caps a
 * single turn's length, keeps only the most recent turns, then drops the
 * oldest of those until the total is under budget. */
export function sanitizeHistory(raw: unknown): AIChatTurn[] {
  if (!Array.isArray(raw)) return [];
  const turns: AIChatTurn[] = [];
  for (const item of raw) {
    if (
      item &&
      typeof item === "object" &&
      (item.role === "user" || item.role === "assistant") &&
      typeof item.content === "string" &&
      item.content.trim() !== ""
    ) {
      turns.push({ role: item.role, content: item.content.slice(0, MAX_HISTORY_TURN_CHARS) });
    }
  }

  const recent = turns.slice(-MAX_HISTORY_TURNS);
  let totalChars = recent.reduce((sum, turn) => sum + turn.content.length, 0);
  let start = 0;
  while (totalChars > MAX_HISTORY_TOTAL_CHARS && start < recent.length) {
    totalChars -= recent[start]!.content.length;
    start++;
  }
  return recent.slice(start);
}

function buildClient(config: AIConfig | null): AICompletionClient | null {
  if (!config) return null;
  return config.provider === "ollama"
    ? new OllamaClient(config.baseUrl, config.model)
    : new OpenAIClient(config.apiKey, config.model);
}

export function aiRoutes(
  aiConfig: AIConfig | null,
  aiSettingsStore: AISettingsStore,
  requireSession: RequestHandler,
  requireRealmMatch: RequestHandler,
  rateLimitByRealm: RequestHandler,
  /// The opt-in "second opinion" tier (2026-08-29) — see
  /// `config.ts`'s `resolveSecondaryAIConfig` doc comment. Always OpenAI
  /// when configured, entirely independent of `aiConfig`'s own provider —
  /// a request only ever reaches this client when it explicitly asks for
  /// `tier: "secondary"`.
  secondaryAIConfig: AIConfig | null = null
): Router {
  const router = Router();
  const client = buildClient(aiConfig);
  const secondaryClient = buildClient(secondaryAIConfig);

  router.get("/ai/status", requireSession, (_req, res) => {
    res.json({
      configured: client !== null,
      enabled: aiSettingsStore.isEnabled(),
      provider: aiConfig?.provider ?? null,
      model: aiConfig?.model ?? null,
      secondaryConfigured: secondaryClient !== null,
      secondaryProvider: secondaryAIConfig?.provider ?? null,
      secondaryModel: secondaryAIConfig?.model ?? null
    });
  });

  router.post("/ai/settings", requireSession, (req, res) => {
    const enabled = req.body?.enabled;
    if (typeof enabled !== "boolean") {
      res.status(400).json({ error: "Body must be { enabled: boolean }." });
      return;
    }
    aiSettingsStore.setEnabled(enabled);
    logEvent("ai_settings_changed");
    res.json({
      configured: client !== null,
      enabled: aiSettingsStore.isEnabled(),
      provider: aiConfig?.provider ?? null,
      model: aiConfig?.model ?? null,
      secondaryConfigured: secondaryClient !== null,
      secondaryProvider: secondaryAIConfig?.provider ?? null,
      secondaryModel: secondaryAIConfig?.model ?? null
    });
  });

  router.post(
    "/realms/:realmId/ask-ai",
    requireSession,
    requireRealmMatch,
    rateLimitByRealm,
    async (req, res) => {
      const realmId = req.params.realmId!;

      if (!aiSettingsStore.isEnabled()) {
        logEvent("ask_ai_disabled", { realmId });
        res.status(503).json({ error: "AI features are turned off for this app. Turn them back on in Settings to use this." });
        return;
      }

      // Owner directive (2026-08-29): opt-in "second opinion" tier — a
      // request only ever routes to `secondaryClient` (OpenAI) when it
      // explicitly asks, never as a fallback for the default free/local
      // tier. Anything else in `tier` is rejected outright rather than
      // silently treated as "primary" — a typo here should never silently
      // send a paid request nobody asked for, nor silently degrade a
      // second-opinion request to the free tier without saying so.
      const tier = req.body?.tier;
      if (tier !== undefined && tier !== "primary" && tier !== "secondary") {
        res.status(400).json({ error: 'tier must be "primary" or "secondary" when present.' });
        return;
      }
      const useSecondary = tier === "secondary";
      const activeClient = useSecondary ? secondaryClient : client;

      if (!activeClient) {
        logEvent("ask_ai_not_configured", { realmId, tier: useSecondary ? "secondary" : "primary" });
        res.status(503).json({
          error: useSecondary
            ? "The second-opinion tier isn't configured on this backend — no OpenAI API key is set."
            : "AI is not configured on this backend yet — no API key is set."
        });
        return;
      }

      const question = req.body?.question;
      const context = req.body?.context;
      if (typeof question !== "string" || question.trim() === "" || typeof context !== "string") {
        res.status(400).json({ error: "Body must be { question: string, context: string }." });
        return;
      }
      // Owner directive (2026-08-29): report-mode prose, only for the two
      // report buttons — see `systemPrompt`'s doc comment. Same "reject
      // outright, never silently default" posture as `tier` above.
      const format = req.body?.format;
      if (format !== undefined && format !== "concise" && format !== "report") {
        res.status(400).json({ error: 'format must be "concise" or "report" when present.' });
        return;
      }
      if (question.length > MAX_QUESTION_LENGTH) {
        res.status(400).json({ error: `question is too long (max ${MAX_QUESTION_LENGTH} characters).` });
        return;
      }
      if (context.length > MAX_CONTEXT_LENGTH) {
        res.status(400).json({ error: `context is too long (max ${MAX_CONTEXT_LENGTH} characters).` });
        return;
      }

      const history = sanitizeHistory(req.body?.history);

      logEvent("ask_ai_invoked", { realmId, tier: useSecondary ? "secondary" : "primary" });
      try {
        const userMessage = `Context (already computed by the app, not by you):\n${context}\n\nQuestion: ${question}`;
        const result = await activeClient.complete(systemPrompt(format === "report" ? "report" : "concise"), userMessage, history);
        logEvent("ask_ai_succeeded", { realmId, tier: useSecondary ? "secondary" : "primary", latencyMs: result.latencyMs });
        res.json({ answer: result.text, model: result.model });
      } catch (error) {
        const errorName = error instanceof Error ? error.name : "UnknownError";
        if (error instanceof OpenAIApiError || error instanceof OllamaApiError) {
          logEvent("ask_ai_failed", { realmId, tier: useSecondary ? "secondary" : "primary", httpStatus: error.httpStatus, error: errorName });
        } else {
          logEvent("ask_ai_failed", { realmId, tier: useSecondary ? "secondary" : "primary", error: errorName });
        }
        res.status(502).json({ error: "The AI request failed. Try again in a moment." });
      }
    }
  );

  return router;
}
