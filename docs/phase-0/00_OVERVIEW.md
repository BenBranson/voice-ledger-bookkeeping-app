# Voice Ledger — Phase 0 Architecture & Implementation Plan

**Status:** Draft for review. No application code has been written.
**Date:** 2026-08-15
**Inputs:** `docs/VOICE_LEDGER_SPEC.md` (v9), `CLAUDE.md`

---

## How to read this

Twelve documents, one per requested deliverable. Read in this order if you're
reviewing everything; jump to §2 if you only have time for one.

| # | Document | What it decides |
|---|---|---|
| 1 | [01_REPO_INVENTORY.md](01_REPO_INVENTORY.md) | **BLOCKED** — prototype repo path still not supplied (see `OPEN_QUESTIONS.md` Q1) |
| 2 | [02_QBO_CAPABILITY_MATRIX.md](02_QBO_CAPABILITY_MATRIX.md) | What QBO can actually do, per feature. The load-bearing document. |
| 3 | [03_SECURITY_THREAT_MODEL.md](03_SECURITY_THREAT_MODEL.md) | Backend boundary, token handling, why the desktop client can't call arbitrary QBO |
| 4 | [04_DATA_MODEL.md](04_DATA_MODEL.md) | The normalized shape API data and file imports both resolve into |
| 5 | [05_FINDING_SCHEMA.md](05_FINDING_SCHEMA.md) | Universal Finding as Swift types |
| 6 | [06_PERIOD_STATE_MACHINE.md](06_PERIOD_STATE_MACHINE.md) | Page states, completion criteria, dependency graph, staleness |
| 7 | [07_CLIENT_ISOLATION.md](07_CLIENT_ISOLATION.md) | `realmId` segregation enforced by types, not discipline |
| 8 | [08_RULE_ENGINE.md](08_RULE_ENGINE.md) | How a rule is defined, registered, versioned, tested |
| 9 | [09_INGESTION_PIPELINE.md](09_INGESTION_PIPELINE.md) | Three tiers, cross-foot, verification UI, provenance |
| 10 | [10_STAGING_APPROVAL_AUDIT.md](10_STAGING_APPROVAL_AUDIT.md) | Staging, approval, idempotency, timed-out writes, recovery |
| 11 | [11_VERTICAL_SLICE.md](11_VERTICAL_SLICE.md) | Duplicate posted-expense, end to end. Exact scope. |
| 12 | [12_TEST_STRATEGY.md](12_TEST_STRATEGY.md) | Sandbox test strategy; how ASSUMED becomes VERIFIED |
| — | [CAPABILITY_CLASSIFICATION.md](CAPABILITY_CLASSIFICATION.md) | Every proposed feature, classified into the five buckets |
| — | [SPIKE_QUEUE.md](SPIKE_QUEUE.md) | The §2.8 waves as an ordered, runnable test list — `Purchase` void first |
| — | [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md) | Answered 2026-08. Two placeholders still open: repo path, macOS version. |

---

## The one thing to take away

**Almost nothing in the capability matrix is VERIFIED, and that is the correct
state at the end of Phase 0.** I have no sandbox access in this session, so every
QBO behavioral claim in these documents is marked `ASSUMED` with a stated
confidence and a named test that will settle it. §12 defines the mechanism that
flips rows to `VERIFIED`: the matrix is *generated from passing sandbox tests*,
not hand-edited. A row cannot claim VERIFIED unless a test asserted it against a
live sandbox within the staleness window.

This directly implements `CLAUDE.md` rule 6 — "No feature is labeled 'Automatic'
without sandbox proof." The matrix is the enforcement surface for that rule.

---

## Architectural decisions made in this phase

These are the choices the rest of the plan depends on. Each is argued in its
document; collected here so you can disagree with them in one place.

**D1 — The rule engine has three outcomes, not two.**
`RuleOutcome` is `.pass`, `.findings`, or `.cannotEvaluate`. There is no code
path where "the rule ran and produced zero findings" and "the rule could not run"
collapse into the same value. This makes `CLAUDE.md` rule 5 a type-level
guarantee rather than a UI convention. (§8)

