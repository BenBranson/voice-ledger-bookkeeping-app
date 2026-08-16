/**
 * The second, independent layer of §3.5's logging control. The typed
 * logger (logger.ts) is the primary defense; this scans the SERIALIZED
 * output for token-shaped and currency-shaped strings as a backstop, on the
 * assumption that the primary defense will eventually be bypassed by
 * someone in a hurry — including a future version of me.
 */

export interface RedactionResult {
  readonly matched: boolean;
  readonly patterns: readonly string[];
}

interface NamedPattern {
  readonly name: string;
  readonly pattern: RegExp;
}

const PATTERNS: readonly NamedPattern[] = [
  // QBO / OAuth2 bearer tokens and refresh tokens are long opaque strings,
  // typically base64url-ish and 20+ characters.
  { name: "bearer_token", pattern: /\bBearer\s+[A-Za-z0-9._-]{20,}/i },
  { name: "long_opaque_token", pattern: /"(access_token|refresh_token|client_secret|id_token)"\s*:\s*"[^"]{8,}"/i },
  // A currency-shaped value — e.g. "486.20" or "$1,234.56" — should never
  // appear in a log line per the forbidden list in §3.5.
  { name: "currency_amount", pattern: /\$?\d{1,3}(,\d{3})*\.\d{2}\b/ },
  // Anthropic-style API keys, in case one is ever accidentally interpolated.
  { name: "anthropic_key", pattern: /sk-ant-[A-Za-z0-9_-]{20,}/ }
];

export function redact(serializedLogLine: string): RedactionResult {
  const matches: string[] = [];
  for (const { name, pattern } of PATTERNS) {
    if (pattern.test(serializedLogLine)) {
      matches.push(name);
    }
  }
  return { matched: matches.length > 0, patterns: matches };
}
