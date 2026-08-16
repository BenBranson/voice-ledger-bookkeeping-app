# Voice Ledger — UI Architecture

The application shell, navigation, page templates, and component inventory.
Captured from the 2026-08 brief, reconciled against `CLAUDE.md`,
`docs/VOICE_LEDGER_SPEC.md`, and the Phase 0 architecture.

**Nothing in this document is built yet.** Design tokens exist
(`desktop/Sources/DesignSystem/`); everything below is Phase 1 step 1.3+,
which is gated behind step 1.2's exit criteria and not approved.

---

## 1. The through-line the interface must communicate

```
DATA SOURCE → VERIFICATION → DETERMINISTIC CHECK → FINDING → HUMAN REVIEW
  → STAGED CORRECTION → QBO HANDOFF/WRITE → ACTIVITY RECORD → CLOSE PACKAGE
```

Every screen should make clear where in this chain the user is standing, and
what is still unproven behind them.

---

## 2. Application shell

Native structure: `NavigationSplitView` (sidebar + detail), with a custom
toolbar for the global context bar.

### 2.1 Global context bar (always visible)

| Element | Component | Notes |
|---|---|---|
| Active client | `ClientPeriodPin` | Wrong-Client Protection — pinned to every screen |
| Accounting period | `ClientPeriodPin` | Same component |
| Environment | `VLEnvironmentBadge` ✅ built | Striped SANDBOX / solid PRODUCTION |
| Access mode | `ReadOnlyModeBadge` | Read-Only = calm teal shield (the safe default) |
| Last successful sync | `FreshnessIndicator` | Relative + absolute on hover |
| QBO connection health | `VLStatusPill` ✅ built | Live check, never cached |
| Local/privacy status | `ProvenanceChip` | Factual only |
| **Unresolved write alert** | `UnresolvedWriteIndicator` | **Gap 1** — persistent, blocking, impossible to miss |
| Global search | Native search field | |
| Voice control | `VoiceCommandControl` | Small, persistent, state-bearing |
| User menu | Native menu | |

### 2.2 Left navigation

```
COMMAND
  Firm Cockpit · Next Best Action · Universal Findings

MONTHLY CLOSE                          ← rendered as the progress spine
  1. Access & Evidence          8. Balance Sheet Integrity
  2. Scope & Period Lock        9. Sales Tax Review
  3. File Health Scan          10. Tax Estimates
  4. Bank Feed Cleanup         11. Month-End Close
  5. Reconciliation            12. Reporting
  6. Chart of Accounts
  7. Batch Fixes

OPERATIONS
  Universal Ingestion · Staged Corrections · Client Questions
  Client Memory · Activity & Correction Log · Report History

SETTINGS
  Client Settings · Detection Settings · Integrations · Security & Privacy
```

Each of the 12 close pages shows its state via `VLStatusPill` — icon **and**
text, never a bare colored dot. Collapsing the sidebar preserves state
indicators and adds tooltips.

### 2.3 Workspace

Page title · purpose statement · `PageTypeBadge` · `VLCoverageStrip` ·
work area · optional right-side evidence panel · docked `AskClaudePanel`.

Desktop-first: assumes this app owns one monitor while QBO owns the other.
"Open in QBO" handoffs must be findable without covering working data.

---

## 3. Page-type visual system

| Type | Accent | Icon | Carries |
|---|---|---|---|
| **A — API-Driven** | Cyan / electric blue | connected nodes | Live sync, last checked, coverage, rules run, staged actions |
| **B — Import-Driven** | Teal | upload / document | Import freshness, filename, extraction method + confidence, coverage, cross-foot result, "Get this file from QBO" panel |
| **C — Guided Manual** | Blue-gray outline + restrained violet | checklist | QBO steps, pitfalls, definition of done, confirmation + notes + timestamp + person, "Open in QBO" |

Hybrid pages show **two badges** (e.g. `API-Driven` + `Guided Manual`). Never
blend into an ambiguous third color.

---

## 4. Workflow page template

1. Page-type + capability badges
2. `VLCoverageStrip` — DATA AVAILABLE · CHECKS COMPLETED · EXCEPTIONS FOUND
3. What was checked
4. What passed
5. What needs review
6. Findings + evidence (`FindingCard`)
7. Recommended solutions + consequences
8. Actions: approve / edit / dismiss / ask client
9. Type B: import instructions
10. Type C: QBO procedure
11. Re-run checks · completion controls
12. `AskClaudePanel`

**Rule:** if required evidence is missing, section 2 reads "Coverage
incomplete" and the page cannot present as passed. Backed by
`RuleOutcome.cannotEvaluate` (`docs/phase-0/08_RULE_ENGINE.md` §8.1) — this is
not a UI convention that can be forgotten.

---

## 5. FindingCard

Progressive disclosure — quick to read, expandable to full provenance.

- **Header:** severity icon + label · title · dollar exposure · status · assignee
- **Classification:** severity · confidence · workflow status · detection capability · resolution capability
- **Provenance:** data source · filename or sync time · extraction method · extraction confidence · coverage · cross-foot · rule ID + version
- **Body:** plain-English explanation · evidence · affected transactions · risk if ignored · recommended actions · consequences
- **Footer:** review · approve · edit · dismiss · ask client · ask Claude · view in QBO

