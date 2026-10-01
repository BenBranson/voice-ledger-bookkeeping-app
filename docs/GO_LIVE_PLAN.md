# Voice Ledger — Go-Live Plan (backend online + QuickBooks production)
Written 2026-10-01. One page. Nothing here changes the sandbox setup that works today.
Facts about Intuit's rules are from general knowledge and MUST be re-checked on developer.intuit.com before spending money.

## Why it's needed
- QuickBooks' real-client login (OAuth) sends the client back to a **public HTTPS address**; `localhost` only works for the sandbox.
- CLAUDE.md rule 3: the QuickBooks client secret and AI keys live **only in the backend**, never in the desktop app.
- Intuit reviews every app before production keys are issued (app assessment, privacy policy, terms, company site).

## The pieces
| Piece | What it is | Where it lives |
|---|---|---|
| Business website | benjaminbransonbookkeeping.com — already exists | stays where it is |
| Legal pages | `/privacy` and `/terms` (Intuit asks for both) | on the business website |
| Backend | the existing Node/TypeScript server (QuickBooks + token storage) | a hosted server at `api.benjaminbransonbookkeeping.com` |
| Token database | encrypted QuickBooks refresh tokens | Supabase Postgres (replaces the local SQLite file) |
| AI | Gemma 12B on the owner's Mac | **stays local**; desktop talks to Ollama directly (a hosted backend can't reach the laptop) |
| Desktop app | Voice Ledger | the owner's Mac; points at the hosted backend for QuickBooks only |

Supabase cannot run the Express backend as-is (no long-running Node server); using it for the database only keeps the QuickBooks code untouched.

## Steps, in order
1. **Confirm requirements** (owner + Claude, no cost): read Intuit's production checklist; list exactly which URLs/forms they ask for.
2. **Legal pages** (Claude drafts, owner adds to the website): privacy policy covering QuickBooks data, read-only default, no data sale, deletion on request; terms of use. Have a Texas attorney glance at them with the engagement agreement.
3. **Host** (owner signs up and pays; Claude sets up): Render (Node web service) + Supabase (free tier to start). Add the `api.` DNS record at the domain registrar.
4. **Move the backend** (Claude): environment variables on the host (QuickBooks secret, token-encryption key); swap SQLite for Postgres; HTTPS only; logs; the `/healthz` check already exists.
5. **Desktop app** (Claude): backend URL becomes a setting; AI calls go to local Ollama; sandbox/production stay visually unmistakable (rule 7).
6. **Intuit production application** (owner fills forms, Claude supplies the answers): app assessment, redirect URI `https://api.…/oauth/callback`, privacy/terms URLs. Expect days to weeks of review.
7. **First real client, read-only**: connect with writes OFF (rule 4), run the Health Scan, compare to the client's own QuickBooks. Writes stay disabled until a sandbox-proven path is approved.

## Rough monthly cost
Render web service $7–25 · Supabase $0 (free tier) to $25 · domain already owned · Intuit developer account $0. **About $7–50/month.**

## Owner's to-do list (the parts Claude can't do)
- [ ] Log in to developer.intuit.com and screenshot the production-keys checklist
- [ ] Tell Claude where the website is hosted (Wix / Squarespace / GoDaddy / WordPress …)
- [ ] Create the Render and Supabase accounts (payment card required for Render)
- [ ] Add the DNS record Claude specifies at the domain registrar
- [ ] Complete Intuit's app-assessment forms (Claude supplies answers)

## Not in scope here
Webhooks, Xero adapter, multi-user logins, a client-facing portal.
