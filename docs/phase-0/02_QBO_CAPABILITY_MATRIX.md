# 2. QBO Capability Matrix

**Verification status of this document: every row is `ASSUMED`.**

I have no QBO sandbox access in this session. Nothing here has been executed
against a live API. Per `CLAUDE.md` rule 6, that means nothing here may be used
to label a feature "Automatic," and nothing here may be designed against as fact.

Each row carries a **confidence** value describing why it's assumed:

| Confidence | Means |
|---|---|
| `DOC-HIGH` | Intuit's published API surface makes this near-certain; I'd be surprised if the spike disproved it |
| `DOC-MED` | Documented but with known inconsistencies between entities, minor versions, or locales |
| `INFERRED` | Not documented as such; deduced from how adjacent entities behave |
| `NEGATIVE-HIGH` | Confident the capability does **not** exist — no endpoint, no entity. Still needs a spike to record the absence. |

Confidence is not verification. `DOC-HIGH` rows still block features under rule 6.

---

## 2.1 How to read a row

Sixteen fields per capability is unreadable as a wide table, so common values are
factored into **profiles**. Each row states its profile and only its deviations.

### Profile `TXN` — transaction entity
Purchase, Bill, BillPayment, JournalEntry, Deposit, Transfer, Payment, Invoice,
SalesReceipt, VendorCredit, CreditMemo, RefundReceipt.

| Field | Profile value |
|---|---|
| Access | Query endpoint `GET /v3/company/{realmId}/query?query=…`; single-read `GET /v3/company/{realmId}/{entity}/{id}` |
| Pagination | `STARTPOSITION` (1-based) + `MAXRESULTS`; default 100, **cap 1000**. No cursor — offset paging over a mutating set can skip or repeat rows. Mitigation in §2.6. |
| CDC | Supported (subset — verify per entity) |
| Webhook | Supported (subset — verify per entity) |
| Sparse update | `POST /v3/company/{realmId}/{entity}` with `"sparse": true`, `Id`, `SyncToken`. **Not universal — per-entity and per-field.** |
| Full update | Default when `sparse` absent. **Omitted fields are cleared.** Never issue a full update built from a partial object. |
| SyncToken | Required on every update/delete/void. Mismatch → error `5010` (stale object). Increments on every successful write, *including writes made in the QBO UI by someone else*. |
| Closed period | Write rejected with a `6xxx` business validation error when `TxnDate` ≤ `BookCloseDate` and no closing-date password is supplied. Exact code per §2.7. |
| Delete | `POST …/{entity}?operation=delete` — **hard delete, permanent, not recoverable.** |
| Void | `POST …/{entity}?operation=void` — availability is **per entity**, not universal. Verify individually. **`Purchase`: DISPROVEN, 2026-08-16 — see row 11.x.** |
| Manual QBO step | None for the read path |

**Verified findings for `Purchase` specifically, 2026-08-16** — discovered
running the capability spike, not documented anywhere in advance:

