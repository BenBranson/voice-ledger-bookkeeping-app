/**
 * All runtime configuration, loaded from environment variables exactly once.
 *
 * docs/phase-0/03_SECURITY_THREAT_MODEL.md §3.8, control 1: "Separate
 * credentials. Sandbox and production QBO apps have different client IDs.
 * A development backend is configured with the sandbox client ID only and
 * physically cannot mint a production token." This module is where that
 * control lives — `resolveQBOCredentials()` is the only place a client
 * secret is read, and it refuses to return production credentials unless
 * TWO independent things are both true.
 */

export type Environment = "sandbox" | "production";

export interface QBOCredentials {
  readonly environment: Environment;
  readonly clientId: string;
  readonly clientSecret: string;
  readonly redirectUri: string;
  readonly minorVersion: number;
}

/**
 * Two shapes, picked by `AI_PROVIDER`. "ollama" needs no secret at all —
 * it's this machine talking to its own local Ollama server — which is why
 * `resolveAIConfig` below never returns `null` for it the way it does for
 * a missing OpenAI key.
 */
export type AIConfig =
  | { readonly provider: "openai"; readonly apiKey: string; readonly model: string }
  | { readonly provider: "ollama"; readonly baseUrl: string; readonly model: string };

export interface AppConfig {
  readonly port: number;
  readonly baseUrl: string;
  readonly tokenEncryptionKey: Buffer;
  readonly sqlitePath: string;
  readonly allowProductionWrites: boolean;
}

function requireEnv(env: NodeJS.ProcessEnv, name: string): string {
  const value = env[name];
  if (!value || value.trim() === "") {
    throw new ConfigError(`Missing required environment variable: ${name}`);
  }
  return value;
}

export class ConfigError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ConfigError";
  }
}

/**
 * docs/phase-0/03_SECURITY_THREAT_MODEL.md §3.8: production credentials are
 * refused unless BOTH `ALLOW_PRODUCTION=true` AND distinct
 * `QBO_PRODUCTION_CLIENT_ID` / `QBO_PRODUCTION_CLIENT_SECRET` values are
 * present. Absent either, this function can only ever return sandbox
 * credentials — there is no code path that falls back to using the sandbox
 * client ID "as" a production one, which would be a worse failure than
 * simply refusing.
 */
export function resolveQBOCredentials(env: NodeJS.ProcessEnv = process.env): QBOCredentials {
  const allowProduction = env.ALLOW_PRODUCTION === "true";
  const minorVersion = Number(env.QBO_MINOR_VERSION ?? "75");

  if (allowProduction) {
    const clientId = env.QBO_PRODUCTION_CLIENT_ID;
    const clientSecret = env.QBO_PRODUCTION_CLIENT_SECRET;
    if (clientId && clientSecret) {
      return {
        environment: "production",
        clientId,
        clientSecret,
        redirectUri: requireEnv(env, "QBO_REDIRECT_URI"),
        minorVersion
      };
    }
    // ALLOW_PRODUCTION=true but production credentials weren't supplied —
    // this is a misconfiguration, not a reason to silently use sandbox
    // credentials in a way that could be mistaken for production access.
    throw new ConfigError(
      "ALLOW_PRODUCTION=true but QBO_PRODUCTION_CLIENT_ID / QBO_PRODUCTION_CLIENT_SECRET are not both set."
    );
  }

  return {
    environment: "sandbox",
    clientId: requireEnv(env, "QBO_SANDBOX_CLIENT_ID"),
    clientSecret: requireEnv(env, "QBO_SANDBOX_CLIENT_SECRET"),
    redirectUri: requireEnv(env, "QBO_REDIRECT_URI"),
    minorVersion
  };
}

/**
 * The AI feature (Ask [AI] panel) is entirely optional, unlike QBO
 * credentials — a backend with no AI provider configured still runs
 * normally; every deterministic rule, finding, and report works exactly
 * the same (CLAUDE.md's kill-switch guarantee: "every deterministic
 * rule... still works with it off").
 *
 * `AI_PROVIDER=ollama` (2026-08-29, per the owner's own direction to cut
 * AI cost — this app's default going forward): talks to a local Ollama
 * server, no API key, genuinely free per request. Never `null` for this
 * provider — there's no secret to be missing, only "is Ollama actually
 * running," which `OllamaClient.complete` surfaces as a normal request
 * failure if not, the same way a network error would for any provider.
 *
 * `AI_PROVIDER=openai` (or unset, for backward compatibility): `null`
 * when `OPENAI_API_KEY` isn't set. The key itself never leaves this
 * process — CLAUDE.md rule 3, "no secrets in the desktop binary" — the
 * desktop client only ever calls `/realms/:realmId/ask-ai`, never OpenAI
 * directly.
 */
