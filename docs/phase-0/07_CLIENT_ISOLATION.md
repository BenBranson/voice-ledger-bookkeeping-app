# 7. Client Isolation Design

`CLAUDE.md` rule 9:

> All data, caches, queues, and logs segregate by QBO `realmId` — never by a
> mutable "current client" variable.

The requirement is that isolation be **structural, not conventional**. A design
where every query must remember `WHERE realm_id = ?` is conventional: it works
until one query forgets, and that one query shows client A's duplicate expenses
on client B's page.

Four mechanisms, layered so that each catches what the others miss.

---

## 7.1 Mechanism 1 — one database per realm (D2)

Physical separation, not a discriminator column.

```
~/Library/Application Support/VoiceLedger/
  app.sqlite                          ← app-level only: connections, prefs, model config
  clients/
    <realmDirectoryName>/
      store.sqlite                    ← ledger cache, findings, staging, activity log
      imports/                        ← original source documents
      cache/                          ← report responses, CDC state
```

**Property gained: a cross-client query is not a missing predicate — it is a
different file.** There is no SQL statement, however malformed, that can return
client B's rows from client A's database. The failure mode is eliminated rather
than guarded against.

Secondary benefits worth having:
- Deleting a client is deleting a directory. Complete, verifiable, no orphans.
- Corruption is contained to one client.
- Backup and retention are per-client.
- `app.sqlite` holds no accounting data at all, so the one shared store is not a
  cross-contamination surface.

`<realmDirectoryName>` is a hash of the `realmId` rather than the raw value —
directory listings shouldn't enumerate client identifiers, and it sidesteps
filesystem-legal-character questions.

**Cost, stated:** no cross-client SQL. The Firm Cockpit needs every client on one
screen, so it must fan out across stores and aggregate in memory. That is more
code than a `GROUP BY`. It is worth it, and the aggregation is over small
summary data (period, close readiness %, urgent count, last sync) — not over
ledger rows.

---

## 7.2 Mechanism 2 — `ClientScope`, and no ambient current client

There is no `AppState.currentClient`. There is no singleton anyone can read.

```swift
/// The sole gateway to one client's data. Owns every per-client resource.
actor ClientScope {
    let realmID: RealmID
    let environment: QBOEnvironment          // .sandbox | .production — immutable
    let accessMode: AccessMode               // .readOnly | .writeEnabled

    private let store: ClientStore
    private let importStore: ImportStore
    private let stagingQueue: StagingQueue
    private let activityLog: ActivityLog
    private let syncEngine: SyncEngine
    private let logger: ScopedLogger

    // Repositories are vended, never constructed elsewhere. Each is bound to
    // this scope's store at creation and has no way to reach another.
    func ledgerRepository() -> LedgerRepository
    func findingRepository() -> FindingRepository
    func stagingRepository() -> StagingRepository
}

actor ClientScopeRegistry {
    /// The only way to obtain a scope. Enforces one live scope per realm.
    func scope(for realmID: RealmID) async throws -> ClientScope
}
```

**Every repository is constructed with a store handle it does not choose.**
`LedgerRepository` has no `realmID` parameter on its methods, because it has no
capacity to serve a different realm — the question cannot be asked.

**`environment` is immutable on the scope.** This is where `CLAUDE.md` rule 7
(never modify production during development) meets the isolation design: sandbox
and production are different realms, therefore different scopes, therefore
different stores. There is no "switch to production" operation that could apply
to in-flight work.

---

## 7.3 Mechanism 3 — phantom-typed values at the boundaries

Mechanisms 1 and 2 protect data at rest and repository access. They do not stop a
value that has *already been read* from client A being handed to a function
operating on client B — the classic leak: a `Finding` from one client passed into
another's staging queue.

```swift
/// A value whose client binding is part of its type.
/// `Scope` is a phantom type; there is no way to convert between bindings
/// except through `rebind`, which is auditable and must never appear in
/// production code (a lint rule enforces that).
struct Scoped<Scope: ClientScopeTag, Value>: Sendable where Value: Sendable {
    let realmID: RealmID
    let value: Value
}
```

With per-client repository interfaces expressed in terms of `Scoped<…>`, passing
client A's finding to client B's staging queue is a **type error**, not a runtime
check that might not run.

**Honest assessment of this mechanism:** phantom types over dynamically-created
scopes require some machinery (existential scope tags, `withScope { }` closures)
and Swift will make it slightly awkward. I would apply it **only at the crossing
points** — staging queue input, activity log writes, and the QBO write path — and
not to every read. Applying it everywhere makes the codebase heavier than the
risk justifies. The write path is where a leak becomes a wrong-client
modification of real books, so that is where the type-level guarantee earns its
cost.

If the machinery proves genuinely unpleasant in Phase 1, the fallback is
Mechanism 4 with an assertion at every crossing point — weaker (runtime, not
compile time), but still structural.

---

## 7.4 Mechanism 4 — runtime assertions at the crossing points

Belt and braces at the four places where a mismatch would matter most:

1. **Staging queue admission.** `stagingQueue.enqueue(_:)` asserts
   `correction.realmID == scope.realmID`. Mismatch → precondition failure in
   debug, hard error and log in release. Never a silent skip.
2. **Backend request construction.** Every catalog operation carries a `realmId`;
   the client asserts it matches the scope, and **the backend independently
   verifies the session is authorized for that realm** (§3.3 item 11). Two checks
   on opposite sides of the network boundary, so neither one alone is trusted.
