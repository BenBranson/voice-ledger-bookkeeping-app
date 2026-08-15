# Feature Capability Classification

Every proposed feature, classified into the five requested buckets.

| Symbol | Bucket |
|---|---|
| 🟢 | **Supported through the QBO API** |
| 🟡 | **Partially supported** — API covers some of it |
| 🔧 | **Manual QBO action required** |
| 📄 | **Available only via file import or screenshot** |
| ⛔ | **Unsupported** — no path exists |

All classifications rest on §2's matrix, which is entirely `ASSUMED`. A row's
classification can change when the spike runs. Where that would be a *material*
change, it's noted.

---

## Connection layer

| Feature | Class | Notes |
|---|---|---|
| Connect a company via OAuth | 🟢 | Per-company; no bulk client list exists |
| Health check (live CompanyInfo read) | 🟢 | Must be a real call; a cached assumption is not green |
| Token refresh | 🟢 | Backend only |
| Refresh-token expiry countdown | 🟢 | Computed locally from grant time |
| Per-client Read-Only / Write-Enabled toggle | 🟢 | Self-enforced — QBO has no read-only scope |
| Sandbox / production visual distinction | 🟢 | App-side; `CLAUDE.md` rule 7 |
| Claude connection status, model assignment, spend | 🟢 | Backend-mediated |
| AI kill switch | 🟢 | App-side; proven by the §12 kill-switch suite |
| **Accountant's full QBOA client list** | ⛔ | No documented endpoint. Registry is Voice Ledger's own. |
| **Verify QBOA accountant access** | ⛔ | Your attestation only |

---

## Page 1 — Access & Evidence Pack (Type A + C)

| Feature | Class | Notes |
|---|---|---|
| Confirm company name and `realmId` | 🟢 | |
| Connection health | 🟢 | |
| Read chart of accounts | 🟢 | |
| Baseline reports (BS, P&L, TB, GL, Transaction List) | 🟢 | |
| Generate the **Baseline Evidence Pack** | 🟢 | **Not a backup.** Terminology is non-negotiable (`CLAUDE.md`). |
| Inventory attachments | 🟡 | `Attachable` list is API-visible; completeness unverified |
| **Restorable backup of a QBO file** | ⛔ | No API. Never represent the evidence pack as one. |
| QBOA access attestation | 🔧 | Recorded, never verified |

---

## Page 2 — Scope & Period Lock (Type A + C)

| Feature | Class | Notes |
|---|---|---|
| Store engagement scope | 🟢 | Local |
| Read QBO `BookCloseDate` | 🟡 | Read assumed; fidelity after a UI change unverified |
| Voice Ledger's own stricter lock | 🟢 | Local, always enforceable |
| Warn on transactions dated in closed periods | 🟢 | Local comparison |
| Catch closed-period rejection codes | 🟡 | Backstop only; exact codes unverified |
| **Set the official QBO closing date** | 🔧 | ⚠ If the spike shows `Preferences` accepts it, this becomes 🟢 — an upgrade, not a redesign |
| **Set the closing-date password** | ⛔ | No API surface |
| **Confirm filing status** | 🔧 | Your confirmation |

---

## Page 3 — File Health Scan (Type A)

| Feature | Class | Notes |
|---|---|---|
| Analyze accounts, transactions, BS, P&L, TB, GL | 🟢 | Strong coverage |
| Duplicate expense / bill / invoice / payment detection | 🟢 | Deterministic, `/core` |
| Uncategorized transaction detection | 🟢 | |
| Miscoding detection vs. vendor history | 🟢 | Local history |
| Unusual vendor name / amount / timing | 🟢 | |
| Recurring subscription increase or non-use | 🟢 | |
| Avoidable fees and interest | 🟢 | |
| Possible personal expenses / owner draws | 🟢 | Detection only; classification is yours |
| **QBO Books Review findings** | 📄 | Screenshot → OCR. No API entity. |
| **Transaction Review anomalies** | 📄 | Screenshot → OCR |
| **Books Close progress** | ⛔ | No API |
| Voice Ledger Health Scan (our own) | 🟢 | Modeled on the same checks; **not** claiming to be QBO's tool |

---

## Page 4 — Bank Feed Cleanup (Type B)

