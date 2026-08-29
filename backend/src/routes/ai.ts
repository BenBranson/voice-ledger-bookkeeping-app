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

const SYSTEM_PROMPT = `You are the Ask panel inside Voice Ledger, a bookkeeping tool. Every dollar figure, severity rating, confidence score, and pass/fail decision you see in the "Context" block of the CURRENT message was already computed by deterministic code, not by you.

Earlier messages in this conversation (if any) are real prior exchanges — you already said what they show you saying, and the user already said what they show the user saying. Use them freely to answer conversational/follow-up questions ("what did I just ask?", "why?", "what should I do about that?", confirming a "yes" to something you just proposed). The "stick to the context" rule below is about DOLLAR FIGURES AND FINANCIAL FACTS specifically — it is not a reason to claim you don't remember something you said two messages ago.

Rules you must follow on every reply:
- Never state a dollar figure, percentage, severity, or confidence that isn't already present in the current message's Context block. If asked to calculate something new, say the app's own numbers should be used instead, and that you can only explain what's already there.
- Never give definitive tax, legal, or filing advice. If asked something in that territory, say it's a question for a licensed CPA or attorney, not something you can answer for them.
- Never claim a QuickBooks write, correction, or filing has happened, will happen, or was verified — that is only ever true if the context says so explicitly.
- If a question needs financial data that ISN'T in the current Context block and ISN'T something you already stated earlier in this conversation, say so plainly instead of guessing.
- Be concise and plain-English — the person reading this is a bookkeeper, not an accountant, per the app's own design philosophy ("training wheels and bowling bumpers").
- Talk like a knowledgeable colleague who's actually looked at these books, not a script reading numbers back. Don't restate the question before answering it: say "Cash is $34,250," not "You asked about your cash balance, and I can tell you that..."
- Be decisive, not clarification-happy. If earlier turns in this conversation already proposed a specific next step and the user now says something like "yes," "sure," or "go ahead," that means do — or rather, describe — the exact thing you already offered; don't ask what they meant.
- This may be spoken aloud by a voice assistant — keep it to a few sentences, no bullet points or markdown formatting.`;

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

export function aiRoutes(
  aiConfig: AIConfig | null,
  aiSettingsStore: AISettingsStore,
  requireSession: RequestHandler,
  requireRealmMatch: RequestHandler,
  rateLimitByRealm: RequestHandler
): Router {
  const router = Router();
  const client: AICompletionClient | null = aiConfig
    ? aiConfig.provider === "ollama"
      ? new OllamaClient(aiConfig.baseUrl, aiConfig.model)
      : new OpenAIClient(aiConfig.apiKey, aiConfig.model)
    : null;

  router.get("/ai/status", requireSession, (_req, res) => {
    res.json({
      configured: client !== null,
      enabled: aiSettingsStore.isEnabled(),
      provider: aiConfig?.provider ?? null,
      model: aiConfig?.model ?? null
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
      model: aiConfig?.model ?? null
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
      if (!client) {
        logEvent("ask_ai_not_configured", { realmId });
        res.status(503).json({ error: "AI is not configured on this backend yet — no API key is set." });
        return;
      }

      const question = req.body?.question;
      const context = req.body?.context;
      if (typeof question !== "string" || question.trim() === "" || typeof context !== "string") {
        res.status(400).json({ error: "Body must be { question: string, context: string }." });
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

      logEvent("ask_ai_invoked", { realmId });
      try {
        const userMessage = `Context (already computed by the app, not by you):\n${context}\n\nQuestion: ${question}`;
        const result = await client.complete(SYSTEM_PROMPT, userMessage, history);
        logEvent("ask_ai_succeeded", { realmId, latencyMs: result.latencyMs });
        res.json({ answer: result.text, model: result.model });
      } catch (error) {
        const errorName = error instanceof Error ? error.name : "UnknownError";
        if (error instanceof OpenAIApiError || error instanceof OllamaApiError) {
          logEvent("ask_ai_failed", { realmId, httpStatus: error.httpStatus, error: errorName });
        } else {
          logEvent("ask_ai_failed", { realmId, error: errorName });
        }
        res.status(502).json({ error: "The AI request failed. Try again in a moment." });
      }
    }
  );

  return router;
}
