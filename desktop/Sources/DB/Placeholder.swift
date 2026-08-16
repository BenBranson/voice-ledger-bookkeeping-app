/// /db — deferred.
///
/// Design constraints: docs/phase-0/07_CLIENT_ISOLATION.md §7.1 — one SQLite
/// database per realm, never a `realm_id` column with a WHERE clause. Not
/// part of the approved Phase 1 scope (steps 1.0–1.2 only).
public enum DBPlaceholder {}
