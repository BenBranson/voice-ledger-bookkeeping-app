/**
 * Intuit's app assessment requires realm IDs, like refresh tokens, to be
 * encrypted at rest. A realm ID is stored AES-256-GCM encrypted; rows are
 * found by `lookupKey`, a keyed HMAC, so the database never holds a
 * plaintext realm ID yet lookups stay exact.
 */

import { createHmac } from "node:crypto";
import { encrypt, decrypt, type EncryptedPayload } from "./crypto.js";

export class RealmCipher {
  private readonly hmacKey: Buffer;

  constructor(private readonly encryptionKey: Buffer) {
    this.hmacKey = createHmac("sha256", encryptionKey).update("voice-ledger/realm-lookup/v1").digest();
  }

  lookupKey(realmId: string): string {
    return createHmac("sha256", this.hmacKey).update(realmId).digest("hex");
  }

  seal(realmId: string): EncryptedPayload {
    return encrypt(realmId, this.encryptionKey);
  }

  open(payload: EncryptedPayload): string {
    return decrypt(payload, this.encryptionKey);
  }
}
