import { describe, it, expect } from "vitest";
import { resolveQBOCredentials, resolveAppConfig, resolveAIConfig, ConfigError } from "../src/config.js";

/**
 * docs/phase-0/03_SECURITY_THREAT_MODEL.md §3.8 control 1 / §3.8's test
 * requirement, and the owner's explicit Phase 1 instruction: "Sandbox
 * client ID only... Set that up now, not later." This is that control,
 * verified.
 */
describe("resolveQBOCredentials — production guard", () => {
  const sandboxEnv = {
    QBO_SANDBOX_CLIENT_ID: "sandbox-id",
    QBO_SANDBOX_CLIENT_SECRET: "sandbox-secret",
    QBO_REDIRECT_URI: "https://example.test/oauth/callback"
  };

  it("defaults to sandbox when ALLOW_PRODUCTION is unset", () => {
    const credentials = resolveQBOCredentials(sandboxEnv as NodeJS.ProcessEnv);
    expect(credentials.environment).toBe("sandbox");
    expect(credentials.clientId).toBe("sandbox-id");
  });

  it("defaults to sandbox even if production env vars happen to be present but ALLOW_PRODUCTION is unset", () => {
    const credentials = resolveQBOCredentials({
      ...sandboxEnv,
      QBO_PRODUCTION_CLIENT_ID: "prod-id",
      QBO_PRODUCTION_CLIENT_SECRET: "prod-secret"
    } as NodeJS.ProcessEnv);
    expect(credentials.environment).toBe("sandbox");
  });

  it("refuses to produce production credentials without ALLOW_PRODUCTION=true", () => {
    // No ALLOW_PRODUCTION at all, no sandbox vars either — must fail closed,
    // not fall back to some default.
    expect(() => resolveQBOCredentials({} as NodeJS.ProcessEnv)).toThrow(ConfigError);
  });

  it("throws — does not silently fall back to sandbox — when ALLOW_PRODUCTION=true but production credentials are missing", () => {
    expect(() =>
      resolveQBOCredentials({
        ...sandboxEnv,
        ALLOW_PRODUCTION: "true"
      } as NodeJS.ProcessEnv)
    ).toThrow(ConfigError);
  });

  it("returns production credentials only when BOTH ALLOW_PRODUCTION=true AND production vars are set", () => {
    const credentials = resolveQBOCredentials({
      ALLOW_PRODUCTION: "true",
      QBO_PRODUCTION_CLIENT_ID: "prod-id",
      QBO_PRODUCTION_CLIENT_SECRET: "prod-secret",
      QBO_REDIRECT_URI: "https://example.test/oauth/callback"
    } as NodeJS.ProcessEnv);
    expect(credentials.environment).toBe("production");
    expect(credentials.clientId).toBe("prod-id");
  });
});

describe("resolveAppConfig", () => {
  it("rejects a TOKEN_ENCRYPTION_KEY that isn't exactly 32 bytes", () => {
    expect(() =>
      resolveAppConfig({
        APP_BASE_URL: "https://example.test",
        TOKEN_ENCRYPTION_KEY: "tooshort"
      } as NodeJS.ProcessEnv)
    ).toThrow(ConfigError);
  });

  it("accepts a valid 32-byte hex key", () => {
    const key64hex = "a".repeat(64);
    const config = resolveAppConfig({
      APP_BASE_URL: "https://example.test",
      TOKEN_ENCRYPTION_KEY: key64hex
    } as NodeJS.ProcessEnv);
    expect(config.tokenEncryptionKey.length).toBe(32);
  });
});

describe("resolveAIConfig — AI features are optional, never a startup requirement", () => {
  it("returns null when OPENAI_API_KEY is unset — the backend must run fully without it", () => {
    expect(resolveAIConfig({} as NodeJS.ProcessEnv)).toBeNull();
  });

  it("returns null for an empty-string key, not a config that silently 'works' with an empty key", () => {
    expect(resolveAIConfig({ OPENAI_API_KEY: "" } as NodeJS.ProcessEnv)).toBeNull();
  });

  it("returns the key and defaults the model to gpt-4o-mini when OPENAI_MODEL is unset", () => {
    const config = resolveAIConfig({ OPENAI_API_KEY: "sk-test-123" } as NodeJS.ProcessEnv);
    expect(config).toEqual({ apiKey: "sk-test-123", model: "gpt-4o-mini" });
  });

  it("honors an explicit OPENAI_MODEL override", () => {
    const config = resolveAIConfig({ OPENAI_API_KEY: "sk-test-123", OPENAI_MODEL: "gpt-4o" } as NodeJS.ProcessEnv);
    expect(config?.model).toBe("gpt-4o");
  });
});
