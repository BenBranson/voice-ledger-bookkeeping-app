# 12. Test Strategy Using the QBO Sandbox

Including the mechanism that turns §2's `ASSUMED` rows into `VERIFIED` — which is
the part that makes `CLAUDE.md` rule 6 enforceable rather than aspirational.

---

## 12.1 Five test tiers

| Tier | Runs | Network | Speed | Gates |
|---|---|---|---|---|
| **T0 — Structural** | Every commit | none | instant | Architecture invariants |
| **T1 — Unit / rules** | Every commit | none | seconds | `/core` correctness |
| **T2 — Contract** | Every commit | replayed fixtures | seconds | Normalization |
| **T3 — Capability spike** | On demand + weekly | **live sandbox** | minutes | §2's matrix |
| **T4 — Integration** | On demand + pre-release | **live sandbox** | minutes | End to end |

T0–T2 are the CI gate. T3–T4 need credentials and a live sandbox, so they run on
demand and on a schedule — but T3's *results* gate feature work through the
matrix.

---

## 12.2 T0 — structural tests

Tests that assert the architecture, so a violation fails a build rather than
surviving until someone notices in review.

1. **`/core` imports nothing from `/integrations`** — source-level scan.
   `CLAUDE.md`, Architecture boundaries.
2. **Exactly one construction site for `FindingColor.green`**, at §5.7's guarded
   derivation.
3. **`ResolutionCapability.automaticAPI` is never constructed** (§5.2).
4. **No `markStale` function exists** — staleness is derived (§6.3, D3).
5. **`LedgerRepository` exposes no method taking a `RealmID`** (§7.8 test 2).
6. **No untyped logging API in the backend** (§3.5).
7. **Every `Rule` in the registry has a non-empty `accountingPrinciple`** (§8.2).
8. **Every rule has at least one `.cannotEvaluate` golden fixture** (§8.7).
9. **`Scoped.rebind` appears in no production target** (§7.3).
10. **No `Double` in any type under `/core`'s money paths** (§4, M1).

These are cheap, they run in milliseconds, and each one guards a decision that
would otherwise erode silently over months.

---

## 12.3 T1 — rule unit tests

Per §8.7: golden fixtures, property tests, and the regression corpus. No network,
fully deterministic, and a rule cannot merge without them.

The property test that matters most is **source equivalence** — the same data via
API and via CSV yields the same findings modulo provenance. That is §4.1's
contract, and it is the assertion that keeps Type B pages from quietly becoming a
parallel codebase.

---

## 12.4 T2 — contract tests

Recorded, sanitized QBO responses replayed through the normalization layer.

- Fixtures are **captured by T3**, never hand-written. A hand-written fixture
  tests our idea of the API, which is precisely the thing that's wrong.
- Sanitization strips tokens and replaces real identifiers; amounts and structure
  are preserved because they're what's under test.
- Every fixture records the **minor version** it was captured under (§2.7). A
  fixture is only valid for its version.
- **A T2 fixture that no longer matches live sandbox behavior is a T3 failure**,
  not a T2 one — the contract changed, and the matrix must reflect it.

---

## 12.5 T3 — the capability spike suite ⭐

**The mechanism that makes §2's matrix trustworthy.**

### The rule
**§2's matrix is generated from T3 test results. It is not hand-edited.**

Each matrix row has a corresponding test. The test asserts the behavior the row
claims. The generator emits the matrix from the test run:

- Test passed → row is `VERIFIED (<date>)`
- Test failed → row is `DISPROVEN` and every dependent feature is blocked
- Test not written → row stays `ASSUMED`
- Test not run within the staleness window → row reverts to `STALE`

A human cannot promote a row to VERIFIED by typing. That is the point.

### Test shape

```swift
@CapabilityTest(row: "7.1", claim: "Purchase supports sparse update of line AccountRef")
func testPurchaseSparseUpdateAccountRef() async throws {
    let purchase = try await sandbox.seed.purchase(amount: 100, account: .officeSupplies)

    let response = try await capture {                    // records request + response
        try await sandbox.sparseUpdate(purchase, lineAccountRef: .utilities)
    }

    #expect(response.status == 200)
    let reread = try await sandbox.read(Purchase.self, id: purchase.id)
    #expect(reread.line(0).accountRef == .utilities)
    #expect(reread.syncToken == purchase.syncToken.incremented)

    // The claim that actually matters: sparse did not clear anything else.
    #expect(reread.privateNote == purchase.privateNote)
    #expect(reread.docNumber  == purchase.docNumber)
    #expect(reread.memo       == purchase.memo)

    try capture.emitFixture(named: "purchase-sparse-update-accountref")
}
```

Note the last three assertions. The interesting question is not "did the update
succeed" — it is **"did anything else get destroyed"** (§2 row 7.1, constraint 2).
A capability test that only asserts the happy path documents nothing useful.

### Negative capability tests
Absences need recording too (§2.8, Wave 2):

```swift
@CapabilityTest(row: "5.3", claim: "No API surface returns reconciliation history")
func testReconciliationHistoryUnavailable() async throws {
    try await sandbox.completeReconciliationManually()   // documented manual setup
    let attempts = try await sandbox.probeForReconciliationData()
    #expect(attempts.allSatisfy { $0.foundNothing })
    try capture.emitNegativeEvidence(searched: attempts.map(\.description))
}
```

