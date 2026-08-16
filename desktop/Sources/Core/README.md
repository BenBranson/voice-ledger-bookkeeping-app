# Core — Phase 1, step 1.0

This target is deliberately near-empty right now. Phase 1 approval
(`docs/phase-0/SPIKE_REVIEW.md`, if you saved it — otherwise see the approval
recorded in conversation) covers steps 1.0–1.2 only: repo skeleton, the
capability spike harness, and a read-only thin backend. The rules engine
(`docs/phase-0/08_RULE_ENGINE.md`), the full normalized data model
(`docs/phase-0/04_DATA_MODEL.md`), and the Finding schema
(`docs/phase-0/05_FINDING_SCHEMA.md`) are specified in detail but **not yet
implemented** — they belong to later, not-yet-approved build steps (1.5
onward in `docs/phase-0/00_OVERVIEW.md`'s gate table).

What's here now is exactly the two zero-dependency value primitives that
almost everything else in the spec is built from, so they exist once rather
than being redefined per-consumer:

- `Money.swift` — exact money, integer minor units, no floating point
  (§4.3, decision M1)
- `RealmID.swift` — the isolation key (§4.4, §7)

**The one invariant this target exists to protect:** `Core` has zero
dependencies and must never import `IntegrationsQuickBooks`,
`IntegrationsImports`, `Staging`, `Voice`, or `DB`. Enforced by
`Scripts/check-module-boundaries.sh`, run as part of `swift test` via
`Tests/ArchitectureTests/ModuleBoundaryTests.swift`.
