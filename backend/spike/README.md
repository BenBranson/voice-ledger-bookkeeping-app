# Capability Spike — Runbook

Implements docs/phase-0/SPIKE_QUEUE.md. Run this against a **sandbox**
company only — nothing here should ever point at production credentials.

## One-time setup (Wave 0)

1. Create an Intuit developer account and a sandbox company at
   developer.intuit.com (free). **This step is yours — it can't be
   automated from here.**
2. In your Intuit app's settings, add a redirect URI matching
   `QBO_REDIRECT_URI` in your backend's `.env` (see `backend/.env.example`).
3. Start the backend locally: `npm run dev` (from `backend/`).
4. Visit `<APP_BASE_URL>/oauth/authorize` in a browser, sign into the
   sandbox company, and approve. The callback response is JSON containing a
   `sessionToken` — you don't need it for the spike scripts (they read the
   refresh token straight from the backend's SQLite store), but it's what
   `voiceledger-devtool` needs for the Phase 1 step 1.2 gate check.
5. Export the realm you just connected for the spike scripts:
   ```
   export QBO_SPIKE_REALM_ID=<the realmId from the callback response>
   ```
6. Seed the baseline data:
   ```
   npx tsx spike/seed.ts apply baseline
   ```

## Running the queue

```
npx tsx spike/seed.ts apply duplicates
npm run spike
```

Results are written to `spike/fixtures/results-<timestamp>.json` and a
summary prints to stdout. `spike/fixtures/seed-manifest.json` tracks what
was created so `apply` stays idempotent — re-running it is safe.

## Manual sandbox setup required for later waves

Per docs/phase-0/SPIKE_QUEUE.md Wave 4, these need state that can only be
created by hand in the sandbox UI. **Fill in the exact steps here as you do
them each** — per docs/phase-0/12_TEST_STRATEGY.md §12.6: "write the setup
procedure into a checked-in runbook as you go, since it will be needed again
on a fresh sandbox."

### Closing date (items 41–43)
- [ ] Steps to set a closing date without a password: _(fill in)_
- [ ] Steps to set a closing date WITH a password: _(fill in)_

### Reconciliation (item 44)
- [ ] Steps to mark `VL-SPIKE-RECON-CLEARED` (from `spike/seeds/reconciliation.json`)
      as Reconciled in the sandbox UI: _(fill in)_

### Automated Sales Tax mode (items 45–46)
- [ ] Steps to confirm/enable AST on a fresh sandbox company: _(fill in)_

### Webhooks (item 47 — deferred per docs/phase-0/OPEN_QUESTIONS.md Q2)
- Not needed until webhooks are picked back up. CDC-polling ships first.

## Teardown

```
npx tsx spike/seed.ts teardown all
```

Hard-deletes every `Purchase` this harness created (tracked via the
`PrivateNote` markers in `spike/seeds/*.json`, e.g. `VL-SPIKE-DUP-A`). This
is sandbox-only, throwaway data — a permanent hard delete here is fine and
is NOT the pattern used anywhere in the production write path (see
docs/phase-0/10_STAGING_APPROVAL_AUDIT.md, which never hard-deletes).

Accounts and vendors are left in place (QBO has no delete API for them —
docs/phase-0/02_QBO_CAPABILITY_MATRIX.md's `NAME` profile). If the sandbox
gets too cluttered, it's usually faster to spin up a fresh sandbox company
than to clean one up by hand.

## A boundary worth restating

`spike/qboRawClient.ts` calls QBO directly — including operations, like
`void`, that are **not** in `src/catalog/operations.ts` yet. That's the
entire point of the spike: discovering what an endpoint does before
committing to a typed catalog entry for it (docs/phase-0/03_SECURITY_THREAT_MODEL.md
§3.4). Nothing in `spike/` is reachable by the desktop client, and nothing
in `spike/` should ever be imported from `src/`. Promoting a capability from
"the spike proved this works" to "the desktop can invoke this" means adding
a properly-typed, reviewed entry to the catalog — never pointing production
code at `qboRawClient.ts`.