**Severity, confidence, and status stay visibly separate.** Never compressed
into a single "risk score" — they are three independent axes
(`docs/phase-0/05_FINDING_SCHEMA.md` §5.3).

**Capability-gated actions:** a fix depending on an `ASSUMED` capability row
renders unavailable, citing the row (`05` §5.2 `capabilityUnverified`).

---

## 6. Staged Corrections

Before/after diff: BEFORE on neutral navy, AFTER with restrained cyan outline,
removed values in coral, added in teal.

**Green is not used for the proposed after-state** until the write has
succeeded and verification completed. (The brief's own rule; correct and
consistent with §3 of the design system.)

### The `UNKNOWN` state — Gap 1

Per `docs/phase-0/10_STAGING_APPROVAL_AUDIT.md` §10.6:

- Renders as a **blocking banner** on the affected page — not a subtle badge
- Persistent indicator in the global context bar
- States plainly: submitted, outcome unknown, entity locked pending probe
- Offers **"Run resolution probe"** — never "Retry"
- If the probe returns `AMBIGUOUS`, shows both snapshots side by side and
  escalates to the user. Never guesses.

Write confirmation is an explicit visible gate. Voice may navigate to it and
prepare it; voice may never activate it.

---

## 7. AI-off state — Gap 2

Every AI-touching surface needs a defined appearance with the kill switch on:

| Surface | AI off |
|---|---|
| `AskClaudePanel` | Collapsed, disabled, states why. Not hidden — hiding it would obscure that a capability exists. |
| Finding explanation | Deterministic template renders instead. `GeneratedProse` is `Optional` precisely so this works (`05` §5.1). |
| Report commentary | Omitted; figures and tables unchanged. |
| Ingestion Tier 3 | Unavailable. Documents needing it are honestly unprocessable — never silently degraded to a worse tier. |
| Client Question Builder | Manual composition; no draft. |

Severity, dollar exposure, evidence, and proposed actions must be **byte
identical** with AI on or off — that's the test in
`docs/phase-0/12_TEST_STRATEGY.md` §12.8.

---

## 8. Page-specific layouts

- **Firm Cockpit** — attention metrics row + client table. Every metric leads
  to an action; no decorative charts. Selected client gets cyan edge glow;
  urgent clients get a red alert icon + label, **not** a red glow around the
  whole card.
- **Next Best Action** — one focused command card: what, why now, client,
  exposure, blockers, start button.
- **Bank Feed Cleanup** — three columns (statement · posted ledger ·
  findings). Connector lines only for the *selected* match. Must not imply
  visibility into QBO's For Review queue unless a screenshot was imported.
- **Reconciliation** — statement vs. ledger summaries, precise difference
  indicator. No statement → "Coverage incomplete. Import a statement or
  complete reconciliation in QBO." Then a guided QBO checklist, since we
  cannot execute Finish/Undo.
- **Balance Sheet Integrity** — modules: cash, undeposited funds, clearing,
  assets, liabilities, loans, equity, suspense. Compact balance cards +
  variance charts + drill-down. No pie charts.
- **Batch Fixes** — SELECT → REVIEW → PREVIEW IMPACT → APPROVE → WRITE →
  VERIFY. Must not resemble one-click automation.
- **Month-End Close** — dependency-aware timeline. Upstream change →
  downstream returns to "Revalidation required," green check removed. Driven
  by evidence watermarks (`06` §6.3), not manual invalidation.
- **Reporting** — restrained executive treatment. **The client-facing PDF must
  not look like a cybersecurity infographic.**

---

## 9. Narrow-width fallbacks (open item)

Three-column layouts need a defined behavior below ~1200pt. Proposal: collapse
to a two-pane master/detail, with the third column as a slide-over. Needs a
decision before those pages are built.

---

## 10. Component inventory

✅ = built. Everything else is 1.3+.

| Component | Status |
|---|---|
| `VLColor` / `VLTypography` / `VLSpacing` / `VLRadius` / `VLMotion` | ✅ |
| `VLStatus` / `VLCoverageGap` / `VLEnvironmentTone` / `VLAccessMode` | ✅ |
| `VLStatusPill` | ✅ |
| `VLEnvironmentBadge` | ✅ |
| `VLCard` | ✅ |
| `VLCoverageStrip` | ✅ |
| `AppShell` · `GlobalContextBar` · `ClientPeriodPin` · `ReadOnlyModeBadge` | — |
| `WorkflowProgressSpine` · `PageTypeBadge` · `CapabilityBadge` | — |
| `FreshnessIndicator` · `ProvenanceChip` | — |
| `FindingCard` · `EvidencePanel` · `FindingActionBar` | — |
| `SourceViewer` · `ExtractedDataTable` · `CrossFootValidation` | — |
| `QBOHandoffCard` · `GuidedChecklist` | — |
| `BeforeAfterDiff` · `WriteConfirmationGate` · `UnresolvedWriteIndicator` | — |
| `ClientQuestionPanel` · `AskClaudePanel` · `ActivityTimeline` | — |
| `VoiceCommandControl` | — |
| `EmptyState` · `ErrorState` · `SkeletonLoader` | — |