export function resolveAIConfig(env: NodeJS.ProcessEnv = process.env): AIConfig | null {
  const provider = (env.AI_PROVIDER ?? "openai").trim().toLowerCase();

  if (provider === "ollama") {
    return {
      provider: "ollama",
      baseUrl: env.OLLAMA_BASE_URL ?? "http://localhost:11434",
      model: env.OLLAMA_MODEL ?? "gemma4:12b"
    };
  }

  const apiKey = env.OPENAI_API_KEY;
  if (!apiKey || apiKey.trim() === "") return null;
  return {
    provider: "openai",
    apiKey,
    model: env.OPENAI_MODEL ?? "gpt-4o-mini"
  };
}

/**
 * The opt-in "second opinion" tier (2026-08-29, per the owner's explicit
 * request): a bookkeeper who wants a more capable model's read on a finding
 * can ask for it deliberately, per question — this is INDEPENDENT of
 * `AI_PROVIDER`/`resolveAIConfig` above, which picks the app's default
 * (free, local Ollama) tier. Always tries OpenAI specifically, regardless
 * of what the primary provider is set to; `null` when `OPENAI_API_KEY`
 * isn't set, same "just not configured, not an error" posture as the
 * primary resolver.
 *
 * Never auto-invoked — `routes/ai.ts`'s `/ask-ai` only reaches this client
 * when the request explicitly asks for `tier: "secondary"`, which the
 * desktop app only ever sends from a button the owner clicks themselves
 * (never from the default "Explain This Finding" flow). Keeping this a
 * fully separate resolver/client, rather than a mode of the primary one,
 * means the free local tier can never accidentally fall back to a paid
 * API call.
 */
export function resolveSecondaryAIConfig(env: NodeJS.ProcessEnv = process.env): AIConfig | null {
  const apiKey = env.OPENAI_API_KEY;
  if (!apiKey || apiKey.trim() === "") return null;
  return {
    provider: "openai",
    apiKey,
    model: env.OPENAI_MODEL ?? "gpt-4o-mini"
  };
}

export interface AnthropicAIConfig {
  readonly apiKey: string;
  readonly model: string;
}

/**
 * Owner directive (2026-09-07): a selectable Claude-backed option for
 * Voice Ledger's own in-app voice assistant tool loop, alongside the
 * existing free/local `gemma4:12b` default (`ALLOWED_MODEL_OVERRIDES` in
 * `routes/ai.ts`). A completely separate resolver/credential from both
 * `resolveAIConfig` (the app's default tier) and `resolveSecondaryAIConfig`
 * (the OpenAI "second opinion" tier) — same "independent resolver, never a
 * silent fallback" posture those two already established. `null` when
 * `ANTHROPIC_API_KEY` isn't set, same as the other optional-AI resolvers.
 */
export function resolveAnthropicConfig(env: NodeJS.ProcessEnv = process.env): AnthropicAIConfig | null {
  const apiKey = env.ANTHROPIC_API_KEY;
  if (!apiKey || apiKey.trim() === "") return null;
  return {
    apiKey,
    model: env.ANTHROPIC_MODEL ?? "claude-haiku-4-5"
  };
}

export function resolveAppConfig(env: NodeJS.ProcessEnv = process.env): AppConfig {
  const keyHex = requireEnv(env, "TOKEN_ENCRYPTION_KEY");
  const key = Buffer.from(keyHex, "hex");
  if (key.length !== 32) {
    throw new ConfigError(
      `TOKEN_ENCRYPTION_KEY must be 32 bytes hex-encoded (64 hex characters); got ${key.length} bytes. ` +
        `Generate one with: node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"`
    );
  }

  return {
    port: Number(env.PORT ?? "3000"),
    baseUrl: requireEnv(env, "APP_BASE_URL"),
    tokenEncryptionKey: key,
    sqlitePath: env.SQLITE_PATH ?? "./data/voiceledger.sqlite",
    // §3.8 control 3: "Backend refuses production writes unless an explicit
    // deployment-level flag is set, and that flag is absent from every
    // development and CI configuration." Phase 1 step 1.2 ships read-only
    // regardless (no write operation exists in the catalog yet — see
    // src/catalog/operations.ts) — this flag governs a future step, recorded
    // here now so the control exists before it's needed.
    allowProductionWrites: env.ALLOW_PRODUCTION_WRITES === "true"
  };
}