3. **Activity log writes.** Same assertion. A log entry in the wrong client's log
   corrupts the record that exists to be trustworthy.
4. **Claude fact packets.** Assert every referenced finding shares the scope's
   realm before the packet is built. This is the leak that would be most visible
   and most damaging — client A's vendor names appearing in client B's
   explanation.

---

## 7.5 UI: scope injection without a defaultable environment

SwiftUI's `EnvironmentKey` requires a `defaultValue`, which is exactly the ambient
fallback this design forbids — a view that renders with the default is a view
showing the wrong client.

**Approach:** the active scope is passed as an explicit initializer parameter
down the workflow view hierarchy. The environment carries at most a non-optional
`ClientScopeBox` whose default is `.unbound`, and `.unbound` renders a loud error
state (and traps in debug) rather than falling back to any client.

```swift
enum ClientScopeBox {
    case unbound
    case bound(ClientScope)
}
```

Per spec, **the active company and period are pinned to every screen** —
Wrong-Client Protection. The pinned indicator reads from the injected scope, so a
screen that somehow rendered unbound displays an error, not a stale company name.

The environment badge (SANDBOX / PRODUCTION, visually unmistakable, different
background treatment rather than just a text label) reads from
`scope.environment`, which is immutable — so the badge cannot lag behind a mode
change, because there is no mode to change.

---

## 7.6 Logging

`ScopedLogger` is vended by the scope and stamps `realmID` on every entry.
Per-client log files live inside the client's directory. There is no app-level
logger that accepts accounting data — the app-level logger's typed field set
(§3.5) simply has no case for it.

---

## 7.7 What breaks if a realm changes identity

`realmId` is stable for a company. But two situations deserve explicit handling:

- **Re-authorization of the same realm.** Same directory, same store. The
  connection record updates; data is retained. Must trigger a full resync (§2 C5
  — CDC lookback has certainly lapsed).
- **A sandbox company recreated with a new realmId.** A *new* scope and a *new*
  store. The old one is not silently reused, and the Connection Page shows both
  until you delete the stale one. Silently adopting the old store would mean
  findings computed against data that no longer exists.

---

## 7.8 Testing isolation

Isolation claims must be tested or they are decoration. §12 covers this; the
specific tests:

1. **Two-client fixture test.** Seed two stores with deliberately similar data
   (same vendor names, same amounts, same dates). Run every rule. Assert no
   finding in store A references an ID from store B.
2. **Repository confinement test.** Assert `LedgerRepository` exposes no method
   accepting a `RealmID` — a reflection/API-surface test that fails if someone
   adds one.
3. **Crossing-point assertion tests.** Deliberately attempt each of §7.4's four
   mismatches and assert each fails loudly.
4. **Backend authorization test.** Session bound to realm A requests an operation
   on realm B; assert 403 and assert nothing was forwarded to QBO.
5. **Filesystem test.** After deleting a client, assert no file anywhere under
   Application Support contains that realm's identifier or any of its data.

---

## 7.9 Single operator — confirmed, and where multi-operator would bite (owner decision, 2026-08)

**This entire document is designed for single operator, confirmed.** No
coordination between concurrent users exists or is planned for Phase 1. The
owner expects to bring on help eventually — likely offshore staff — but that is
far enough out that designing for it now would be speculative, and the request
was explicit: don't pre-build coordination, and don't contort the current design
to leave room for it. This section exists so that when it does happen,
multi-operator is a scoped design pass against a known list, not a rediscovery.

**Mechanisms in this document that assume one operator, and what multi-operator
would need to revisit:**

1. **`ApprovalRecord.approvedBy` (§10.2) is a bare string, not an authenticated
   identity with permissions.** Multi-operator needs real user accounts, a
   permission model (can this person approve writes for this client?), and
   probably a distinction between "staged by" and "approved by" that today
   collapses to one person by construction.
2. **`ClientScopeRegistry` enforces one live scope per realm (§7.2), which today
   is trivially true — there's only ever one process.** With two operators
   potentially opening the same client, this becomes a real lock: either
   exclusive access with a visible "in use by X" state, or a concurrency model
   for the scope's actor that doesn't exist today.
3. **Per-entity write serialization (§10.9) is serialized within one process's
   staging queue.** Two operators on two machines could both stage a correction
   against the same entity with no coordination between them — the current
   preflight (§10.3) would catch the resulting `SyncToken` conflict, but only
   *after* the second person did real work drafting a correction that can't land.
   A shared lock or a "someone else is working on this" signal would be needed
   before that becomes acceptable UX.
4. **The backend session model (§3.3) authorizes a session to a realm, not a
   session to a *role* on a realm.** Read-only-for-junior-staff /
   write-enabled-for-owner is not representable today; the operation catalog
   would need a permission dimension per session, not just per realm.
5. **The activity log (§10.8) attributes actions to `Actor.user(String)`.** That's
   sufficient for "which human did this" with one human. It is not sufficient for
   accountability across a small team, where you'd want to distinguish who staged
   a correction from who approved it, and possibly require a second approver for
   material writes.

None of these are hard blockers on Phase 1 — they're the specific seams where a
future multi-operator design would cut. Revisit this list when that phase
starts, rather than treating this document's single-operator assumptions as
having quietly become permanent.