**D2 — Client isolation is one SQLite database per `realmId`, plus a phantom
type.** Not a `realm_id` column with a `WHERE` clause. A cross-client query is a
compile error or an impossible file path, not a missed predicate. (§7)

**D3 — Every completed page records an evidence watermark, and staleness is
watermark inequality.** Not a manual "mark stale" call anyone can forget. A page
is fresh iff the watermark it was completed against still equals the current
watermark for its declared inputs. (§6)

**D4 — Writes use a three-phase local journal with an explicit `unknown` state.**
A timed-out POST moves to `unknown`, which blocks further writes to that entity
and requires a resolution probe. Never a blind retry. (§10)

**D5 — The backend exposes a fixed catalog of named, typed operations — not a
QBO proxy.** The desktop client cannot express "PUT this JSON to /v3/company/X/Y".
It can only invoke `voidPurchase(realmId:id:syncToken:intentId:)`. Adding a new
QBO capability requires a backend deploy. (§3)

**D6 — Reports are treated as a distinct data class from entities.** No CDC, no
webhooks, no SyncToken, no pagination, non-deterministic column layout across
minor versions. They get their own normalization layer and their own staleness
rule (time-based, not event-based). (§2, §4)

**D7 — The first vertical slice's write path is gated on a single unverified
fact** (whether `Purchase` supports `?operation=void`). Both branches are
specified. If void is unsupported, the slice ships with `resolution: manual_qbo`
rather than falling back to hard delete. (§11)

---

## What Phase 1 looks like if you approve this

Ordered to match the spec's Build Order, with the gate conditions made explicit.

| Step | Work | Gate to exit |
|---|---|---|
| 1.0 | Repo skeleton, module boundaries, lint rule enforcing `/core` ⊅ `/integrations` | Boundary violation fails CI |
| 1.1 | Capability spike harness + sandbox seeding | ≥ 80% of matrix rows flipped to VERIFIED or DISPROVEN |
| 1.2 | Thin backend: OAuth, session, operation catalog (read ops only) | Health check green from desktop; no secret in the client bundle |
| 1.3 | Both Connection Pages | A revoked token turns the row red within one health check |
| 1.4 | Read-only sync: accounts, vendors, purchases, bills + CDC + pagination | Full sync of seeded sandbox reproducible byte-for-byte |
| 1.4a | **Webhooks: deferred by owner decision (2026-08).** Ship CDC-polling-only first; add the webhook receiver later as a latency optimization once polling sync is working. This was already the architecture's correctness path (§2, row C4) — polling alone must produce correct results — so deferring the receiver changes nothing structural, only latency. | Not a gate; revisit after 1.4 is stable |
| 1.5 | Normalized model + Tier 1 parsers + cross-foot | Same rule produces identical findings from API and CSV of the same data |
| 1.6 | Vertical slice (§11) | Duplicate detected → approved → sandbox void → log entry, with a forced-timeout test passing |

Steps 1.1 and 1.2 can run in parallel. 1.5 must not start before the
normalization contract in §4 is reviewed, because everything downstream is
shaped by it.

---

## Deliberate omissions

Things I did *not* design in Phase 0, and why:

- **Voice / Whisper layer.** Spec puts it last (Build Order §12). Designing it now
  would be speculative against a UI that doesn't exist.
- **SwiftUI view hierarchy.** Out of scope per the prompt. §6 and §7 constrain it
  (page states, scope injection); the rest is Phase 2.
- **Xero adapter.** §4's normalized model is the entire preparation required. No
  Xero-specific work belongs in Phase 0 beyond not painting ourselves into a
  QBO-shaped corner, which §4 addresses.
- **Firm Cockpit, Client Memory, Training Mode, Close Package.** Classified in
  `CAPABILITY_CLASSIFICATION.md` but not designed — they compose over the
  primitives in §5–§10 and add no new architectural risk.
