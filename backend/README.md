# Voice Ledger — Thin Backend

Phase 1, steps 1.0–1.2 (see `../docs/phase-0/00_OVERVIEW.md`'s gate table).
**Scope: OAuth, session, and the fixed QBO operation catalog — READ
operations only.** No write operation exists yet; see
`src/catalog/operations.ts`'s `assertReadOnlyCatalog()`.

Design reference: `../docs/phase-0/03_SECURITY_THREAT_MODEL.md` §3.3–§3.4.

## What this is, in one sentence

The only thing standing between the desktop app and QuickBooks — it holds
the QBO client secret and Claude API key (neither ever reaches the desktop
client), and exposes a fixed, named catalog of operations instead of a
generic proxy, so an unlisted operation is structurally unreachable, not
merely unauthorized.

## Setup

### 1. Get an Intuit developer account and sandbox company

**This is yours to do — not something that can be automated here.** Free,
at [developer.intuit.com](https://developer.intuit.com). Create an app,
note its sandbox Client ID and Client Secret, and add a redirect URI (see
below).

### 2. Configure environment

```bash
cp .env.example .env
# Fill in QBO_SANDBOX_CLIENT_ID, QBO_SANDBOX_CLIENT_SECRET.
# Generate TOKEN_ENCRYPTION_KEY:
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

`QBO_REDIRECT_URI` in `.env` must exactly match a redirect URI registered
in your Intuit app's settings — for local dev,
`http://localhost:3000/oauth/callback`.

### 3. Install and run

```bash
npm install
npm run dev
```

### 4. Connect the sandbox company

Visit `http://localhost:3000/oauth/authorize` in a browser and approve.
The callback response is JSON with a `sessionToken` and a `realmId` — see
`../desktop/Sources/VoiceLedgerDevTool/main.swift` for how to use them to
verify the Phase 1 step 1.2 exit gate:

```bash
export VOICE_LEDGER_BACKEND_URL=http://localhost:3000
export VOICE_LEDGER_SESSION_TOKEN=<from the callback response>
export VOICE_LEDGER_REALM_ID=<from the callback response>
cd ../desktop && swift run voiceledger-devtool health
```

Green output there is the actual, verified exit condition for step 1.2 —
not this README's say-so.

## Storage — an explicit, temporary scope decision

Refresh tokens and app sessions live in a local SQLite file
(`src/db/sqlite.ts`). This is intentional for Phase 1: sandbox-only,
single-operator, tens of clients at most
(`../docs/phase-0/OPEN_QUESTIONS.md` Q6). **Render's default filesystem is
ephemeral across deploys** — `render.yaml` attaches a persistent disk to
work around that for now. A managed database (Render Postgres, or
similar) is worth provisioning once this moves past sandbox testing; it is
not needed yet and adding it now would be scope creep against what was
approved.

Refresh token *values* are encrypted before they reach this file
(`src/auth/crypto.ts`) regardless of where the file lives.

## Deploying to Render

You already have a Render connector configured — this fits the "small
managed container" from `../docs/phase-0/OPEN_QUESTIONS.md` Q2 with the
least new setup.

1. Push this repo (or connect it) to Render, or use `render.yaml` as a
   Blueprint (`New +` → `Blueprint` in the Render dashboard, pointing at
   this repo).
2. Fill in the `sync: false` environment variables in the Render dashboard
   — `render.yaml` deliberately does not contain real secret values.
3. After first deploy, set `APP_BASE_URL` to the actual Render URL and
   `QBO_REDIRECT_URI` to `<that URL>/oauth/callback` — then add that same
   redirect URI to your Intuit app's settings.
4. Webhooks are **deferred** per `../docs/phase-0/OPEN_QUESTIONS.md` Q2 —
   CDC-polling-only ships first. No webhook-specific Render configuration
   is needed yet.

## Production credentials — deliberately hard to turn on

`src/config.ts`'s `resolveQBOCredentials()` can only return production
credentials when **both** `ALLOW_PRODUCTION=true` **and**
`QBO_PRODUCTION_CLIENT_ID` / `QBO_PRODUCTION_CLIENT_SECRET` are set. Neither
is present in `.env.example`, `render.yaml`, or any CI configuration.
`test/productionGuard.test.ts` asserts this fails closed. Per
`CLAUDE.md` rule 7 and the owner's explicit Phase 1 instruction: sandbox
client ID only, for now.

## Running tests

```bash
npm test          # unit tests — no network, no sandbox needed
npm run typecheck
```

## Running the capability spike

See `spike/README.md` — separate from the app's own test suite, requires a
connected sandbox company, and is how `../docs/phase-0/02_QBO_CAPABILITY_MATRIX.md`
gets its `ASSUMED` rows turned into `VERIFIED`.

## What's deliberately NOT here yet

- Any write-classified catalog operation (`voidPurchase`, account edits,
  etc.) — each needs its spike test to pass first
  (`../docs/phase-0/SPIKE_QUEUE.md`), and adding one requires separate
  Phase 1 approval per the gate table.
- Webhook receiver — deferred (Q2).
- The Connection Page UI — that's step 1.3, not yet approved. The
  `/oauth/callback` JSON response is a development convenience standing in
  for it.
