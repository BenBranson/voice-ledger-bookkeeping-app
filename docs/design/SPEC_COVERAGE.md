# Spec Coverage Check

*"before we proceed i just want to show you what the app should have... make
sure we have all of this."*

This checks the full spec (`docs/VOICE_LEDGER_SPEC.md`) **and** the UI
architecture brief supplied 2026-08 against what Phase 0 actually documented.

**Headline: the accounting architecture is covered. The UI architecture brief
added real material Phase 0 didn't have, and it exposed two genuine gaps in my
own design.**

Note on method: Phase 0's twelve documents were written *from* this spec, so
coverage of the spec itself should be — and is — high. The interesting part is
the second column.

---

## 1. Spec → Phase 0 coverage

| Spec section | Covered in | Status |
|---|---|---|
| Operating model, three page types | `CAPABILITY_CLASSIFICATION.md` | ✅ |
| Universal Ingestion, 3 tiers | `09_INGESTION_PIPELINE.md` | ✅ |
| Cross-foot validation | `09` §9.5 | ✅ |
| Extraction verification UI | `09` §9.6 | ✅ |
| Screenshot partial coverage | `09` §9.7 | ✅ |
| Ask Claude panel + guardrails | `03` §3.6, `05` §5.8 | ✅ |
| Thin backend / security | `03_SECURITY_THREAT_MODEL.md` | ✅ |
| No read-only OAuth scope | `03` §3.4, `10` §10.4 | ✅ |
| Core layer boundaries | `04_DATA_MODEL.md`, enforced by lint | ✅ |
| Multi-client / realmId isolation | `07_CLIENT_ISOLATION.md` | ✅ |
| Sync architecture, CDC, webhooks | `02` rows C4/C5 | ✅ |
| Universal Finding Record | `05_FINDING_SCHEMA.md` | ✅ |
| Color/severity/confidence/status | `05` §5.3, §5.7 | ✅ |
| Green ≠ "nothing found" | `05` §5.7, `08` §8.1 | ✅ |
| Page structure (9 elements) | `06_PERIOD_STATE_MACHINE.md` | ✅ |
| Connection pages | `02` row C1, `12` §12.8 | ✅ |
| All 12 workflow pages | `02`, `CAPABILITY_CLASSIFICATION.md` | ✅ |
| Firm Cockpit, Next Best Action | `CAPABILITY_CLASSIFICATION.md` | ⚠️ classified, not designed |
| Client Memory with approval | `09` §9.9, `08` §8.5 | ✅ |
| Client Question Builder | `05` §5.5 | ✅ |
| Close Package | `CAPABILITY_CLASSIFICATION.md` | ⚠️ classified, not designed |
| Training Mode | `08` §8.2 (`accountingPrinciple`) | ✅ |
| Voice guardrails | `CAPABILITY_CLASSIFICATION.md` | ✅ |
| Wrong-Client Protection | `07` §7.5 | ✅ |
| Activity & Correction Log | `10` §10.8 | ✅ |
| Rules engine vs. Claude | `08_RULE_ENGINE.md` | ✅ |
| Build order | `00_OVERVIEW.md` | ✅ |
| Capability spike checklist | `02` §2.8, `SPIKE_QUEUE.md` | ✅ |
| Out of scope items | `CAPABILITY_CLASSIFICATION.md` | ✅ |
| Reference Findings Library | `08` §8.8 (27 rules) | ✅ |

The ⚠️ items are *classified and scoped* but have no detailed design. That's
correct sequencing — they compose over primitives from `05`–`10` and add no
new architectural risk. They need design before they're built, not before now.

---

## 2. What the UI brief ADDED (new, valuable, now captured)

Material genuinely not in Phase 0, now recorded in `UI_ARCHITECTURE.md`:

1. **Three-level context system** — global bar / left nav / workspace
2. **Navigation grouping** — COMMAND / MONTHLY CLOSE / OPERATIONS / SETTINGS
3. **Workflow progress spine** — 12 pages as a compact always-visible state strip
4. **Page-type visual treatments** — Type A cyan/blue, Type B teal, Type C blue-gray+violet
5. **Three-column status strip** — DATA AVAILABLE · CHECKS COMPLETED · EXCEPTIONS FOUND.
   This is the best concrete encoding of the green rule I've seen; it's now
   built as `VLCoverageStrip`.
6. **Firm Cockpit metrics** — specific fields, action-oriented
7. **Bank Feed three-column workspace** with selective connector lines
8. **Reconciliation comparison layout** with precise difference indicator
9. **Balance Sheet financial-system modules** (cash, undeposited, clearing, …)
10. **Batch Fixes stage sequence** — SELECT → REVIEW → PREVIEW IMPACT → APPROVE → WRITE → VERIFY
11. **Staged Corrections diff rules** — including *"do not use green for the
    proposed after-state until the write has actually succeeded"*, which is an
    excellent catch and is exactly consistent with the green rule
12. **Reporting restraint** — client PDF must not look like a cybersecurity infographic
13. **Voice interface states** — idle / listening / processing / understood / confirm / failed
14. **Provenance trust chips** — factual, tied to real state
15. **29-component inventory**

---

## 3. Two real gaps the brief did NOT account for ⚠️

These are the findings worth your attention. Both are states the UI must have
and the brief has no place for.

### Gap 1 — the `UNKNOWN` write state

`docs/phase-0/10_STAGING_APPROVAL_AUDIT.md` §10.6 defines the case where a
write was submitted and **we do not know whether it landed** (timeout, network
drop, crash after send). It is a persisted, first-class state that blocks
further writes to the affected entity until a resolution probe settles it.

The brief's Staged Corrections section covers approved → written → verified.
It has no visual for "submitted, outcome unknown, do not touch this entity."

**Why it matters:** this is the single most dangerous state in the app. A
retry here double-voids a transaction. It needs to be *impossible to miss* —
not a subtle badge. Added as `VLCoverageGap.unresolvedWrite`, and
`UI_ARCHITECTURE.md` specifies it as a blocking banner on the affected page
plus a persistent global-bar indicator.

### Gap 2 — the AI kill switch

The spec requires a single toggle disabling all AI features app-wide, with
every deterministic rule, finding, calculation, and report still working
(`docs/VOICE_LEDGER_SPEC.md`, Claude API Connection; `03` §3.6 item 5).

The brief designs the Ask Claude panel but never mentions its disabled state —
nor what happens to finding explanations, report commentary, or Tier 3
ingestion escalation when AI is off.

**Why it matters:** the kill switch is the proof that "code computes, Claude
explains" is real rather than aspirational. If the UI degrades badly with AI
off, nobody will ever turn it off, and the guarantee becomes theoretical.
`UI_ARCHITECTURE.md` now specifies the AI-off state for every AI-touching
surface.

---

## 4. Smaller items to keep in view

| Item | Note |
|---|---|
| **`capabilityUnverified` rendering** | `05` §5.2 — a finding whose fix depends on an `ASSUMED` matrix row must render the action unavailable *citing the row*. The brief's `CapabilityBadge` can carry this; make sure it does. |
| **Report History / Detection Settings / Security & Privacy** | New nav items not in the original spec. Reasonable additions; no architecture impact. |
| **Type C "Open in QBO"** | Brief makes this the primary handoff action. macOS: opens the default browser to a deep link. Worth spiking whether QBO deep links land on the right entity. |
| **Three-column layouts** | Bank Feed and Reconciliation assume wide screens. Need a defined narrow-width fallback — the brief says "when screen width allows" but doesn't say what happens otherwise. |
| **Contrast unmeasured** | `DESIGN_SYSTEM.md` §9. `textMuted` on `surfaceCard` is the risky pair. |

---

## 5. Conclusion

Nothing in the spec is missing from the architecture. The UI brief is
substantially richer than Phase 0's UI thinking was, and it's now captured.
The two gaps above are mine, not yours — they're states my own design
documented and my own UI planning would have missed.
