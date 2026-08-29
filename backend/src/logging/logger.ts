/**
 * Structured logging with a closed field set. docs/phase-0/03_SECURITY_THREAT_MODEL.md
 * §3.5: "A structured logger where the ONLY way to log is via typed fields
 * drawn from the allowed set. No `log(String)` interpolation API exists in
 * the backend."
 *
 * There is deliberately no exported function that accepts a free-form
 * message string with data spliced in. Every call site names an event and
 * passes a typed payload; TypeScript's structural typing rejects a payload
 * containing a field that isn't in `LogFields`, which is the mechanism that
 * keeps a stray `body` or `token` field from ever reaching a log line.
 */

import { redact } from "./redaction.js";

export type LogEvent =
  | "http_request"
  | "oauth_exchange"
  | "oauth_refresh"
  | "oauth_refresh_failed"
  | "session_created"
  | "session_rejected"
  | "realm_authorization_denied"
  | "operation_invoked"
  | "operation_unreachable"
  | "operation_write_disabled"
  | "operation_succeeded"
  | "operation_failed"
  | "rate_limited"
  | "config_error"
  | "server_started"
  | "ask_ai_invoked"
  | "ask_ai_succeeded"
  | "ask_ai_failed"
  | "ask_ai_disabled"
  | "ask_ai_not_configured"
  | "ai_settings_changed";

/**
 * Every field a log line is EVER allowed to carry. Adding a field here is a
 * reviewable, deliberate act — that's the point. Notably absent, on
 * purpose, per §3.5's forbidden list: token values, request/response
 * bodies, dollar amounts, entity names (vendor/customer/employee), memos,
 * descriptions, document numbers, imported file contents, and any Claude
 * prompt or completion.
 */
export interface LogFields {
  readonly timestamp?: string;
  readonly sessionId?: string;
  readonly realmId?: string;
  readonly operationName?: string;
  readonly outcome?: "success" | "fault" | "timeout";
  readonly httpStatus?: number;
  readonly httpMethod?: string;
  readonly httpPath?: string;
  readonly latencyMs?: number;
  readonly intentId?: string;
  readonly minorVersion?: number;
  readonly byteCount?: number;
  readonly error?: string; // the error's `.message` / class name — never a raw stack containing interpolated request data
  /// Which Ask AI tier served this request — "primary" (the app's default,
  /// currently local Ollama) or "secondary" (the opt-in, paid, per-question
  /// OpenAI "second opinion," 2026-08-29). Never a provider name or model —
  /// just which tier, so an operator can see spend-relevant requests in the
  /// log without this becoming a place provider/model details leak.
  readonly tier?: "primary" | "secondary";
}

export interface LogLine extends LogFields {
  readonly event: LogEvent;
  readonly timestamp: string;
}

/**
 * The only logging entry point in this codebase. `event` names what
 * happened; `fields` is drawn exclusively from `LogFields`. Emits one JSON
 * line to stdout, after passing through the redaction filter as a second,
 * independent layer (§3.5) — a match there means this typed logger was
 * somehow bypassed, which is a bug in the logger itself, not routine noise.
 */
export function logEvent(event: LogEvent, fields: LogFields = {}): void {
  const line: LogLine = {
    event,
    timestamp: new Date().toISOString(),
    ...fields
  };
  const serialized = JSON.stringify(line);
  const redactionResult = redact(serialized);
  if (redactionResult.matched) {
    // The typed logger was bypassed somehow, or a field we thought was safe
    // contains a token/currency-shaped value. Loud on purpose — see
    // docs/phase-0/03_SECURITY_THREAT_MODEL.md §3.5: "a match there means
    // the typed logger was bypassed, which is a bug to fix, not noise to
    // suppress."
    process.stderr.write(
      `REDACTION_ALARM: log line for event "${event}" matched a redaction pattern (${redactionResult.patterns.join(", ")}). Line suppressed.\n`
    );
    return;
  }
  process.stdout.write(serialized + "\n");
}
