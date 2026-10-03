# Voice Ledger — Project Constraints

Native macOS (SwiftUI) bookkeeping command center layered on QuickBooks Online.
Full spec: `docs/VOICE_LEDGER_SPEC.md` — read it before any architectural decision.
**Institutional memory: `docs/VOICE_LEDGER_HANDOFF.md` — read it at the start of every session.** It carries decisions, verified findings, rejected approaches with reasons, and things that must never be removed or broken (§18) that don't live anywhere else. When it and the `docs/phase-0/*` files disagree, the more recently-dated statement wins — update the stale one rather than silently trusting either.

## Non-negotiable rules

1. **Code computes and classifies. Claude explains.** Every dollar figure, severity, confidence score, and pass/fail decision comes from deterministic Swift. LLM calls only produce prose, drafts, and guidance — never an authoritative number, never a severity assignment.

2. **Detect → draft → review → push.** No code path writes to a production QuickBooks file without an explicit human approval step. Staged corrections live locally first.

3. **No secrets in the desktop binary.** The QBO client secret and Claude API key live only in the thin backend. The desktop client must not be able to invoke arbitrary QBO endpoints.

4. **QBO has no read-only OAuth scope** (`com.intuit.quickbooks.accounting` grants read+write). The app enforces read-only itself. Every new client connection starts in Read-Only Mode; writes are enabled per-client, explicitly.

5. **Green means verified, not merely "nothing found."** A check may only render green when the required data was present, the check completed, the result is current, and no exception was found. Missing or stale data renders gray, never green.

6. **No feature is labeled "Automatic" without sandbox proof.** The existence of a similarly-named API field or SDK class is not evidence that an operation works.

7. **Never modify production QBO data during development.** Sandbox only. Production and sandbox connections must be visually unmistakable in the UI.

8. **Extraction is not computation.** OCR/vision-extracted financial data is never auto-approved into a finding that can lead to a QBO write. It passes through cross-foot validation and human verification first.

9. **Client isolation by `realmId`.** All data, caches, queues, and logs segregate by QBO `realmId` — never by a mutable "current client" variable.

## Architecture boundaries

- `desktop/Sources/Core` — platform-agnostic rules engine. Never imports from `desktop/Sources/Integrations` (enforced by `desktop/Scripts/check-module-boundaries.sh`).
- `desktop/Sources/Integrations/QuickBooks` — QBO calls via the backend, normalized into Core's shape.
- `desktop/Sources/Integrations/Imports` — file parsers + on-device OCR, normalized into the *same* shape.
- Adding Xero later must mean writing one adapter, not touching `/core`.

## Terminology (deliberate — do not "correct" these)

- **Baseline Evidence Pack**, not "backup" — a report export is not a restorable backup.
- **Voice Ledger Health Scan**, not "Books Review" — QBO's Books Review has no API.
- **Voice Ledger Activity & Correction Log**, not "Audit Log" — QBO's audit log has no API.

## Working style

- Prefer the smallest change that solves the problem.
- When an API capability is uncertain, verify against sandbox before designing around it — do not assume from documentation alone.
- Flag any place the spec conflicts with observed API reality rather than silently working around it.
