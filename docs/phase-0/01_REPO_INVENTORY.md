# 1. Existing Prototype Repo Inventory

**Status: N/A — permanently, per owner confirmation 2026-08-17.**

The Phase 0 prompt said:

> There's also an existing prototype repo at **[REPO URL / PATH]** built in a
> web-based AI app builder.

That placeholder described an assumption, not a fact: it presumed a prototype
codebase existed and just hadn't been located yet. The owner confirmed
2026-08-17 that this build is fresh — no such repo exists anywhere. This
deliverable is therefore closed as not applicable, not left open waiting on a
path that will never arrive. Everything else in Phase 0 was already complete
and never depended on it (§4.4 in `VOICE_LEDGER_HANDOFF.md`'s note on the
prototype's *screenshots* — visual direction and feature-set inspiration
only — still stands; that came from images shown in conversation, not a repo).

---

## What this deliverable would have contained, had a prototype existed

Kept for historical record only — do not resurrect this as a pending task.

### A. Inventory
- File/module tree with LOC and last-modified, grouped by apparent purpose
- Framework and platform inventory (which builder, what it generated, what
  runtime it assumed)
- Data model as the prototype defined it — tables, entities, field names
- Every QBO endpoint the prototype called, extracted from source, cross-checked
  against §2's capability matrix
- Every place an LLM call sits in a decision path

### B. Findings logic worth carrying forward *conceptually*
Extracted as **rule specifications, not code**: for each detection the prototype
performed, what triggered it, what thresholds it used, what it classified as
severity/confidence, and whether it satisfies `CLAUDE.md` rule 1 (deterministic).
Output format is the `Rule` spec template in §8, so it drops straight into the
rule registry backlog.

### C. Discard list, with reasons
Expected categories, based on what web-app-builder output typically looks like:
- Anything where an LLM produced a number, a severity, or a pass/fail — violates
  `CLAUDE.md` rule 1 regardless of how well it worked
- Any direct QBO call from client code — violates rule 3
- Any "current client" global — violates rule 9
- Green-on-empty-data rendering — violates rule 5
- Web UI, routing, state management, styling — near-zero reuse per your own
  framing

### D. Capability claims to re-verify
Anything the prototype *appeared* to do successfully against QBO becomes a
high-priority row in the §2 matrix marked `ASSUMED (prototype-observed)` — which
is stronger evidence than documentation but still not sandbox proof under rule 6.
This is the single most valuable output of the inventory: the prototype is a
record of which endpoints actually returned useful data in practice.

---

## The permanent stand-in, now that no prototype is coming

Where other documents needed to know what the prototype checked for, the
**Reference Findings Library** at the end of `VOICE_LEDGER_SPEC.md` (duplicate
expenses/bills/invoices/payments, reconciliation differences, uncategorized or
miscoded transactions, unusual vendor names/amounts/timing, negative balances and
abnormal clearing accounts, changed or unused recurring subscriptions, avoidable
fees and interest, vendor price increases and duplicate services, possible
personal expenses in business accounts) was used as the source list of
detections. §8's rule backlog is seeded from that list — and, as of
2026-08-17, this is no longer an interim substitute pending something better;
it's the permanent source. No other Phase 0 document changes as a result of
this resolution.