This records **what was searched**, so a future reader knows whether the absence
was established or assumed — and so that when Intuit ships the endpoint, we can
tell what we looked for last time.

### Staleness window
`VERIFIED` expires after **90 days**. The weekly scheduled T3 run refreshes it.
An expired row reverts to `STALE` and its dependent features surface
`ResolutionConstraint.capabilityUnverified` in the UI (§5.2). An API that changed
under us shows up as a matrix regression, not a production surprise.

---

## 12.6 Sandbox management

### Seeding
A deterministic seeding harness — not manual data entry, and not a one-time
snapshot. Manually-seeded sandboxes drift and become unreproducible, at which
point every test failure is ambiguous.

```
Seeds/
  baseline.json          COA, vendors, opening balances
  duplicates.json        exact / near / legitimate-recurring cases (§11)
  reconciliation.json    matched, unmatched, partially cleared
  closed-period.json     transactions before and after a close date
  edge-cases.json        zero amounts, very large, multi-line, linked txns
```

Properties:
- **Idempotent** — re-seeding produces the same state, not duplicates.
- **Versioned** — a seed change is a code change with a diff.
- **Teardown** — hard cleanup between suites so residue can't create phantom
  duplicates that make `VL-DUP-EXP-001` look right for the wrong reason.

### Multiple sandboxes
At least two, ideally three:
1. **Spike sandbox** — T3 lives here; state is dirty by nature.
2. **Slice sandbox** — clean, seeded, T4's home.
3. **Isolation sandbox** — a second realm with deliberately similar data, for
   §7.8's cross-client tests. This one is not optional: isolation cannot be
   tested with one client.

### Sandbox-specific setup that must be documented
Some Wave 4 rows need state you can only create by hand in the QBO UI: a set
closing date (with and without password), a completed reconciliation, a
configured sales-tax mode, a populated For Review queue. **Write the procedure
down as a checked-in runbook**, because it will be needed again on a fresh
sandbox and it will not be remembered.

---

## 12.7 T4 — integration tests

End-to-end against a live sandbox. §11.5's acceptance criteria are the first T4
suite.

**Failure injection is mandatory, not optional.** Specifically:
- Timeout after send (both landed and not-landed variants)
- Process kill between journal write and network call
- `SyncToken` mutated externally between read and write
- 429 with `Retry-After`
- Refresh token revoked mid-operation
- Pagination checksum mismatch

These paths are the ones that matter and the ones nobody exercises by accident.
§10's entire design is untested without them, and §10 is the part of the system
whose failure would corrupt real client books.

---

## 12.8 Cross-cutting suites

### The kill-switch suite
Run the **entire** T1 + T4 deterministic suite with AI disabled. Every finding,
severity, dollar figure, evidence item, and proposed action must be **byte
identical** to the AI-enabled run. Only `GeneratedProse` fields differ (present
vs. `nil`).

This is the proof that `CLAUDE.md` rule 1 and the spec's kill-switch guarantee
are real. It is worth running regularly for exactly that reason (spec).

### The production-safety suite
1. Attempt a production-classed write with the deployment flag unset → refused.
2. Assert no development or CI configuration contains production credentials.
3. Assert the sandbox/production badge renders differently — a snapshot test, so
   "visually unmistakable" is checked, not assumed.

`CLAUDE.md` rule 7, made mechanical.

### The green-audit suite
For every page, enumerate every way it can reach `.green` and assert each path
satisfies all four conditions (data present, check completed, result current, no
exception). Then, for each page, assert green is **unreachable** with: no data ·
partial coverage · stale data · unhealthy connection · a `.cannotEvaluate` check ·
a failed cross-foot · a screenshot source with no stated total.

`CLAUDE.md` rule 5 is the rule most likely to be violated by accident, because
violating it requires no bad intent — just a forgotten case. This suite is what
catches that.

### The log-hygiene suite
§3.5's canary test: run a full write path with distinctive values
(`$13579.24`, vendor `ZZCANARYVENDOR`, a synthetic token) and assert none appear
in captured backend log output.

---

## 12.9 What is not tested, and why

- **QBO's own correctness.** We test our interaction with it, not it.
- **UI layout beyond the environment badge.** Snapshot-testing SwiftUI broadly
  produces churn without catching bugs. The badge is tested because it is a
  safety control, not a design detail.
- **Whisper accuracy.** Voice is last (Build Order §12); its tests come with it.
- **Claude's prose quality.** Not testable deterministically, and not
  safety-critical by design — the `citedValues` check (§5.8) tests the property
  that *is* safety-critical: no uncomputed number can render.

---

## 12.10 CI configuration

```
on: every commit
  T0 structural
  T1 unit / rules
  T2 contract
  kill-switch suite (T1 subset)
  green-audit suite
  build

on: schedule (weekly) + manual
  T3 capability spike   → regenerates docs/phase-0/02_QBO_CAPABILITY_MATRIX.md
  T4 integration
  log-hygiene suite
  production-safety suite

on: pre-release
  everything, plus failure injection
```

**The weekly T3 run regenerating the matrix is the heart of this strategy.** The
matrix stops being a document someone maintains and becomes a build artifact that
reflects reality on a known date. When it changes, the diff shows exactly which
QBO behavior moved — and the features depending on that row are blocked
automatically rather than discovered broken.
