import type { Request, Response, NextFunction } from "express";
import { logEvent } from "../logging/logger.js";

/**
 * Per-realm token bucket. docs/phase-0/02_QBO_CAPABILITY_MATRIX.md §2.5:
 * "a per-realm token bucket in the backend so that the ceiling is enforced
 * across all desktop clients for that realm, not per-process."
 *
 * Phase 1 scope: single-instance in-memory bucket. Explicit limitation,
 * not an oversight — a multi-instance deployment would need a shared store
 * (e.g. Redis) for this to hold across instances. Single operator, tens of
 * clients (docs/phase-0/OPEN_QUESTIONS.md Q6) does not need that yet.
 *
 * Threshold is a placeholder pending docs/phase-0/SPIKE_QUEUE.md item 10
 * (`testRateLimitThreshold`) — it exists so the *mechanism* is in place and
 * testable before the real number is known, not to assert we know QBO's
 * actual limit.
 */

interface Bucket {
  tokens: number;
  lastRefillAt: number;
}

const CAPACITY = 30; // placeholder — see doc comment above
const REFILL_PER_SECOND = 5; // placeholder

export class RateLimiter {
  private readonly buckets = new Map<string, Bucket>();

  tryConsume(realmId: string): boolean {
    const now = Date.now();
    const bucket = this.buckets.get(realmId) ?? { tokens: CAPACITY, lastRefillAt: now };

    const elapsedSeconds = (now - bucket.lastRefillAt) / 1000;
    const refilled = Math.min(CAPACITY, bucket.tokens + elapsedSeconds * REFILL_PER_SECOND);

    if (refilled < 1) {
      this.buckets.set(realmId, { tokens: refilled, lastRefillAt: now });
      return false;
    }

    this.buckets.set(realmId, { tokens: refilled - 1, lastRefillAt: now });
    return true;
  }
}

export function rateLimitByRealm(limiter: RateLimiter) {
  return (req: Request, res: Response, next: NextFunction): void => {
    const realmId = req.params.realmId ?? req.sessionRealmId;
    if (!realmId) {
      next();
      return;
    }
    if (!limiter.tryConsume(realmId)) {
      logEvent("rate_limited", { realmId, httpPath: req.path });
      res.status(429).json({ error: "Rate limit exceeded for this realm. Retry shortly." });
      return;
    }
    next();
  };
}