- **`PaymentType` is required on create**, undocumented in our original
  design. Omitting it fails with fault code `2020` ("Required parameter
  PaymentType is missing"). We use `"Check"`, consistent with
  `docs/phase-0/11_VERTICAL_SLICE.md` §11.2's in-scope description.
- **`DocNumber` must be unique per company by default.** Attempting to
  reuse one fails with fault code `6140` ("Duplicate Document Number
  Error"). This directly affects `VL-DUP-EXP-001`'s T2 tier
  (`docs/phase-0/11_VERTICAL_SLICE.md` §11.2) — a same-vendor/amount/
  DocNumber duplicate can only exist in a client's real data if they have
  "Custom transaction numbers" enabled in company settings; otherwise QBO
  itself already prevents the shared-DocNumber case the T2 tier looks for.
- **`DocNumber` has a 21-character maximum.** Fault code `2050` if
  exceeded.
- **`PrivateNote` is NOT a queryable field.** `select ... where PrivateNote
  = '...'` fails with fault code `4001` ("property 'PrivateNote' is not
  queryable"). Relevant beyond this spike: any future rule or UI code that
  expects to filter/search by PrivateNote needs a different approach
  (`DocNumber`, or client-side filtering after a broader read).

Not yet verified whether these four hold for the other 11 `TXN`-profile
entities — discovered and confirmed for `Purchase` only. Fixture:
`backend/spike/fixtures/results-2026-08-16T17-34-45-969Z.json` plus the
seeding-run failures that surfaced them (`backend/spike/seed.ts`'s git
history for 2026-08-16).

### Profile `NAME` — name-list entity
Account, Vendor, Customer, Item, Class, Department, Term, PaymentMethod, Employee.

Same as `TXN` except:

| Field | Profile value |
|---|---|
| Delete | **No delete operation exists.** Deactivate via sparse update `Active: false`. |
| Void | Not applicable |
| Closed period | Not applicable (no `TxnDate`) |
| Merge | Not exposed. QBO's UI merge (rename-to-match) has no API equivalent. |

### Profile `RPT` — report
All `/v3/company/{realmId}/reports/{ReportName}` endpoints.

| Field | Profile value |
|---|---|
| Access | `GET /v3/company/{realmId}/reports/{Name}?start_date=…&end_date=…&…` |
| Write | **None.** Reports are read-only, always. |
| Pagination | **None.** The full report returns in one response. Large general ledgers can be very large; size and timeout behavior is a spike item. |
| CDC | **Not applicable.** Reports are not CDC entities. |
| Webhook | **Not applicable.** No report-changed event exists. |
| Sparse / SyncToken | Not applicable |
| Closed period | Not applicable (read) |
| Delete/void | Not applicable |
| Staleness model | **Time-based, not event-based.** A report is stale when any underlying entity in its date range changed since generation — which we detect via CDC on entities, not via the report. See §6. |
| Structural risk | Column set and row nesting vary by minor version, locale, and company preferences. **Never index report columns positionally.** Bind by `ColTitle`/`ColType` metadata. |

### Profile `NONE` — no API surface
No endpoint, no entity, no field. Detection and resolution must route through
import, screenshot, or manual QBO action.

---

## 2.2 Summary index

`Det.` = detection capability · `Res.` = resolution capability
(values per the Universal Finding schema, §5).

| ID | Page | Capability | Endpoint / entity | Read | Write | Det. | Res. | Conf. |
|---|---|---|---|---|---|---|---|---|
| **C1** | Conn | Health check | `CompanyInfo` | VERIFIED | n/a | automatic | n/a | VERIFIED (2026-08-16) |
| **C2** | Conn | OAuth exchange + refresh | Intuit OAuth2 | ASSUMED | n/a | automatic | n/a | DOC-HIGH |
| **C3** | Conn | Preferences read | `Preferences` | VERIFIED | n/a | automatic | n/a | VERIFIED (2026-08-16) |
| **C4** | Conn | Webhooks | Intuit webhooks | ASSUMED | n/a | assisted | n/a | DOC-MED |
| **C5** | Conn | Change Data Capture | `/cdc` | VERIFIED* | n/a | automatic | n/a | VERIFIED-PARTIAL (2026-08-16) |
| **C6** | Conn | Batch | `/batch` | VERIFIED | VERIFIED | n/a | staged_api | VERIFIED (2026-08-16) |
| **C7** | Conn | Attachments | `Attachable` + `/upload` | n/a | VERIFIED* | assisted | staged_api | VERIFIED-PARTIAL (2026-08-16) |
| **1.1** | 1 | Company identity + realmId | `CompanyInfo` | ASSUMED | n/a | automatic | n/a | DOC-HIGH |
| **1.2** | 1 | Chart of accounts snapshot | `Account` | VERIFIED | n/a | automatic | n/a | VERIFIED (2026-08-16) |
| **1.3** | 1 | Baseline reports | `RPT` ×5 | VERIFIED | n/a | automatic | n/a | VERIFIED (2026-08-16) |
| **1.4** | 1 | Attachment inventory | `Attachable` | ASSUMED | n/a | assisted | n/a | DOC-MED |
| **1.5** | 1 | QBOA accountant access | — | **NONE** | **NONE** | unavailable | unsupported | NEGATIVE-HIGH |
| **2.1** | 2 | Read QBO closing date | `Preferences` | ASSUMED | n/a | automatic | n/a | DOC-MED |
| **2.2** | 2 | Set QBO closing date | `Preferences` | n/a | **UNLIKELY** | n/a | manual_qbo | INFERRED |
| **2.3** | 2 | Closed-period rejection codes | error envelope | ASSUMED | n/a | automatic | n/a | DOC-MED |
| **2.4** | 2 | Filing status / return submitted | — | **NONE** | **NONE** | unavailable | unsupported | NEGATIVE-HIGH |
| **3.1** | 3 | Posted transaction sweep | `TXN` ×8 | VERIFIED* | n/a | automatic | n/a | VERIFIED-PARTIAL (2026-08-16) |
| **3.2** | 3 | Transaction detail report | `RPT TransactionList` | VERIFIED | n/a | automatic | n/a | VERIFIED (2026-08-16) |
| **3.3** | 3 | General ledger | `RPT GeneralLedger` | ASSUMED | n/a | automatic | n/a | DOC-MED |
| **3.4** | 3 | QBO Books Review findings | — | **NONE** | **NONE** | import_required | manual_qbo | NEGATIVE-HIGH |
| **3.5** | 3 | Transaction Review anomalies | — | **NONE** | **NONE** | import_required | manual_qbo | NEGATIVE-HIGH |
| **3.6** | 3 | Books Close progress | — | **NONE** | **NONE** | unavailable | manual_qbo | NEGATIVE-HIGH |
| **4.1** | 4 | Posted bank/CC activity | `TXN` ×4 | VERIFIED* | n/a | automatic | n/a | VERIFIED-PARTIAL (2026-08-16) |
| **4.2** | 4 | "For Review" queue | — | **NONE** | **NONE** | import_required | manual_qbo | NEGATIVE-HIGH |
| **4.3** | 4 | Bank rules | — | **NONE** | **NONE** | import_required | manual_qbo | NEGATIVE-HIGH |
| **4.4** | 4 | Excluded bank-feed items | — | **NONE** | **NONE** | unavailable | manual_qbo | NEGATIVE-HIGH |
| **4.5** | 4 | QBO match suggestions/confidence | — | **NONE** | **NONE** | unavailable | manual_qbo | NEGATIVE-HIGH |
| **4.6** | 4 | Create missing statement item | `Purchase` | n/a | ASSUMED | automatic | **manual_qbo** ⚠ | DOC-HIGH |
| **5.1** | 5 | Cleared/uncleared status | `RPT TransactionList` | ASSUMED | n/a | assisted | n/a | DOC-MED |
| **5.2** | 5 | Statement begin/end balance | — | **NONE** | **NONE** | import_required | n/a | NEGATIVE-HIGH |
| **5.3** | 5 | Reconciliation history | — | **NONE** | **NONE** | import_required | manual_qbo | NEGATIVE-HIGH |
| **5.4** | 5 | Finish / Undo reconciliation | — | **NONE** | **NONE** | unavailable | manual_qbo | NEGATIVE-HIGH |
| **6.1** | 6 | Read accounts | `Account` | VERIFIED | n/a | automatic | n/a | VERIFIED (2026-08-16) |
| **6.2** | 6 | Create account | `Account` | n/a | VERIFIED | n/a | staged_api | VERIFIED (2026-08-16) |
| **6.3** | 6 | Rename / edit account | `Account` | n/a | VERIFIED | automatic | staged_api | VERIFIED (2026-08-16) |
| **6.4** | 6 | Deactivate account | `Account` `Active:false` | n/a | VERIFIED* | automatic | staged_api | VERIFIED-PARTIAL (2026-08-16) |
| **6.5** | 6 | Merge accounts | — | **NONE** | **NONE** | automatic | **manual_qbo** | NEGATIVE-HIGH |
| **7.1** | 7 | Reclassify expense account | `Purchase` sparse | n/a | **DISPROVEN** | automatic | **staged_api ⚠ see card** | DISPROVEN (2026-08-16) |
| **7.2** | 7 | Reclassify bill line | `Bill` sparse | n/a | **DISPROVEN** | automatic | **staged_api ⚠ see card** | DISPROVEN (2026-08-16) |
| **7.3** | 7 | Change Class / Department | `ClassRef`/`DepartmentRef` | n/a | ASSUMED | automatic | staged_api | DOC-MED |
| **7.4** | 7 | Change vendor on a txn | `Purchase`/`Bill` | n/a | ASSUMED | automatic | staged_api | DOC-MED |
| **7.5** | 7 | Batched updates | `/batch` (30 max) | n/a | ASSUMED | n/a | staged_api | DOC-HIGH |
| **7.6** | 7 | QBOA Reclassify Transactions tool | — | **NONE** | **NONE** | automatic | **manual_qbo** | NEGATIVE-HIGH |
| **7.7** | 7 | Payroll transaction correction | — | **NONE** | **NONE** | assisted | **manual_qbo** | NEGATIVE-HIGH |
| **8.1** | 8 | Balance Sheet | `RPT BalanceSheet` | VERIFIED | n/a | automatic | n/a | VERIFIED (2026-08-16) |
| **8.2** | 8 | Trial Balance | `RPT TrialBalance` | VERIFIED | n/a | automatic | n/a | VERIFIED (2026-08-16) |
| **8.3** | 8 | General Ledger | `RPT GeneralLedger` | VERIFIED | n/a | automatic | n/a | VERIFIED (2026-08-16) |
| **8.4** | 8 | Journal entries | `JournalEntry` | ASSUMED | VERIFIED | automatic | staged_api | VERIFIED (2026-08-16, write only) |
| **8.5** | 8 | Undeposited funds aging | `Deposit`+`Payment` | ASSUMED | n/a | automatic | staged_api | DOC-MED |
| **8.6** | 8 | Transfers | `Transfer` | ASSUMED | VERIFIED | automatic | staged_api | VERIFIED (2026-08-16, write only) |
| **9.1** | 9 | Tax codes / rates / agencies | `TaxCode`,`TaxRate`,`TaxAgency` | ASSUMED | n/a | automatic | n/a | DOC-MED |
| **9.2** | 9 | Create tax rate | `TaxService` | n/a | ASSUMED | n/a | staged_api | DOC-MED |
| **9.3** | 9 | Taxable treatment per txn | `TXN` line fields | ASSUMED | ASSUMED | automatic | staged_api | DOC-MED |
| **9.4** | 9 | Liability balance | `RPT` / `Account` | ASSUMED | n/a | automatic | n/a | DOC-MED |
| **9.5** | 9 | Filing / payment / notices | — | **NONE** | **NONE** | unavailable | manual_qbo | NEGATIVE-HIGH |
| **9.6** | 9 | Tax Center adjustments | — | **NONE** | **NONE** | unavailable | manual_qbo | NEGATIVE-HIGH |
| **10.1** | 10 | Income/expense basis for estimate | `RPT P&L` | ASSUMED | n/a | automatic | n/a | DOC-HIGH |
| **10.2** | 10 | Actual tax liability | — | **NONE** | **NONE** | unavailable | unsupported | NEGATIVE-HIGH |
| **11.1** | 11 | Read close date at close | `Preferences` | ASSUMED | n/a | automatic | n/a | DOC-MED |
| **11.2** | 11 | Execute Books Close | — | **NONE** | **NONE** | unavailable | manual_qbo | NEGATIVE-HIGH |
| **11.x** | 11 / slice gate | Void a Purchase | `Purchase` `?operation=void` | n/a | **DISPROVEN** | n/a | **manual_qbo** ⚠ | DISPROVEN (2026-08-16) |
| **11.x-bill** | 11 / Decision 3 | Void a Bill | `Bill` `?operation=void` | n/a | **DISPROVEN ⚠ anomalous** | n/a | **manual_qbo** | DISPROVEN (2026-08-16) — see card, HTTP 200 with a Fault body |
| **11.x-je** | 11 / Decision 3 | Void a JournalEntry | `JournalEntry` `?operation=void` | n/a | **DISPROVEN ⚠ anomalous** | n/a | **manual_qbo** | DISPROVEN (2026-08-16) — see card, HTTP 200 with an empty body |
| **11.x-bp** | 11 / Decision 3 | Void a BillPayment | `BillPayment` `?operation=void` | n/a | **DISPROVEN** | n/a | **manual_qbo** | DISPROVEN (2026-08-16) — clean rejection, same as Purchase |
| **12.1** | 12 | P&L | `RPT ProfitAndLoss` | VERIFIED | n/a | automatic | n/a | VERIFIED (2026-08-16) |
| **12.2** | 12 | Balance Sheet | `RPT BalanceSheet` | VERIFIED | n/a | automatic | n/a | VERIFIED (2026-08-16) |
| **12.3** | 12 | Cash Flow | `RPT CashFlow` | ASSUMED | n/a | automatic | n/a | DOC-MED |
| **12.4** | 12 | Aging reports | `RPT AgedReceivables`/`AgedPayables` | ASSUMED | n/a | automatic | n/a | DOC-MED |
| **12.5** | 12 | Report → QBO parity | — | n/a | n/a | assisted | n/a | INFERRED |
| **13.1** | Backlog / Cleanup Assessment | Categorization provenance (rule vs. AI vs. human) exposed via any read API | `Purchase` query, `cdc`, `reports/TransactionList` | **DISPROVEN** | n/a | unavailable | n/a | DISPROVEN (2026-08-17) |
| **13.2** | Backlog / write-risk tiers | Whether a transaction is already reconciled, exposed via any read API | `Purchase` query, `cdc`, `reports/TransactionList` | **DISPROVEN** | n/a | unavailable | n/a | DISPROVEN (2026-08-17) — see card, caveat on unreconciled-only test data |

Count: 71 rows (65 original + row 11.x + rows 11.x-bill/11.x-je/11.x-bp,
added 2026-08-16 across two spike runs the same day — Wave 1 then Wave 3;
+ rows 13.1/13.2, added 2026-08-17, Wave 5 items 49-50).
**The original document's "Count: 61" was itself wrong — never
mechanically counted; corrected while regenerating, since a false count is
the same category of problem this whole exercise exists to catch.**
**VERIFIED: 21 (5 marked `VERIFIED*` — partial coverage, see their detail
cards). DISPROVEN: 8. ASSUMED / NONE / other: 42.**

Generated from `docs/phase-0/VERIFICATION_LEDGER.json`, itself generated by
`backend/spike/regenerateMatrix.ts` from `backend/spike/fixtures/results-*.json`
— per §12.5, these status changes are not hand-typed. The ledger is the
audit trail from raw QBO response to the marker in this table.

---

## 2.3 Detail cards — rows with a write path or a non-obvious behavior

Only rows where the profile is insufficient. Read-only report rows inherit `RPT`
entirely and are not repeated.

---

### C1 — Connection health check
**Endpoint** `GET /v3/company/{realmId}/companyinfo/{realmId}`
**Profile** `NAME` (read only) · **Minor version** pin at spike; use highest
version the spike passes on · **Subscription/locale** none

**Why this row exists:** the Connection Page's green state requires a *live*
call, not a structurally-valid token (spec, Connection Pages). This is that call.
Chosen because it is cheap, non-mutating, and returns the legal name we need to
confirm we're pointed at the right company.

**Spike must record:** latency distribution, whether it counts against the
metered CorePlus allowance, and the exact error shape when the refresh token has
been revoked on Intuit's side (the failure mode this page exists to catch).

**Det/Res:** automatic / n/a. **Status: VERIFIED (2026-08-16).**

**Verification evidence:** 3 live sandbox reads succeeded, latencies
287/325/332ms. No CorePlus-metering-related response headers found (checked
against header names matching `/rate|limit|quota|throttle/i`) — either QBO
doesn't expose remaining-quota via headers on this endpoint, or names this
row didn't anticipate; not resolved further this round. Error shape probed
with a deliberately malformed bearer token (**not** a genuinely revoked
token — revoking would require disconnecting the sandbox this entire spike
run depends on): HTTP 401, `fault.error[0]` = `{"message":
"...errorCode=003200; statusCode=401", "detail": "Malformed bearer token:
too short or too long", "code": "3200"}`. A genuinely revoked (rather than
malformed) token's exact shape remains ASSUMED. Non-cached-vs-cached is not
independently verifiable from outside QBO's infrastructure and is not
claimed either way. Fixture: `backend/spike/fixtures/results-2026-08-16T17-34-45-969Z.json`.

---

### C4 — Webhooks
**Profile** custom · **Minor version** n/a

**Assumed behavior:** entity-change notifications POSTed to a registered HTTPS
endpoint, signed with HMAC-SHA256 over the raw body using a verifier token, in an
`intuit-signature` header. Only a **subset of entities** emits events. Intuit is
migrating the envelope toward CloudEvents (spec, Sync architecture).

**Design consequence:** webhooks are a *latency optimization*, never a
correctness mechanism. The architecture must be correct with webhooks entirely
disabled — CDC polling plus the periodic checksum sweep is the correctness path.
Build the receiver to accept both the legacy envelope and CloudEvents from day
one, discriminating on content type rather than on a config flag.

**Spike must record:** the exact per-entity supported list (not the doc list —
the observed list), signature verification against a real payload, replay/
duplicate delivery behavior, and whether notifications arrive for changes made by
our own writes (self-echo — if yes, we must suppress them by `intentId` or we'll
mark our own writes as third-party ledger mutations and cascade staleness).

**Det/Res:** assisted / n/a. **Status: ASSUMED (DOC-MED).**

---

### C5 — Change Data Capture
**Endpoint** `GET /v3/company/{realmId}/cdc?entities=…&changedSince=…`

**Assumed behavior:** returns entities changed since a timestamp, for a
**subset** of entity types. **Lookback is limited to ~30 days** (spec) — CDC is
not a permanent history feed. Deleted entities appear as tombstones.

**Design consequence — this is the important one:** because lookback is bounded,
a client not opened for >30 days **cannot be incrementally caught up**. That
client requires a full resync, and the app must know that rather than silently
producing a partial view. The sync engine therefore tracks `lastCdcCursor` and,
if `now - lastCdcCursor > cdcLookbackWindow - safetyMargin`, forces a full sync
and marks all derived pages stale. This interacts with the ~100-day refresh-token
expiry: a client dormant long enough to need re-auth is also long past the CDC
window, so re-authorization must always trigger a full resync.

**Spike must record:** exact supported entity list, exact lookback boundary
(test at 29/30/31 days), tombstone shape, whether `changedSince` is inclusive,
and behavior when the window is exceeded (error vs. silent truncation — silent
truncation is the dangerous answer and must be assumed until disproven).

**Det/Res:** automatic / n/a. **Status: VERIFIED-PARTIAL (2026-08-16).**

**Verification evidence — partial, stated precisely:** the endpoint is
reachable and returns the documented `CDCResponse` shape for a near-term
window (`entities=Purchase,Account,Vendor`, `changedSince` = 1 hour prior);
it reported a change to `Vendor` correctly. **NOT tested in this run** —
and still fully ASSUMED — the 30-day lookback boundary (needs real elapsed
calendar time at 29/30/31 days, which a single session cannot produce),
tombstone shape for a deleted entity, and behavior once the window is
exceeded. Do not treat this row as fully verified; only "the endpoint
exists and responds correctly to a well-formed near-term request" is
established. Fixture: `backend/spike/fixtures/results-2026-08-16T17-34-45-969Z.json`.

---

### C6 — Batch
**Endpoint** `POST /v3/company/{realmId}/batch`

**Assumed behavior:** up to **30 operations** per request; each item carries a
caller-supplied `bId`; the response returns per-item success or fault. **Batch is
not transactional** — partial success is normal and must be the assumed outcome.

**Design consequence:** the staging journal (§10) records per-operation state,
never per-batch. A batch of 30 that returns 22 successes and 8 faults produces 22
`confirmed` and 8 `failed` journal rows, and the UI reports it that way. A batch
that times out produces 30 `unknown` rows, each requiring an individual
resolution probe — which is why batch size is capped well below 30 in practice
(see §10 for the chosen ceiling).

**Spike must record:** whether faults on one item affect others, whether a batch
counts as 1 or N against rate limits, and behavior when two items in one batch
touch the same entity.

**Det/Res:** n/a / staged_api. **Status: VERIFIED (2026-08-16).**

**Verification evidence:** 10-item batch, one deliberately invalid (missing
`PaymentType`, a required-field finding from the same session — see the
`TXN` profile notes in §2.1). Result: **9 successes, 1 fault, cleanly
isolated** — the design assumption holds exactly. `docs/phase-0/10_STAGING_APPROVAL_AUDIT.md`
§10.7's per-item journaling is safe to build on this. **Not tested:**
whether a batch counts as 1 or N against rate limits, and behavior when two
items in one batch touch the same entity — both remain ASSUMED. Fixture:
`backend/spike/fixtures/results-2026-08-16T20-45-42-102Z.json`.

---

### C7 — Attachments
**Endpoint** `POST /v3/company/{realmId}/attachable` (metadata) +
`POST /v3/company/{realmId}/upload` (multipart binary content, not tested)

**Det/Res:** assisted / staged_api. **Status: VERIFIED-PARTIAL (2026-08-16).**

**Verification evidence:** creating an `Attachable` with only
`FileName`/`ContentType`/`AttachableRef` (no real content) failed —
`"You must have at least a note string or file attachment"` (fault `6000`).
Adding a `Note` field succeeded: the `Attachable` was created and linked
to a `Purchase` via `EntityRef`. **This verifies the entity-linkage half
only.** The actual binary-upload path (`/upload`, multipart form data —
what a real receipt-photo attachment needs) was **not exercised** and
remains ASSUMED. Fixture: `backend/spike/fixtures/results-2026-08-16T20-45-42-102Z.json`.

---

### 1.5 — QBOA accountant access attestation
**Profile** `NONE`

No documented endpoint returns whether you hold accountant-level QBOA access to a
company, and no endpoint returns an accountant's client list (spec, Multi-client
reality). This is not a gap to work around — it is a permanent property.

**Resolution:** Page 1 asks *you* to attest, records the attestation with
timestamp and user, and surfaces it in the Close Package as an attestation rather
than a verification. The UI must not style it like a passed check.

**Det/Res:** unavailable / unsupported. **Status: ASSUMED (NEGATIVE-HIGH).**

---

### 2.1 / 2.2 — QBO closing date
**Endpoint** `GET …/query?query=select * from Preferences`
**Field** `AccountingInfoPrefs.BookCloseDate`

**Read (2.1): ASSUMED, DOC-MED.** The field is documented on `Preferences`.
Uncertainty is whether it is populated when a closing date is set *with* a
password versus without, and whether it reflects promptly after a UI change.

**Write (2.2): ASSUMED UNLIKELY, INFERRED.** `Preferences` supports update, but I
have no basis to claim `BookCloseDate` is settable through it, and there is
certainly no API surface for the closing-date *password*. **Treat as
`manual_qbo` until the spike proves otherwise.** Page 2 and Page 11 are designed
around you setting it in QBO; if the spike shows it is settable, that is an
upgrade, not a redesign.

⚠ **Do not design Page 11's completion criteria around API-settable close dates.**

**Spike must record:** read fidelity after a UI change (with and without
password), and an explicit write attempt with the result recorded either way.

---

### 2.3 — Closed-period rejection
**Profile** error envelope, all `TXN` writes

**Assumed behavior:** attempting to create or modify a transaction dated on or
before `BookCloseDate` returns HTTP 400 with a `Fault` of type
`ValidationFault`, code in the **6xxx** range. The spec names 6200/6210. I
cannot confirm which code corresponds to which condition, and the two are
plausibly "closed period" vs. "closing date password required."

**Design consequence:** we do not rely on the code. `CLAUDE.md` and the spec both
require closed-period writes to be **blocked client-side before reaching QBO**.
The error handling is a backstop for the race where the close date changed
between our read and our write, not the primary control. The backstop must
distinguish "rejected for closed period" (expected, recoverable, present to user
as a period-lock conflict) from other 6xxx validation faults (unexpected, log as
error) — so the spike must capture the exact codes.

**Spike must record:** exact code + message for a write dated inside a closed
period, with and without a closing-date password set; and whether the code
differs by entity.

---

### 4.6 — Creating a missing statement item ⚠ POLICY-CONSTRAINED
**Endpoint** `POST /v3/company/{realmId}/purchase`
**Read** n/a · **Write** ASSUMED, DOC-HIGH — the API almost certainly permits it.

**This is the one row where the capability exists and we deliberately do not use
it.** Per spec §Page 4 safety rule: if the same item later arrives in the bank
feed, an API-created Purchase may sit unmatched or be added twice.

**Classification is therefore `detection: import_required`, `resolution:
manual_qbo`** — not because the API can't, but because doing so would create a
reconciliation hazard the app cannot see (it cannot read the For Review queue,
row 4.2, so it cannot know whether the item is about to arrive).

This distinction — *capable but prohibited* — needs to be first-class in the
matrix, because a future reader will otherwise "fix" this by enabling the write.
The Finding schema (§5) carries `resolutionConstraint: .policyProhibited(reason:)`
for exactly this, so the reason travels with the finding rather than living only
in a doc.

---

### 5.1 — Cleared / uncleared status
**Endpoint** `GET …/reports/TransactionList?…`
**Profile** `RPT`

**Assumed behavior:** `TransactionList` accepts a filter selecting cleared status
(values along the lines of Reconciled / Cleared / Uncleared / Deposited /
NotDeposited / Void). This is the *only* assumed route to reconciliation state,
since individual transaction entities do not reliably expose a cleared flag.

**Design consequence:** Page 5 can compare an imported statement against the
posted ledger and can partially inspect cleared state — but it cannot obtain the
statement beginning/ending balance (5.2), the reconciliation completion date, the
saved history, or the attached statement (5.3), and cannot execute Finish or Undo
Reconciliation (5.4). Page 5 **never goes green without imported statement
evidence or your explicit confirmation that you completed it in QBO.**

**Spike must record:** the exact parameter name and accepted values, whether the
filter is honored for credit-card accounts, and whether "Reconciled" is
distinguishable from "Cleared."

**Status: ASSUMED (DOC-MED)** — this one is a genuine coin-flip and Page 5's
design should not deepen its dependence on it before the spike.

---

### 6.3 / 6.4 — Account edit and deactivate
**Profile** `NAME`

**6.3 rename/edit — VERIFIED (2026-08-16).** Sparse update on `Account`
confirmed for `Name`: renamed cleanly, `AccountType` survived unchanged as
a side effect of the same test. **Still ASSUMED:** whether `AccountType` /
`AccountSubType` are mutable **after the account has transactions** —
this test used a fresh, empty account. Do not extend this VERIFIED status
to "type is mutable post-posting" without a separate test.

**6.4 deactivate — VERIFIED-PARTIAL (2026-08-16).** `Active: false` via
sparse update, both cases tested directly:

- **Zero balance:** deactivates cleanly, no error, nothing else to check.
- **Non-zero balance ($42 posted):** **also deactivates cleanly, no error
  returned.** But — verified by directly querying the account afterward,
  not by trusting the absence of an error:
  - **No adjusting `JournalEntry` was auto-created.**
  - **QBO renames the account**, appending `" (deleted)"` to its `Name` —
    an undocumented side effect discovered here. Any rule or UI matching
    accounts by name must account for this on deactivated accounts.
  - **The original `Purchase` transactions that posted the $42 remain
    completely unchanged** — same `Id`, same `TotalAmt`, still referencing
    the now-inactive account. Nothing about the transaction history is
    touched.
  - **The account's own `CurrentBalance` field reports `0`** after
    deactivation. **Do not read this as "the balance was reclassified or
    adjusted."** No mechanism that would explain a real adjustment was
    found (no JE, no changed transaction) — this may simply be how QBO
    reports `CurrentBalance` for any inactive account, verified or not.
    **Unresolved:** what a Trial Balance / Balance Sheet shows for this
    account post-deactivation was not checked. Do that before treating
    Page 6's deactivate path as safe for non-zero-balance accounts.

**Net effect:** the balance is not "stranded" in the sense of an error or a
visible orphaned amount, but it is **not visibly reconciled either** — the
$42 simply stops showing on the (renamed, inactive) account's balance while
the transactions that created it are untouched. This needs a real
accounting read (Trial Balance, not just `CurrentBalance`) before Page 6
can claim this path is safe. Fixture:
`backend/spike/fixtures/results-2026-08-16T20-45-42-102Z.json`.

---

### 6.5 — Merge accounts
**Profile** `NONE` — **NEGATIVE-HIGH**

QBO merges accounts by renaming one to exactly match another through the UI.
There is no merge endpoint. Attempting to replicate it by renaming via API is
**not** a supported path and must not be attempted — an API rename that collides
with an existing name has undefined merge semantics.

Per spec §Page 6 this stays manual **on purpose**: merges are permanent, can
silently lose reconciliation history, and require matching account and detail
types. The app's job is to detect merge candidates (automatic), prepare the merge
plan, and **preserve reconciliation reports first** (via §9 ingestion, since
reconciliation history is API-invisible per 5.3).

**Det/Res:** automatic / manual_qbo.

---

### 7.1 / 7.2 — Reclassification via sparse update ⚠ DISPROVEN
**Profile** `TXN`

**The single highest-risk write path in the app — and the spike confirmed
the risk is real, not hypothetical.** Constraints from the spec, each
tested directly 2026-08-16:

1. **"Sparse updates are not universal" — CONFIRMED, and more precisely
   than assumed.** Sparse *is* genuinely sparse at the **entity level**:
   updating a `Purchase`'s line `AccountRef` left `DocNumber` and
   `PrivateNote` untouched. But sparse is **NOT sparse at the line
   level**: the same update, resending the `Line` array without the
   line's `Description` (memo), **silently cleared the memo** even
   though nothing about it was mentioned as changing. Entity-level fields
   you omit survive; line-level fields you omit inside a `Line` array you
   DO send do not.
2. **"Line-level updates may require the full `Line` array" — CONFIRMED,
   and worse than "may."** Sending a `Bill` update with only 1 of its 2
   lines **silently dropped the second line entirely** — no error, no
   warning, HTTP 200. A $20 line item vanished from the transaction.
   This is not "sparse update requires the full array or it's rejected"
   (which would be safe) — it's "a partial array is *accepted* and
   *truncates* the transaction" (which is actively dangerous).
3. **Linked transactions** — not tested this round; remains ASSUMED.
4. **`Id` + `SyncToken` required** — implicitly confirmed (every write
   this session used this pattern successfully).
5. **Closed periods** — not tested this round; remains ASSUMED (see §2.3).
6. **Payroll-originated entries** — not applicable to this sandbox; remains
   ASSUMED.

**Two required-field findings discovered getting these tests to run at
all**, now in §2.1's `TXN` profile notes: `Purchase` requires
`PaymentType` on **every** write, sparse or not — omitting it (even when
unchanged from the existing value) fails with fault `2020`. `Bill`
requires `VendorRef` the same way. Sparse does not mean "unset fields
keep their existing value" for these two fields; it means "omitted
fields are cleared or rejected, entity by entity, field by field" —
exactly as constraint 1 originally warned, now with two concrete
examples.

**Design consequence — this is now load-bearing, not precautionary.**
§10's preflight round-trip check (`decode → encode → byte-compare
against a fresh read`) is not an abundance of caution. **It is the only
thing in the current design that would have caught either data-loss
event above before it was written.** Do not treat that check as optional
or as something to simplify later — this session found two independent
ways sparse updates silently destroy data on the two entities tested
first.

**Status: DISPROVEN (2026-08-16) — "safe to build batch reclassification
on a straightforward sparse-update payload" is false.** The capability
(sparse update exists, writes succeed) is real; the *safety assumption*
behind it is not. §7's batch-fix design must always resend: (a) every
required field, regardless of whether it's changing, and (b) the complete
`Line` array, every line, every field on every line — never a computed
diff. Fixture: `backend/spike/fixtures/results-2026-08-16T20-45-42-102Z.json`.

---

### 7.3 — Class / Department
**Profile** `TXN` · **Subscription** `Class` and `Department` require **QBO Plus
or Advanced**, and must additionally be *enabled* in company Preferences.

A client on Essentials will have these refs absent entirely. The rules engine
must treat "no Class on any transaction" as *not applicable* rather than as a
finding — otherwise every Essentials client generates a page of false positives.
Read `Preferences` (C3) to determine applicability and drive
`.cannotEvaluate(.featureNotEnabled)` (§8) rather than `.pass`.

---

### 7.6 — QBOA Reclassify Transactions tool
**Profile** `NONE` — **NEGATIVE-HIGH**

No API equivalent exists. Row 7.1–7.5 approximates it via sparse updates, but the
QBOA tool handles cases ours will not (it is aware of linkages and can operate at
a scale our 30-per-batch ceiling makes tedious).

**This stays a documented manual alternative you may prefer for large jobs**
(spec, Page 7). The UI should say so at a threshold — e.g. above N transactions,
Page 7 recommends the QBOA tool rather than staging N/30 batches. Choosing N is a
Phase 2 decision informed by observed batch reliability.

---

### 8.4 — Journal entries
**Profile** `TXN` · **Status: ASSUMED (DOC-HIGH)** for both read and write.

Create/read/update are well supported. The constraint is editorial, not
technical: **Intuit recommends using journal entries sparingly — prefer the
native transaction type where practical** (spec, Page 8). A JE that should have
been a `Transfer` or a `Deposit` is technically valid and practically wrong.

The rules engine therefore treats "correction expressible as a native
transaction" as preferred, and any staged JE correction must record why a native
type was not used. That justification belongs in the Close Package.

---

### 9.1 / 9.3 — Sales tax
**Profile** `NAME` / `TXN` · **Subscription/locale — significant.**

QBO has (at least) two sales-tax modes: **Automated Sales Tax (AST)** and legacy
manual tax. Field semantics, which `TaxCode`s exist, whether rates are editable,
and whether `TaxService` can create rates all differ between them. Non-US locales
differ again (VAT/GST reporting, different agencies, and in some locales
entities that do not exist in the US edition at all).

**Design consequence:** Page 9 is `skippable per client` (spec) and must first
determine the tax mode from `Preferences`, then select a rule set. Writing tax
rules that assume AST and running them on a legacy-mode company produces
confidently wrong findings — the worst category.

**Spike must record:** mode detection from `Preferences`, and the `TaxCode`/
`TaxRate` shape under each mode.

**Scope, owner decision (2026-08): US-only, Automated Sales Tax only.** All
clients are US-based and legacy manual-tax companies are out of scope for v1.
Page 9's rule set is written against AST exclusively. **Legacy mode is
classified `.unsupported` and gated, not merely untested:** the mode-detection
read against `Preferences` runs first, and if it resolves to legacy tax, Page 9
returns `MissingRequirement.featureNotEnabled("Automated Sales Tax")` →
`.cannotEvaluate` → gray, with the reason stated. It never attempts AST-shaped
rules against a legacy-mode file. Non-US locales are `.unsupported` for the same
reason — no client, no rule set.

---

### 12.5 — Report parity with QBO's rendered reports
**Profile** `RPT` · **INFERRED**

Report API responses need normalization and **will not be pixel-identical to
QBO's rendered reports** (spec, Page 12). Row grouping, subtotal placement, and
which columns appear differ.

**Design consequence:** the Close Package must not imply it reproduces QBO's
report. Numbers should tie; layout will not. Any place we show a total next to a
QBO screenshot, the tie-out must be a computed comparison, not visual similarity.
A tie-out mismatch is a finding, not a rendering bug — and the first suspect is
report parameters (accounting method, date basis) rather than QBO being wrong.

---

### 11.x — Void a Purchase — the vertical slice's write-path gate ⚠ DISPROVEN
**Endpoint** `POST /v3/company/{realmId}/purchase?operation=void`
**Profile** `TXN` (deviation — see below) · **Added 2026-08-16**, added as a
row specifically because it's the exact question
`docs/phase-0/11_VERTICAL_SLICE.md` §11.1 is gated on, and every other row
touching write behavior already existed before this test ran.

**This was previously ASSUMED (DOC-MED) — "I believe [void] does [work]." It
does not.**

QBO's response to the void attempt, verbatim:
```json
{
  "Fault": {
    "Error": [{
      "Message": "Unsupported Operation",
      "Detail": "Operation void is not supported.",
      "code": "500",
      "element": "Operation"
    }],
    "type": "ValidationFault"
  }
}
```
Unambiguous — not a malformed request, not a missing precondition (the
`Purchase` being voided was created successfully first, confirmed via a
fresh re-read). QBO is stating directly that the operation does not exist
for this entity.

**Consequence per §11.1's pre-written branch logic:** this selects
**Branch B** — no API write for duplicate-expense resolution on `Purchase`;
`resolution_capability` is `manual_qbo`, not `staged_api`, for
`VL-DUP-EXP-001`'s primary worked example. Both branches were specified in
advance precisely so this outcome wouldn't require a redesign — it requires
building the already-specified Branch B path. **Whether and how to proceed
with that is the owner's call, not something this regeneration decides.**

**Det/Res:** n/a / **manual_qbo** (was: staged_api, ASSUMED). **Status:
DISPROVEN (2026-08-16).**

**Tested 2026-08-16, per owner Decision 3** (`docs/phase-0/SPIKE_QUEUE.md`):
whether void is a `Purchase`-specific gap or a `TXN`-profile-wide one.
Answer: **it varies by entity, and two of the three responses are worse
than Purchase's clean rejection.** See the three cards below.
Fixture: `backend/spike/fixtures/results-2026-08-16T17-34-45-969Z.json`
(Purchase), `backend/spike/fixtures/results-2026-08-16T20-45-42-102Z.json`
(Bill, JournalEntry, BillPayment).

---

### 11.x-bill — Void a Bill ⚠ DISPROVEN, anomalously
**Endpoint** `POST /v3/company/{realmId}/bill?operation=void`

**Status: DISPROVEN (2026-08-16).** But not the way `Purchase` was.
`Purchase`'s void returned a clean HTTP 400 with a plain "Unsupported
Operation" fault. `Bill`'s void returns **HTTP 200** with this body:
```json
{
  "Fault": {
    "Error": [{
      "Message": "An application error has occurred while processing your request",
      "Detail": "System Failure Error: java.lang.UnsupportedOperationException",
      "code": "10000",
      "element": "SystemFailureError"
    }],
    "type": "SystemFault"
  }
}
```
A Java-level `UnsupportedOperationException` is leaking through as a
`SystemFault`, **on a 200 status code.** This is the single most
important finding from this test group: **`response.ok` / `status === 200`
is not sufficient to confirm a QBO write succeeded.** Any code — ours or
anyone else's — that checks status alone would record this as a
successful void. It is not one. **Consequence for §10's preflight and
resolution-probe design: the "did this write land" check must inspect the
response body for a `Fault` key regardless of HTTP status, not treat 200
as sufficient on its own.** This generalizes beyond void — nothing tested
this session rules out the same pattern occurring on other write
operations we haven't tried yet.

---

### 11.x-je — Void a JournalEntry ⚠ DISPROVEN, ambiguously
**Endpoint** `POST /v3/company/{realmId}/journalentry?operation=void`

**Status: DISPROVEN (2026-08-16).** A third distinct shape. HTTP 200,
body:
```json
{ "BatchItemResponse": [], "time": "..." }
```
**No `Fault`. No `JournalEntry` object. Nothing.** Resolution probe run
immediately after (re-reading the entity): **it still exists, unvoided.**
So the write silently did nothing — QBO accepted the request, returned a
success-shaped envelope, and changed nothing. This is arguably the
**most dangerous of the three shapes**: `Bill`'s `SystemFault` is at least
detectable by scanning for a `Fault` key; this response has no error
signal of any kind. The only way to know it didn't work was to
independently re-read the entity — exactly the resolution-probe pattern
`docs/phase-0/10_STAGING_APPROVAL_AUDIT.md` §10.6 already specifies for
the `UNKNOWN` timeout case, now shown necessary for a different reason: a
200 response that is quietly a no-op.

---

### 11.x-bp — Void a BillPayment ✅ clean rejection, consistent with Purchase
**Endpoint** `POST /v3/company/{realmId}/billpayment?operation=void`

**Status: DISPROVEN (2026-08-16), cleanly.** HTTP 400, identical shape to
`Purchase`: `"Message": "Unsupported Operation", "Detail": "Operation
void is not supported.", "code": "500"`. The one entity of the four
tested (`Purchase`, `Bill`, `JournalEntry`, `BillPayment`) that behaves
the way you'd want an "unsupported" answer to behave.

---

**Summed up across all four:** void is unsupported everywhere tested, but
QBO's way of saying so is **not consistent** — clean rejection
(`Purchase`, `BillPayment`), a leaked system exception disguised as
success (`Bill`), and a silent no-op disguised as success
(`JournalEntry`). Branch B is confirmed as the only safe path for all
four entities, and the response-classification problem this surfaced is
arguably more consequential than the void question itself.

---

### 13.1 — Categorization provenance ❌ DISPROVEN, confirmed absent

**Source** `docs/phase-0/SPIKE_QUEUE.md` Wave 5 item 49, `testCategorizationProvenance` · `docs/backlog/CLEANUP_MODE.md` §2.7

**Question:** is QBO's rule-vs-AI-vs-human categorization source exposed via any read API? A per-transaction "this was 100% a guess" signal (visible in the QBO UI per Hector Garcia's walkthrough) would be a powerful cleanup filter if reachable.

**Status: DISPROVEN (2026-08-17).** Checked across three surfaces against the live sandbox — a plain `Purchase` query (35 distinct keys observed across the full raw JSON, not just top level), the `cdc` feed (93 distinct keys), and the `TransactionList` report's column set (`Date, Transaction Type, Num, Posting, Name, Memo/Description, Account, Split, Amount`). None of 12 plausible candidate field names (`Source`, `TxnSource`, `CategorizationSource`, `CreatedBy`, `CreatedVia`, `SuggestedBy`, `AISource`, `RuleSource`, `BankRuleId`, `MatchedRuleId`, `AutoCategorized`, `IsAiSuggested`) appeared anywhere. See `backend/spike/fixtures/results-2026-08-17T16-06-42-317Z.json` for the full negative evidence.

**Consequence:** the "sort the whole file by categorized-by-a-guess" cleanup filter proposed in `CLEANUP_MODE.md` §2.7 has no API path. If this signal is only ever visible in the QBO UI, the only way to capture it is a screenshot per transaction — not practical at cleanup scale. This particular backlog idea should be considered closed, not merely unimplemented, unless a future minor version exposes something new (the search here was a point-in-time check).

---

### 13.2 — Reconciled-transaction detection ❌ DISPROVEN (unreconciled test data only)

**Source** `docs/phase-0/SPIKE_QUEUE.md` Wave 5 item 50, `testReconciledTransactionDetection` · `docs/backlog/REDDIT_FEEDBACK_ASSESSMENT.md` item 6

**Question:** can the API tell us a transaction has already been reconciled? A write against an already-reconciled transaction breaks that reconciliation, and §10.3's five preflight checks don't currently check for this.

**Status: DISPROVEN (2026-08-17), with a caveat that matters.** Same three-surface check as 13.1, against 8 candidate field names (`Cleared`, `cleared`, `Reconciled`, `ReconcileStatus`, `ReconciliationStatus`, `BankReconciliationStatus`, `ClearedStatus`, `TxnStatus`) — none found. This corroborates row 3.1/4.1's earlier, narrower finding (no `cleared` field on `Purchase`) with a broader search across more surfaces and more candidate names.

**The caveat, not hidden:** no seed data in this sandbox has ever been through a real `Finish Reconciliation` in the QBO UI. This confirms the field doesn't exist on an **unreconciled** transaction's shape — it does not rule out a field that only appears once a transaction actually is reconciled (QBO's API is known to omit some fields entirely rather than send them null/false, e.g. `SyncToken` behavior elsewhere in this matrix). A real answer needs a follow-up test against a manually-reconciled account — `spike/seeds/reconciliation.json` already exists for this (feeds Wave 4 item 44, `testClearedStatusFilter`, itself still unrun). Do not treat 13.2 as fully closed the way 13.1 is; treat it as "no signal in the common case," with the reconciled case still genuinely open.

---

## 2.4 What has no API at all — consolidated

Because this list is what actually shapes the product, here it is in one place.
All `NEGATIVE-HIGH`. Every one of these is a Type B or Type C page in the spec,
and each has a named fallback.

| Missing capability | Fallback | Page |
|---|---|---|
| QBOA client list / accountant access | Manual per-company OAuth + your attestation | 1 |
| Books Review findings | Screenshot → OCR | 3 |
| Transaction Review anomalies | Screenshot → OCR | 3 |
| Books Close progress / execution | Guided manual + your confirmation | 3, 11 |
| "For Review" bank-feed queue | Screenshot → OCR | 4 |
| Bank rules | QBO's own rules export, or screenshot | 4 |
| Excluded bank-feed items | Screenshot | 4 |
| QBO match suggestions / confidence | None — out of reach, documented as such | 4 |
| Statement beginning/ending balance | Bank statement import (CSV/OFX/QFX/PDF) | 5 |
| Reconciliation history & saved reports | PDF export or screenshot | 5 |
| Finish / Undo Reconciliation | Guided manual | 5 |
| Account merge | Guided manual (with pre-merge evidence capture) | 6 |
| Reclassify Transactions tool | Guided manual, or our staged batches | 7 |
| Payroll transaction correction | Guided manual | 7 |
| Sales tax filing status / payments / notices | Your confirmation | 9 |
| Tax Center adjustments | Guided manual | 9 |
| Actual tax liability | Out of scope — estimate only, always labeled | 10 |
| **QBO Audit Log** | CSV *or* PDF export → ingestion | Activity Log |

**The last row is why Universal Ingestion is scheduled early** (Build Order §4).
It is the difference between an activity log that covers Voice Ledger's own
actions and one that can also account for changes made directly in QBO.

---

## 2.5 Cross-cutting: rate limits and metering

**ASSUMED, DOC-MED.** Per-realm request throttling with 429 responses; a
concurrency ceiling; and most reads metered as "CorePlus" calls under Intuit's
usage-based pricing with a large free monthly allowance (spec, Sync
architecture).

Design responses, all of which are architecture, not optimization:
- **Cache locally and prefer CDC over full syncs.** Non-negotiable, not a tuning
  knob.
- **Paginate at the cap** (~1000) to minimize request count.
- **Batch carefully** (30 max, and we will use less).
- **Exponential backoff with jitter on 429**, with a per-realm token bucket in
  the *backend* so that the ceiling is enforced across all desktop clients for
  that realm, not per-process.
- **Meter and attribute cost per client** — the Claude Connection Page already
  requires per-client spend tracking; QBO call cost belongs beside it so the true
  cost of a close is visible.

**Spike must record:** the actual 429 threshold, the `Retry-After` behavior, and
which endpoints are metered.

**Verification, 2026-08-16 — inconclusive by design, not a gap:** 40 rapid
sequential `companyinfo` reads against the sandbox produced zero 429s (avg
latency 304ms, range 258–419ms). **This does not mean no limit exists** —
only that this endpoint, at this volume, in this sandbox, didn't trip one.
Deliberately did not push further: a sandbox company used for every other
test in this run is not the place to go looking for the ceiling by brute
force. The threshold, `Retry-After` behavior, and which endpoints are
metered all remain ASSUMED. Fixture:
`backend/spike/fixtures/results-2026-08-16T17-34-45-969Z.json`.

---

## 2.6 Cross-cutting: pagination correctness ⚠

**This is a correctness bug waiting to happen and I want it flagged now.**

`STARTPOSITION`/`MAXRESULTS` is **offset pagination over a live, mutating set**.
If a transaction is created or deleted between page 3 and page 4 of a sync, rows
shift — and a row can be **skipped entirely** or **returned twice**. A skipped
duplicate expense is a false green.

Mitigations, in order of preference:
1. **Order by a stable key and paginate by key range** rather than offset, if the
   query language permits `ORDER BY Id` with a `WHERE Id > lastId` predicate.
   *Spike item — this is the clean fix if it works.*
2. **Bound the query by a closed time window** (`TxnDate` within the period) so
   the result set is not growing at the tail during the sweep.
3. **Checksum the sweep**: after paginating, re-query `COUNT` and compare to rows
   collected. Mismatch → mark the sync `partial`, which by §8's rules means
   `.cannotEvaluate` and a gray page, not a green one.

Mitigation 3 is mandatory regardless of whether 1 or 2 works, because it converts
a silent correctness failure into an honest gray. The spec's "periodic checksum
catches missed events" is the same idea; this applies it per-sweep.

**Verified, 2026-08-16 — this is a real bug, not a theoretical one.**
Reproduced directly: created 6 `Purchase` records, fetched page 1
(`ORDER BY Id STARTPOSITION 1 MAXRESULTS 2`), deleted the earliest of the
6 (a record already fetched), then fetched page 2
(`STARTPOSITION 3 MAXRESULTS 2`) against the now-5-element set. **A third
record — never deleted, still existing in QBO — was silently absent from
every page fetched.** Exact before/after Id sequences and both fixture
runs (the first attempt used QBO's *default* order, which turned out to be
Id-**descending**, not ascending as first assumed — that wrong assumption
accidentally avoided reproducing the skip; the corrected run explicitly
sorts `ORDER BY Id` and reproduces it cleanly) are in
`backend/spike/fixtures/results-2026-08-16T17-34-45-969Z.json`.

Two mitigations also confirmed viable in the same session:
- **Mitigation 1 (`ORDER BY Id`) is supported syntax** — confirmed via a
  direct probe query, separate from the reproduction above.
- **Mitigation 3 (checksum) is viable**: `select count(*) from Purchase`
  is supported (`totalCount` field), and in an unrelated full-sweep test
  the count matched the paginated total exactly (50 = 50) — confirming the
  checksum mechanism itself works as designed, though it was not run
  *concurrently* with the skip-reproduction above (that would require a
  third, more elaborate test; the mechanism's correctness is established
  either way).

**Net effect:** §2.6's concern moves from ASSUMED to VERIFIED, and the
verified answer is "the bug is real." This does not change the design —
mitigations 1 and 3 were already specified — it converts them from
precautionary to load-bearing.

---

## 2.7 Cross-cutting: minor version pinning

**ASSUMED.** Minor version is a query parameter (`minorversion=NN`) that changes
field availability and, for reports, column composition.

**Decision:** pin one minor version app-wide, recorded in config, asserted in
every request, and stored on every cached response and every Finding. A finding
detected under minor version N is not automatically valid under N+1 — column
semantics may have shifted. Bumping the pinned version is a deliberate operation
that reruns the capability spike suite and marks affected findings for
revalidation, exactly like a rule version bump (§8).

I am deliberately not naming a version number here. The spike selects the highest
version that passes the full suite, and that number goes in config — not in prose
in this document where it will rot.

---

## 2.8 Sandbox verification plan

The plan that turns `ASSUMED` into `VERIFIED`. Mechanics are in §12; this is the
sequencing.

### Wave 0 — prerequisites (blocking everything)
Intuit developer account · sandbox company · OAuth round trip · backend able to
refresh a token · **environment badge proven visually distinct** before any other
work, per `CLAUDE.md` rule 7.

### Wave 1 — read surface (unblocks the read-only sync)
Rows C1, C3, C5, 1.1, 1.2, 1.3, 3.1, 4.1, 8.1, 8.2, 8.3, 12.1–12.4.
Plus §2.6 pagination correctness and §2.5 rate-limit measurement.
**Exit:** a full read-only sync of a seeded sandbox that is reproducible and
checksum-clean.

### Wave 2 — the negatives (unblocks honest UI)
Rows 1.5, 2.4, 3.4–3.6, 4.2–4.5, 5.2–5.4, 6.5, 7.6, 7.7, 9.5, 9.6, 10.2, 11.2.
Each requires a recorded attempt and a recorded absence — "I looked for this
endpoint and it does not exist" with the search documented.
**Exit:** every Type B/C page's fallback is justified by a recorded negative,
not by my assertion in this document.

### Wave 3 — the writes (unblocks the vertical slice)
Row **11.x-void** (Purchase void — see §11, this is the gate) first, then 6.2,
6.3, 6.4, 7.1, 7.2, 7.5, 8.4, C6, C7.
Each write test must run **twice**: once normally, once with an injected timeout
after send, to exercise the `unknown` path in §10.
**Exit:** the §11 vertical slice write path is proven, including recovery.

### Wave 4 — the awkward ones
Rows 2.1, 2.2, 2.3 (closed period), 5.1 (cleared status), 9.1–9.4 (tax mode),
C4 (webhooks, needs a public endpoint), 12.5 (report parity).
These need special sandbox setup (a closing date, a completed reconciliation, a
configured tax mode, a reachable webhook URL) and will be slower.
**Exit:** Pages 2, 5, 9, 11 have honest completion criteria.

### Per-row evidence required for VERIFIED
1. The exact request (URL, method, minor version, headers with secrets redacted)
2. The sanitized response, committed as a test fixture
3. An assertion in the test suite that fails if behavior changes
4. The verification date
5. For negatives: the attempt made and the absence recorded

A row's `VERIFIED` status **expires**. See §12 for the staleness window and the
scheduled re-verification job — an API that changed under us must show up as a
matrix regression, not as a production surprise.
