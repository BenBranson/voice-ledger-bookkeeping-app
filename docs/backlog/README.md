# Backlog

Filed, not planned. Nothing in this directory is scoped into a phase beyond
the reserved rule IDs in `docs/phase-0/08_RULE_ENGINE.md` §8.8. Per owner
instruction 2026-08-16 (`NEXT_INSTRUCTION.md` Part 4): treat these as backlog,
not as the plan, and leave them alone until the vertical slice (Phase 1 step
1.6) and the Cleanup Assessment ship.

- **`CLEANUP_MODE.md`** — the Cleanup Assessment page (Type A, read-only,
  highest near-term business value per this doc and independently per
  `REDDIT_FEEDBACK_ASSESSMENT.md`), five new cleanup-detection rules, the
  reconciliation gap map, paper-client handling via the Import Bridge.
- **`REDDIT_FEEDBACK_ASSESSMENT.md`** — Transaction Relationship Guard
  (`VL-RELATIONSHIP-001`…`-006`, the source for §8.2a's relationship-before-
  category gating design), many-to-one/one-to-many statement matching (the
  source for the matching-contract design in
  `docs/phase-0/09_INGESTION_PIPELINE.md` §9.11), Account-Month Control Grid,
  Client Accounting Control Profile, balance-sheet evidence workpapers,
  sensitive-write preflight risk tiers, Client Exception Packet,
  changed-after-close detection (`VL-CLOSED-PERIOD-DRIFT-001`),
  forced-reconciliation/OBE detection (`VL-FORCED-RECON-001`,
  `VL-OBE-BALANCE-001`), auto-add bank rule detection
  (`VL-AUTOADD-RULE-001`).
- **`STRATEGY_MERIDIAN.md`** — competitive/market context (Meridian, QBO 2026's
  Intuit Intelligence). No build implications; informs positioning only.

All new rule IDs from the first two documents are reserved in
`docs/phase-0/08_RULE_ENGINE.md` §8.8's backlog table, with phase assignments
and one-line detection summaries. Two spike items were pulled forward from
these documents into `docs/phase-0/SPIKE_QUEUE.md` as tests-only, not run yet:
`testCategorizationProvenance` and `testReconciledTransactionDetection`.
