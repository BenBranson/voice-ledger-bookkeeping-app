# 3. Security Threat Model

Scope: the thin backend's exact responsibilities and boundaries, token handling,
what transits versus what persists, and how the desktop client is structurally
prevented from invoking arbitrary QBO endpoints.

---

## 3.1 The adversary list

Not a generic checklist — these are the threats that actually apply to a
single-operator bookkeeping tool holding accountant-level access to multiple
client companies.

| # | Threat | Why it matters here |
|---|---|---|
| T1 | **Binary extraction** — attacker obtains the app bundle and extracts the QBO client secret or Claude API key | A distributed macOS binary is fully readable. A leaked client secret lets an attacker impersonate the app in OAuth flows. |
| T2 | **Arbitrary QBO invocation** — a compromised or modified desktop client issues QBO calls the app never intended | Accountant-level access to real client books. This is the highest-consequence threat in the model. |
| T3 | **Cross-client leakage** — client A's data appears in client B's context | Regulatory and professional-conduct consequences, plus it destroys trust in every finding. §7 addresses the data-layer half; this document addresses the auth half. |
| T4 | **Refresh-token theft** — long-lived credential exfiltrated from wherever it rests | ~100-day validity, read+write scope, per company. The most valuable secret in the system. |
| T5 | **Prompt injection via ingested documents** | A PDF or screenshot is attacker-influenced input that reaches an LLM. See §3.7. |
| T6 | **Accidental production write during development** | `CLAUDE.md` rule 7. Not malicious, and the most likely to actually happen. |
| T7 | **Backend as accounting-data honeypot** | The backend proxies financial payloads. If it logs or persists them, it becomes a concentrated target holding multiple companies' books. |
| T8 | **Replay / duplicate write** — the same approved correction executes twice | Double-voiding, double-creating. §10's idempotency design. |
| T9 | **Local device compromise** | Imported statements, cached ledger data, and the local database sit on the Mac. |

---

## 3.2 The honest boundary statement

Restating the spec's language because it is the sentence most likely to get
softened later, and softening it would make it false:

> **The backend does not persist accounting payloads, but QBO and Claude requests
> transit it, and it may process selected data in memory while proxying
> authorized requests.**

"The backend never touches accounting data" is **false** and must not appear in
any document, marketing text, or client-facing description. What is true:

| Data | Transits backend | Persists in backend |
|---|---|---|
| OAuth authorization code | ✅ | ❌ |
| Refresh token | ✅ | ✅ **encrypted at rest** |
| Access token | ✅ | ⚠ cached in memory only, TTL-bounded |
| QBO read responses (ledger data) | ✅ | ❌ |
| QBO write payloads | ✅ | ❌ — only a metadata record (§3.5) |
| Claude fact packets | ✅ | ❌ — only token counts and cost |
| Claude API key | ❌ (never leaves backend) | ✅ **encrypted at rest** |
| **Imported files (CSV/PDF/screenshots)** | ❌ | ❌ |
| **On-device OCR output** | ❌ | ❌ |
| Tier 3 Claude-vision documents | ✅ **with explicit per-file consent** | ❌ |
| Local findings, staging queue, activity log | ❌ | ❌ |

The two bold ❌ rows in the imports section are a real privacy property and the
main reason the import path is valuable beyond filling API gaps. **Tier 3
escalation breaks it**, which is exactly why it requires explicit per-file
consent and plain-language disclosure rather than silent escalation (§9).

---

## 3.3 Backend responsibilities — the complete list

The backend does these things and **nothing else**. Anything not on this list
does not belong in the backend; propose it as an addition explicitly.

1. **Hold the QBO client secret.** Never transmitted to the desktop client.
2. **Hold the Claude API key.** Never transmitted to the desktop client. The
   Claude Connection Page shows whether a key is configured and working — never
   the key (spec).
3. **Perform the OAuth authorization-code exchange** and all refreshes.
4. **Store refresh tokens encrypted at rest**, keyed per `realmId`.
5. **Issue and validate app sessions** for the desktop client.
6. **Authorize and execute a fixed catalog of named QBO operations** (§3.4).
   This is the load-bearing control against T2.
7. **Enforce per-realm access mode** — Read-Only vs. Write-Enabled — server-side.
8. **Enforce per-realm rate limiting** with a shared token bucket.
9. **Log access** with financial payloads and tokens excluded (§3.5).
10. **Send Claude only approved, minimized fact packets** (§3.6).
11. **Refuse any request whose `realmId` is not bound to the caller's session.**

Explicitly **not** backend responsibilities: running rules, computing findings,
storing findings, storing imports, OCR, storing the activity log, deciding
severity. All of that is local, which keeps the backend's blast radius small and
keeps the app functional in read-only/offline modes.

---

## 3.4 Defeating T2: the operation catalog

**This is the central control and the most important decision in this document.**

The desktop client **cannot express a QBO request.** There is no endpoint on the
backend that accepts a path, a method, and a body. The backend does not have a
proxy route. What it has is a catalog of named operations with typed parameters:

```
readCompanyInfo(realmId)
readAccounts(realmId, activeOnly, page)
readPurchases(realmId, dateRange, page)
readReport(realmId, reportKind, parameters)   // reportKind is a closed enum
cdcSince(realmId, entityKinds, since)         // entityKinds is a closed enum set
voidPurchase(realmId, purchaseId, syncToken, intentId)
updatePurchaseAccountRef(realmId, purchaseId, syncToken, lineId, accountId, intentId)
deactivateAccount(realmId, accountId, syncToken, intentId)
…
```

Properties this buys, in order of importance:

**A. Unlisted operations are unreachable.** If `deletePurchase` is not in the
catalog, no version of the desktop client — modified, decompiled, or replaced —
can hard-delete a purchase. The capability does not exist on the wire.

**B. Adding a QBO capability requires a backend deploy.** That is deliberate
friction. It means every new write path passes through a review that a
client-side change would not get. It also means the catalog *is* the enforcement
of `CLAUDE.md` rule 6 — a capability that hasn't been sandbox-verified is simply
not in the catalog.

**C. Server-side write gating is meaningful.** Because writes are named, the
backend can refuse *all* write-classified operations for a realm in Read-Only
Mode. A client-side toggle would be advisory; this one is not. Per `CLAUDE.md`
rule 4, every new client connection starts read-only, and the authoritative state
of that flag lives in the backend, not in the app's local database.

**D. Parameter validation is possible.** `voidPurchase` requires a `syncToken`;
the backend can reject a request without one rather than forwarding a malformed
call. `readReport` takes a closed `reportKind` enum, so the client cannot probe
report endpoints we haven't verified.

**E. The audit log is semantically meaningful.** "`voidPurchase` on realm X"
rather than "POST to some URL."

### Cost of this design, stated plainly
Every new QBO capability is a two-sided change (catalog entry + client call) and
a deploy. During Phase 1 that will feel slow. It is the correct trade for
accountant-level write access to real client books, and it is what `CLAUDE.md`
rule 3's second clause — "the desktop client must not be able to invoke arbitrary
QBO endpoints" — actually requires. A generic proxy with an allowlist of paths is
*not* equivalent: allowlists drift, and a path allowlist still lets the client
control the request body.

---

## 3.5 Logging: what is recorded and what is forbidden

**Recorded per request:**
`timestamp` · `sessionId` · `realmId` · `operationName` · `outcome`
(success/fault/timeout) · `httpStatus` · `latencyMs` · `intentId` (writes only) ·
`minorVersion` · byte counts.

**Forbidden in logs, at every level including debug:**
access tokens · refresh tokens · client secret · Claude API key · request bodies ·
response bodies · any dollar amount · any entity name (vendor, customer,
employee) · any memo, description, or document number · imported file contents ·
Claude prompts or completions.

**Enforcement, because a policy is not a control:**
- A structured logger where the *only* way to log is via typed fields drawn from
  the allowed set. No `log(String)` interpolation API exists in the backend.
- A redaction filter as a second layer, matching token-shaped strings and
  currency patterns, that trips a loud alarm on match — a match means the typed
  logger was bypassed, which is a bug to fix, not noise to suppress.
- A CI test that exercises a write path with distinctive canary values
  (`$13579.24`, vendor `ZZCANARYVENDOR`) and asserts they appear nowhere in
  captured log output.

Rationale for the severity here: T7. A backend that logs response bodies is a
single store containing several companies' complete ledgers, which is a
materially worse asset to lose than the books themselves — those at least sit
behind Intuit's controls.

---

## 3.6 Claude boundary

**Fact packets, never dumps.** Claude receives compact pre-selected facts —
never a raw company-file dump (spec, Rules Engine vs. Claude).

Concretely, per `CLAUDE.md` rule 1 and the spec's guardrails:

1. **A fact packet is constructed by deterministic code from an already-computed
   finding.** Claude never receives the inputs to a calculation; it receives the
   output plus the minimum context needed to explain it.
2. **Every number in the packet is pre-computed and labeled as authoritative.**
   The prompt instructs Claude to cite these values rather than compute; the
   *architecture* backs that up by never sending enough raw data to compute an
   alternative.
3. **Structured output via schema-controlled JSON**, versioned prompts, all
   output visibly labeled draft or guidance (spec).
4. **The Ask Claude panel is read-only by construction.** It has no access to the
   staging queue's mutation API, no ability to approve findings, and no state
   transitions. It is an advisor, not a second control surface (spec). This is
   enforced by the panel's context object being a value type containing rendered
   findings — it holds no repository handles at all, so there is nothing for a
   tool call to reach even if we later add tools.
5. **The kill switch is real.** A single toggle disables all AI features
   app-wide, and every deterministic rule, finding, calculation, and report still
   works (spec). §12 makes this a test: the full deterministic suite runs with AI
   disabled and outputs must be byte-identical.
6. **Model choice is per-task configurable, not hardcoded** — Opus 5 for the Ask
   Claude panel and complex multi-finding explanations, a cheaper faster model for
   routine per-finding narration (spec).

