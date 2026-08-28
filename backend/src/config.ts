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

export interface AIConfig {
  readonly apiKey: string;
  readonly model: string;
}

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
 * `null` when `OPENAI_API_KEY` isn't set — the AI feature (Ask [AI] panel)
 * is entirely optional, unlike QBO credentials. A backend with no AI key
 * configured still runs normally; every deterministic rule, finding, and
 * report works exactly the same (CLAUDE.md's kill-switch guarantee: "every
 * deterministic rule... still works with it off"). The API key itself
 * never leaves this process — CLAUDE.md rule 3, "no secrets in the desktop
 * binary" — the desktop client only ever calls `/realms/:realmId/ask-ai`,
 * never OpenAI directly.
 */
export function resolveAIConfig(env: NodeJS.ProcessEnv = process.env): AIConfig | null {
  const apiKey = env.OPENAI_API_KEY;
  if (!apiKey || apiKey.trim() === "") return null;
  return {
    apiKey,
    model: env.OPENAI_MODEL ?? "gpt-4o-mini"
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