| Feature | Class | Notes |
|---|---|---|
| Analyze posted bank/CC activity | 🟢 | |
| Compare against imported statement | 📄 | CSV / OFX / QFX / PDF |
| Duplicate detection against statement | 📄 | Requires the import |
| Missing-posting detection | 📄 | Requires the import |
| **"For Review" queue** | 📄 | Screenshot only |
| **Bank rules** | 📄 | QBO's own rules export, or screenshot |
| **Excluded items** | 📄 | Screenshot |
| **QBO's suggested matches / categories / confidence** | ⛔ | Not exposed in any form |
| **Create a missing statement item via API** | 🔧 | ⚠ **Capable but prohibited.** The API almost certainly permits it; we don't. If the item later arrives in the bank feed it may sit unmatched or double-post, and we can't see the feed to know. |

---

## Page 5 — Reconciliation (Type B + C)

| Feature | Class | Notes |
|---|---|---|
| Compare statement lines to posted ledger | 📄 | |
| Identify unmatched and duplicate items | 📄 | |
| Inspect cleared / uncleared activity | 🟡 | Via `TransactionList`; parameter unverified and genuinely uncertain |
| Calculate the difference | 📄 | Deterministic, once the statement is imported |
| **Statement beginning / ending balance** | 📄 | No API. Import only. |
| **Reconciliation completion date & saved history** | 📄 | PDF or screenshot |
| **The attached statement** | 📄 | |
| **Finish Reconciliation** | 🔧 | No API |
| **Undo Reconciliation** | 🔧 | No API |
| Green without evidence | ⛔ | **By design.** Never green without a statement or your explicit confirmation. |

---

## Page 6 — Chart of Accounts Cleanup (Type A + C)

| Feature | Class | Notes |
|---|---|---|
| Read accounts | 🟢 | |
| Create account | 🟢 | |
| Rename / edit account | 🟡 | Name/number/description assumed; type changes assumed **not** mutable once posted to |
| Deactivate account | 🟡 | ⚠ Behavior with a non-zero balance is unverified and material — build after the spike |
| Detect duplicate-account candidates | 🟢 | |
| Prepare a merge plan | 🟢 | |
| Preserve reconciliation reports before merge | 📄 | Because reconciliation history is API-invisible |
| **Merge accounts** | 🔧 | **Manual on purpose**, not only from an API gap: permanent, can lose reconciliation history, requires matching types, cannot be undone |

---

## Page 7 — Batch Fixes (Type A)

| Feature | Class | Notes |
|---|---|---|
| Reclassify expense account | 🟡 | Sparse-update support is per-entity and per-field |
| Reclassify bill line | 🟡 | |
| Change Class / Department | 🟡 | **QBO Plus/Advanced only**, and must be enabled |
| Change vendor on a transaction | 🟡 | |
| Batched updates | 🟢 | 30 max; we cap at 10 (§10.7) |
| Pre-run preview (count, dollars, tax impact, report impact, reversal) | 🟢 | All computed locally |
| **QBOA Reclassify Transactions tool** | 🔧 | No API equivalent; remains the better choice for large jobs |
| **Payroll transaction correction** | 🔧 | Payroll APIs or manual |
| **Undo a batch** | 🟡 | A new, separately-approved reversal — never an automatic rollback |
| **Hard delete** | ⛔ | **Deliberately not in the backend operation catalog.** Permanent. |

---

## Page 8 — Balance Sheet Integrity (Type A)

Strongest API coverage of any page.

| Feature | Class |
|---|---|
| Balance Sheet, Trial Balance, General Ledger | 🟢 |
| Account list, transaction list | 🟢 |
| Journal entries (read/create/update) | 🟢 |
| Bills, payments, deposits, purchases, transfers | 🟢 |
| Negative asset/liability balance detection | 🟢 |
| Suspense account activity | 🟢 |
| Stale clearing accounts | 🟢 |
| Undeposited-funds aging | 🟢 |
| Loan balance inconsistencies | 🟢 |
| Equity postings needing review | 🟢 |
| Unexpected balance changes period over period | 🟢 |
| Debit/credit patterns against account expectations | 🟢 |
| Attachments | 🟡 |

Editorial constraint, not technical: prefer native transaction types over journal
entries where practical, and record why when a JE is used anyway.

---

## Page 9 — Sales Tax Review (Type A + C, skippable)

**Scope, owner decision (2026-08): US clients, Automated Sales Tax only.**

