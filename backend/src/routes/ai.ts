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
import { OpenAIClient, OpenAIApiError } from "../ai/openaiClient.js";
import { logEvent } from "../logging/logger.js";

const SYSTEM_PROMPT = `You are the Ask panel inside Voice Ledger, a bookkeeping tool. Every dollar figure, severity rating, confidence score, and pass/fail decision you see in the context below was already computed by deterministic code, not by you.

Rules you must follow on every reply:
- Never state a dollar figure, percentage, severity, or confidence that isn't already present in the context you were given. If asked to calculate something new, say the app's own numbers should be used instead, and that you can only explain what's already there.
- Never give definitive tax, legal, or filing advice. If asked something in that territory, say it's a question for a licensed CPA or attorney, not something you can answer for them.
- Never claim a QuickBooks write, correction, or filing has happened, will happen, or was verified — that is only ever true if the context says so explicitly.
- Keep answers grounded strictly in the context provided. If the context doesn't contain enough information to answer, say so plainly instead of guessing.
- Be concise and plain-English — the person reading this is a bookkeeper, not an accountant, per the app's own design philosophy ("training wheels and bowling bumpers").`;

const MAX_QUESTION_LENGTH = 2000;
const MAX_CONTEXT_LENGTH = 8000;

export function aiRoutes(
  aiConfig: AIConfig | null,
  aiSettingsStore: AISettingsStore,
  requireSession: RequestHandler,
  requireRealmMatch: RequestHandler,
  rateLimitByRealm: RequestHandler
): Router {
  const router = Router();
  const client = aiConfig ? new OpenAIClient(aiConfig.apiKey, aiConfig.model) : null;

  router.get("/ai/status", requireSession, (_req, res) => {
    res.json({ configured: client !== null, enabled: aiSettingsStore.isEnabled() });
  });

  router.post("/ai/settings", requireSession, (req, res) => {
    const enabled = req.body?.enabled;
    if (typeof enabled !== "boolean") {
      res.status(400).json({ error: "Body must be { enabled: boolean }." });
      return;
    }
    aiSettingsStore.setEnabled(enabled);
    logEvent("ai_settings_changed");
    res.json({ configured: client !== null, enabled: aiSettingsStore.isEnabled() });
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

      logEvent("ask_ai_invoked", { realmId });
      try {
        const userMessage = `Context (already computed by the app, not by you):\n${context}\n\nQuestion: ${question}`;
        const result = await client.complete(SYSTEM_PROMPT, userMessage);
        logEvent("ask_ai_succeeded", { realmId, latencyMs: result.latencyMs });
        res.json({ answer: result.text, model: result.model });
      } catch (error) {
        const errorName = error instanceof Error ? error.name : "UnknownError";
        if (error instanceof OpenAIApiError) {
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
