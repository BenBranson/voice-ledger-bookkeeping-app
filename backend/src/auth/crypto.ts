/**
 * AES-256-GCM encryption for refresh tokens at rest.
 *
 * docs/phase-0/03_SECURITY_THREAT_MODEL.md §3.9: "QBO refresh token — ~100
 * days — Backend, encrypted at rest, per realmId." This module is that
 * encryption. The key comes from `TOKEN_ENCRYPTION_KEY` (config.ts) and is
 * never derived from anything else — no hardcoded fallback, no
 * "development mode" plaintext path.
 */

import { randomBytes, createCipheriv, createDecipheriv } from "node:crypto";

const ALGORITHM = "aes-256-gcm";
const IV_LENGTH = 12; // 96-bit nonce, standard for GCM

export interface EncryptedPayload {
  readonly iv: string; // hex
  readonly authTag: string; // hex
  readonly ciphertext: string; // hex
}

export function encrypt(plaintext: string, key: Buffer): EncryptedPayload {
  const iv = randomBytes(IV_LENGTH);
  const cipher = createCipheriv(ALGORITHM, key, iv);
  const ciphertext = Buffer.concat([cipher.update(plaintext, "utf8"), cipher.final()]);
  const authTag = cipher.getAuthTag();
  return {
    iv: iv.toString("hex"),
    authTag: authTag.toString("hex"),
    ciphertext: ciphertext.toString("hex")
  };
}

export function decrypt(payload: EncryptedPayload, key: Buffer): string {
  const decipher = createDecipheriv(ALGORITHM, key, Buffer.from(payload.iv, "hex"));
  decipher.setAuthTag(Buffer.from(payload.authTag, "hex"));
  const plaintext = Buffer.concat([
    decipher.update(Buffer.from(payload.ciphertext, "hex")),
    decipher.final()
  ]);
  return plaintext.toString("utf8");
}