### Cost attribution
Per-client spend tracking is a spec requirement. The backend is the only place
that sees Claude requests, so it owns the meter, tagged by `realmId` and
`operationKind`. This makes the cost of closing a client's month attributable —
which is also the fastest way to notice a prompt that got fat.

---

## 3.7 T5: prompt injection through ingested documents

A vendor could put text in a PDF invoice. A screenshot could contain a crafted
string. Both reach an LLM in Tier 3 escalation and in finding narration.

**Controls:**
1. **Extracted text is data, never instruction.** Fact packets place document
   text in a clearly delimited data region, and the system prompt states that
   content within it is untrusted input to be described, never followed.
2. **The blast radius is already near zero by architecture.** Claude cannot write
   to QBO, cannot approve a finding, cannot change state, and cannot compute an
   authoritative number. Successful injection yields *misleading prose next to
   correct numbers* — bad, but it cannot move money.
3. **Cross-foot validation is deterministic** (§9) and runs before any LLM sees
   the document. An injected instruction cannot make a document cross-foot.
4. **The extraction verification UI shows the source image side by side** (spec),
   so a human sees the actual document, not just the transcription.
5. Control 2 is the one that matters, and it is a consequence of `CLAUDE.md`
   rule 1 rather than a bolted-on defense. Worth noting: the "code computes,
   Claude explains" rule is also the app's primary injection defense.

---

## 3.8 T6: never modifying production during development

`CLAUDE.md` rule 7. Layered, because a single control will eventually be
bypassed by someone in a hurry — including me.

1. **Separate credentials.** Sandbox and production QBO apps have different
   client IDs. A development backend is configured with the sandbox client ID
   only and physically cannot mint a production token.
2. **Environment is a property of the connection record**, resolved from the
   `realmId` at connect time and immutable thereafter — never a global mode flag
   that could be wrong.
3. **Backend refuses production writes unless an explicit deployment-level flag
   is set**, and that flag is absent from every development and CI configuration.
4. **Visual distinction is unmistakable** — different background treatment, not
   just a text label (spec). Production connections get a persistent chrome
   treatment that cannot be confused at a glance from across two monitors.
5. **A test asserts the guard.** CI runs a test that attempts a production-classed
   write and asserts it is refused. If someone removes the guard, CI fails.

Control 1 is the real one. The rest are defense in depth.

---

## 3.9 Token lifecycle

| Token | Lifetime | Storage | Rotation |
|---|---|---|---|
| QBO access token | ~1 hour | Backend memory, TTL-bounded | Silent refresh |
| QBO refresh token | **~100 days** | Backend, **encrypted at rest**, per `realmId` | Rotated on each refresh; new value replaces old atomically |
| App session token | Short, renewable | Desktop keychain | Renewed against backend |
| Claude API key | Until rotated | Backend, encrypted at rest | Manual |

**Refresh-token rotation is a correctness hazard, not just a security one.**
Intuit rotates the refresh token on use. If the backend writes the new token and
crashes before commit, or two refreshes race, the stored token can be invalidated
and the client requires full re-authorization. Controls: refresh is serialized
per `realmId`, the new token is persisted before the old is discarded, and a
refresh failure is surfaced on the Connection Page as **red with the specific
cause**, not as a generic sync error.

**Proactive expiry surfacing** (spec): countdown at 30 days out, escalating to
yellow at 14. A client you haven't opened in three months needs full
re-authorization, and that must not be discovered the morning you sit down to
close their books. Note the interaction with CDC's ~30-day lookback (§2, C5):
any client past the CDC window needs a full resync, so re-authorization and full
resync are the same event and should be presented as one.

---

## 3.10 T9: local data at rest

Imported statements, cached ledger data, findings, and the activity log live on
the Mac.

- Database and import store live under the app's Application Support directory,
  **segregated per `realmId`** (§7).
- **File protection:** files created with restrictive permissions; the store
  directory excluded from Time Machine and from iCloud/third-party sync by
  default — an accounting cache silently syncing to a consumer cloud service is
  a real exposure and an easy default to get wrong.
- **FileVault is assumed but not sufficient**, since it protects only at rest
  when powered off. The Connection Page should surface FileVault status as an
  environment check.
- **Retention:** imported source documents are retained because they are evidence
  for findings (provenance, §9). A per-client retention policy with explicit
  deletion is a Phase 2 need, not Phase 1.

---

## 3.11 Residual risks — accepted, not solved

Stating these so they are decisions rather than oversights:

- **A compromised Mac is a compromised app.** Local session token, local cached
  ledger data, local imports. Nothing in this design defends against an attacker
  with code execution on your machine.
- **The backend can read accounting data in transit.** Unavoidable given it
  proxies writes and authorizes operations. Mitigated by not persisting and not
  logging, not by not seeing.
- **Intuit's own scope model forces read+write.** `com.intuit.quickbooks.accounting`
  grants both (`CLAUDE.md` rule 4). Self-enforcement is the entire safety story —
  which is why §3.4's catalog is the most important control in this document.
- **A malicious or buggy rule could stage a harmful correction.** Mitigated by
  human approval (`CLAUDE.md` rule 2), never by trusting the rule.
