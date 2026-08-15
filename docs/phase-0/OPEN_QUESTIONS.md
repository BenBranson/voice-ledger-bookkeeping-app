# Open Questions

Answered 2026-08 in `PHASE_0_ANSWERS.md`. Status per question below; the two
still open are placeholders the owner left for themselves to fill in, not
decisions I'm waiting on.

---

## Q1 — Prototype repo — **still open (placeholder unfilled)**

The answers doc left `[FILL IN: paste your GitHub URL or local path here.]`
unfilled. Deliverable 1 ([01_REPO_INVENTORY.md](01_REPO_INVENTORY.md)) stays
blocked until the path or URL is supplied.

**Scope confirmed for when it arrives:** conceptual reference only, near-zero
code reuse expected. Priority is section D of the original outline — capability
claims to re-verify. Prototype-observed QBO behavior enters §2's matrix as
`ASSUMED (prototype-observed)` and gets priority in the spike queue (see
`SPIKE_QUEUE.md`). Sections A–C should stay thin rather than padded if the
builder output turns out to be mostly scaffolding.

---

## Q2 — Backend hosting — **resolved**

**A small managed container.** Cost matters more than scale — one operator, tens
of clients.

**Webhooks deferred by explicit decision.** Ship CDC-polling-only first; add the
webhook receiver later as a latency optimization, not a launch blocker. Reflected
in `00_OVERVIEW.md`'s Build Order (step 1.4a) and consistent with §2 row C4,
which already specified polling as the correctness path regardless of webhook
status.

---

## Q3 — Single operator — **resolved**

**Confirmed single operator.** The design stops hedging on this.

Multi-operator (likely offshore staff, eventually) is explicitly deferred as its
own future design pass — not pre-built, not designed around. The five specific
mechanisms that would need revisiting when that phase starts are now recorded in
[07_CLIENT_ISOLATION.md §7.9](07_CLIENT_ISOLATION.md#79-single-operator--confirmed-and-where-multi-operator-would-bite-owner-decision-2026-08):
`ApprovalRecord.approvedBy`, `ClientScopeRegistry`'s one-scope-per-realm
assumption, per-entity write serialization, the backend's realm-only (not
realm+role) session model, and `ActivityLogEntry.actor`'s single-identity
attribution.

---

## Q4 — Minimum macOS version — **still open (needs the owner to check About This Mac)**

**Target macOS 15+, provisionally confirmed** — the `RecognizeDocumentsRequest`
gap is material (§9, Tier 2): worse table extraction means more Tier 3
escalations, which means more client documents leaving the Mac, which is the
wrong direction on the one privacy property the import path provides.

Still needs the actual installed OS version checked (Apple menu → About This
Mac) to confirm the target isn't ahead of the dev machine. If it turns out to be
macOS 14, Tier 2 is designed with the `VNRecognizeTextRequest` + bounding-box
clustering fallback from the start rather than assuming 15+ and retrofitting.

---

## Q5 — Locale and sales tax mode — **resolved**

**US only. Automated Sales Tax only.** Page 9 is scoped to AST exclusively;
legacy manual-tax mode and non-US locales are classified `.unsupported` —
**gated, not merely untested.** Mode detection runs first against
`Preferences`; if it resolves to legacy tax, Page 9 returns
`.cannotEvaluate(.featureNotEnabled("Automated Sales Tax"))` rather than
attempting AST-shaped rules against the wrong mode. Reflected in
[02_QBO_CAPABILITY_MATRIX.md §9.1/9.3](02_QBO_CAPABILITY_MATRIX.md) and
[CAPABILITY_CLASSIFICATION.md Page 9](CAPABILITY_CLASSIFICATION.md).

---

## Q6 — Client count — **resolved**

**Tens, not hundreds.** Confirmed — currently zero clients, building ahead of
the first one. Firm Cockpit fan-out (§7.1) is sized for this; no summary cache
until there's a measured reason for one.

---

## Q7 — Materiality defaults — **resolved**

**$25 flat absolute floor, no percentage-of-revenue component.** Reasoning: this
is bookkeeping cleanup, not audit — a revenue-scaled floor would suppress small
duplicates on larger clients, which is backwards for the tool's purpose.

**Cash and clearing accounts get a tighter `accountOverrides` floor** (near
zero) — a small unexplained difference there usually signals a structural
problem, not rounding. Editable per client from the UI in Phase 1, with every
change recorded in the activity log (materiality is a watermark component —
§6.3, §8.6 — so this was already required, not new work). Reflected in
[08_RULE_ENGINE.md §8.6](08_RULE_ENGINE.md).

---

## Q8 — Cross-account duplicates — **resolved**

**`VL-DUP-EXP-001` stays same-payment-account only**, keeping the vertical slice
narrow. **New rule added to the backlog:** `VL-DUP-EXP-002` — cross-account
duplicate candidate, same vendor/amount/near-date, different payment account,
`.medium` confidence at best, Phase 2. Different false-positive profile,
separate fixtures, separate tuning — not folded into the slice. Reflected in
[08_RULE_ENGINE.md §8.8](08_RULE_ENGINE.md).

---

## Q9 — Phase 0 reading — **resolved**

Confirmed correct: stop at the plan, no Phase 1 implementation until explicit
approval.

---

## Git — done

```bash
git init
# .gitignore added first — excludes anything credential-shaped
# (tokens, keys, secrets, .env*, keychain files, unsanitized capture artifacts)
git add -A && git commit -m "Phase 0: spec, constraints, architecture plan"
```

Per the answers doc: *"I want it impossible to commit a token by accident, not
merely unlikely."* The `.gitignore` pattern set is deliberately broad (matches
`*secret*`, `*token*`, `*credential*`, `*apikey*` case-insensitively) rather than
enumerating exact filenames, because an enumerated list is exactly the kind of
thing that misses the one file that matters.

---

## What's next

1. **Deliverable 1** — blocked on Q1's repo path.
2. **The spike queue** — see [SPIKE_QUEUE.md](SPIKE_QUEUE.md). Ordered, runnable,
   `Purchase` void (§11.1's gate) first.

Then: Phase 1 approval, step by step against the gate table in
[00_OVERVIEW.md](00_OVERVIEW.md).
