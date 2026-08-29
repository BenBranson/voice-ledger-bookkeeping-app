import { describe, it, expect } from "vitest";
import { sanitizeHistory } from "../src/routes/ai.js";

describe("sanitizeHistory — voice conversation memory (2026-08-29)", () => {
  it("passes through well-formed history unchanged", () => {
    const history = [
      { role: "user", content: "Why is this flagged?" },
      { role: "assistant", content: "The amount is 5x this vendor's typical charge." }
    ];
    expect(sanitizeHistory(history)).toEqual(history);
  });

  it("returns an empty array for non-array input", () => {
    expect(sanitizeHistory(undefined)).toEqual([]);
    expect(sanitizeHistory(null)).toEqual([]);
    expect(sanitizeHistory("not an array")).toEqual([]);
  });

  it("drops entries with an invalid role or missing/empty content", () => {
    const history = [
      { role: "system", content: "should be dropped, not user/assistant" },
      { role: "user", content: "" },
      { role: "user", content: "kept" },
      { role: "assistant" }
    ];
    expect(sanitizeHistory(history)).toEqual([{ role: "user", content: "kept" }]);
  });

  it("caps a single turn's content length so one oversized entry can't eat the whole budget", () => {
    const longContent = "x".repeat(2000);
    const result = sanitizeHistory([{ role: "user", content: longContent }]);
    expect(result[0]!.content.length).toBe(800);
  });

  it("keeps only the most recent MAX_HISTORY_TURNS (12) entries", () => {
    const history = Array.from({ length: 20 }, (_, i) => ({ role: "user" as const, content: `turn ${i}` }));
    const result = sanitizeHistory(history);
    expect(result.length).toBe(12);
    expect(result[0]!.content).toBe("turn 8");
    expect(result[result.length - 1]!.content).toBe("turn 19");
  });

  it("drops the oldest turns until the total character budget (3000) is respected", () => {
    // 5 turns of 700 chars each = 3500 total, over the 3000 budget —
    // the oldest one should be dropped, leaving 4 * 700 = 2800.
    const history = Array.from({ length: 5 }, (_, i) => ({ role: "user" as const, content: `${i}`.repeat(700) }));
    const result = sanitizeHistory(history);
    expect(result.length).toBe(4);
    const totalChars = result.reduce((sum, turn) => sum + turn.content.length, 0);
    expect(totalChars).toBeLessThanOrEqual(3000);
  });
});