| Feature | Class | Notes |
|---|---|---|
| Read tax codes, rates, agencies (AST) | 🟡 | Mode-detected first; AST shape only |
| Read taxable treatment per transaction (AST) | 🟡 | |
| Read liability balances (AST) | 🟡 | |
| Create a tax rate (AST) | 🟡 | `TaxService` |
| Correct taxable treatment on a transaction (AST) | 🟡 | |
| **Confirm filing jurisdiction / frequency / period** | 🔧 | |
| **Confirm return and payment submitted** | 🔧 | |
| **Tax Center adjustments** | 🔧 | |
| **Outstanding notices** | ⛔ | |
| **Legacy manual-tax mode** | ⛔ | **Explicitly unsupported, not untested.** Mode-detection gate returns `.cannotEvaluate` before any AST-shaped rule runs, rather than producing confidently wrong findings against the wrong mode. |
| **Non-US locales (VAT/GST, etc.)** | ⛔ | Out of scope — no client, no rule set |

⚠ Running AST-shaped rules against a legacy-mode company produces confidently
wrong findings. Mode detection precedes rule selection, always.

---

## Page 10 — Taxes (Type A)

| Feature | Class | Notes |
|---|---|---|
| Estimate trends and possible exposure from QBO data | 🟢 | **Always labeled an estimate.** Never filing guidance. |
| **Actual liability** | ⛔ | |
| **Deductions, basis, outside income** | ⛔ | |
| **Filed-return status** | ⛔ | |

---

## Page 11 — Month-End Close (Type A + C)

| Feature | Class | Notes |
|---|---|---|
| Checklist, dependencies, approvals, carry-forwards | 🟢 | Local (§6) |
| Read QBO close date | 🟡 | |
| Full validation scan | 🟢 | |
| Year-end mode (no unsupported adjusting entries) | 🟢 | |
| **Set the official closing date** | 🔧 | |
| **Complete QBO's Books Close** | 🔧 | |

`PeriodState` keeps `closedInVoiceLedger` and `closedInQBO` separate (§6.8).
Conflating them would be an overclaim.

---

## Page 12 — Reporting (Type A)

| Feature | Class | Notes |
|---|---|---|
| P&L, Balance Sheet, Cash Flow, GL, TB | 🟢 | |
| Transaction and aging reports | 🟢 | |
| Branded client PDF | 🟢 | Locally generated |
| Close Package | 🟢 | Locally assembled |
| Dependency-aware staleness across pages | 🟢 | §6, derived |
| **Pixel-identical reproduction of QBO's reports** | ⛔ | Numbers tie; layout won't |

---

## Beyond the workflow

| Feature | Class | Notes |
|---|---|---|
| Firm Cockpit | 🟢 | Fan-out across per-client stores (§7.1) |
| Next Best Action | 🟢 | Deterministic ranking |
| Client Memory, With Approval | 🟢 | Never silent |
| Client Question Builder | 🟢 | Claude drafts; you send |
| Close Package | 🟢 | |
| Training Mode | 🟢 | From `Rule.accountingPrinciple` (§8.2) |
| Ask Claude panel | 🟢 | Read-only by construction |
| Voice navigation / filter / search / read / draft | 🟢 | Local Whisper |
| **Voice finalizing a QBO write** | ⛔ | **By design.** Visible on-screen confirmation always. |
| Wrong-Client Protection | 🟢 | §7 |
| Universal Ingestion — Tier 1 deterministic | 🟢 | |
| Universal Ingestion — Tier 2 on-device OCR | 🟢 | ⚠ macOS version dependent (Q4) |
| Universal Ingestion — Tier 3 Claude vision | 🟢 | Explicit per-file consent; off-device |
| Cross-foot validation | 🟢 | Deterministic; blocks green on failure |
| Multi-screenshot stitching with overlap detection | 🟢 | |
| **Activity & Correction Log** | 🟡 | Proves our actions; cannot prove direct QBO changes or pre-connection history |
| **QBO Audit Log** | 📄 | CSV or PDF export → ingestion. Partially closes the gap above. |

---

## Tally

| Class | Count |
|---|---|
| 🟢 Supported through the QBO API | 62 |
| 🟡 Partially supported | 22 |
| 🔧 Manual QBO action required | 17 |
| 📄 Import or screenshot only | 13 |
| ⛔ Unsupported | 17 |

**Roughly a quarter of the surface needs a handoff to you or a file.** That is
not a shortfall — it is the operating model. Every 🔧 has a Type C page with a
procedure and a recorded confirmation; every 📄 has a Type B page with
get-the-file-here instructions. The failure mode this app exists to prevent is a
*forgotten* step, not an unautomated one.
