# Reddit Voice-of-Customer — Assessment & Additions

Reviewing the eight recommendations against the current spec. Sorted by whether they change the architecture, refine it, or restate something already there.

---

## Tier 1 — These change the architecture. Adopt both.

### 1. Transaction Relationship Guard ⭐ the best idea in the set

Our rules currently ask *"is the category correct?"* This asks a question that comes **before** that one: *"is this even the right kind of transaction?"*

The decision tree, in order:
1. Should this be **matched** to an existing bill, invoice, payment, or deposit?
2. Is it a **credit-card payment** (balance sheet, never an expense)?
3. Is it a **bank-to-bank transfer** (never income or expense)?
4. Should it be **combined with others** into one deposit (Undeposited Funds)?
5. Should it be **split** — principal/interest/fees, or across categories?
6. Is it a **refund, chargeback, owner contribution, or owner distribution**?
7. Only after ruling all of that out: is it a **new expense**, and what category?

**Why this is right:** every catastrophic bookkeeping error lives in steps 1–6, not step 7. A miscategorized expense is wrong by one line on the P&L. A "categorize" that should have been a "match" **duplicates income or expense outright**. A credit-card payment booked to an expense double-counts the entire payment. Those are order-of-magnitude errors, and they're all *type* errors, not *category* errors.

**Architectural consequence:** this reorders the rules engine. Relationship rules run first and gate the categorization rules. It also subsumes the `VL-CC-PAYMENT-001` rule from the cleanup addendum — that's just branch 2 of this tree.

**Adopt as:** `VL-RELATIONSHIP-001` through `-006`, one per branch, evaluated before any categorization rule on the same transaction.

### 2. Many-to-one and one-to-many statement matching

I under-specified this, and ChatGPT is right that it's a correctness requirement rather than a feature. One-to-one matching alone will generate constant false alarms on any real file.

Required match shapes:
- Several QBO payments → one bank deposit (this is what Undeposited Funds *is*)
- One statement withdrawal → several QBO lines (a split transaction)
- Settlement deposits net of processing fees (Stripe, PayPal, Square — the deposit never equals the sales)
- Refunds and chargebacks
- Transaction date vs. cleared date differences
- Amount tolerances for fees and rounding
- Reversed and re-posted transactions
- Outstanding checks and deposits in transit

**Why it matters more than it sounds:** without this, Page 4 and 5 report a client's normal Stripe settlement as a missing transaction every single month, and you learn to ignore the page. A tool that cries wolf gets turned off.

**This should be built alongside the Import Bridge, not after it** — the matching engine is the point of the import, and building the import without it produces a page you won't trust.

---

## Tier 2 — Real refinements. Adopt, but they extend existing designs rather than replacing them.

### 3. Account-Month Control Grid
Converges with the reconciliation gap map from the cleanup addendum, but extends it correctly: not just *reconciled y/n* but the full control set per account-month — statement received · cross-footed · compared to QBO · difference · QBO reconciliation confirmed · changed afterward.

**The point worth keeping verbatim:** *never show a percentage without its denominator.* "8 of 10 required controls complete — two accounts lack August statements" instead of "85% ready." That's the same principle as the green rule, applied to progress indicators, and it closes a hole I hadn't noticed: a health score is exactly the kind of number that can look reassuring while hiding a missing account.

### 4. Client Accounting Control Profile
Formalizes and versions what we currently split across `MaterialityPolicy` and client memory. The additions worth taking: capitalization threshold, cash vs. accrual basis, fiscal year, known bank/card/loan accounts, expected payment processors and their settlement behavior, accounts that should never be used, and who must approve sensitive decisions.

**The framing that justifies it:** *a $900 purchase might be an expense for one client and a fixed-asset review item for another.* Rules must evaluate against that client's actual policy, not generic assumptions.

Make it a watermark component, exactly as materiality already is — changing the profile changes findings, so completed pages go stale.

### 5. Balance-Sheet Evidence Workpapers
Extends Page 8 from *detecting* abnormal balances to *requiring evidence* for every material balance-sheet account: bank → statement, loan → lender statement, AR/AP → aging, Undeposited Funds → composition of open deposits, sales tax payable → filed return, fixed assets → asset schedule, retained earnings → prior-year return or approved trial balance.

**The prior-year anchor is the highest-value piece:** does the opening balance sheet agree with the prior tax return or the accountant-approved closing trial balance? On a cleanup, that single check finds problems nothing else will.

**Keep the constraint as written:** flag the discrepancy, never invent the correcting journal entry. That's a judgment call requiring the tax preparer.

### 6. Sensitive-Write Preflight — risk classification
Our preflight (§10.3) has five blocking checks. This adds a **risk tier** and three checks we don't have:
- **Is the transaction already reconciled?** (changing it breaks the reconciliation — we don't check this and should)
- Does it affect AR, AP, sales tax, payroll, or inventory?
- Does supporting documentation exist?

Tiers: low (vendor/memo, open period) · moderate (category/class) · high (reconciled, linked, balance sheet, prior period) · blocked (payroll, inventory, merge, filed period).

The reconciled-transaction check is the real gap. Add it.

### 7. Client Exception Packet
Extends the Client Question Builder from per-finding questions into one grouped monthly packet, with due dates, carry-forward from last month, and who answered when.

Practical and time-saving. Lower architectural risk than anything above — it composes over the existing Finding and Question types.

---

## Tier 3 — Already in the plan

**8. Cleanup Assessment Mode** — proposed in `CLEANUP_MODE.md`. Independent convergence from two directions is a good signal this is right. ChatGPT's addition worth taking: explicitly list **client responsibilities and exclusions** in the assessment output. That's scope protection for a fixed-fee engagement.

---

## Three things neither analysis caught

### A. Changed-after-close detection ⭐ build this

The single most useful thing you can do that QBO cannot, and it's cheap.

**The problem:** you close March. In June, someone — the client, their spouse, a prior bookkeeper, QBO's own auto-categorization — edits a March transaction. Your March financials no longer match what you delivered. You have no way to know, because QBO's audit log is API-invisible (matrix row confirmed).

**The solution needs no audit log:** at close, store a snapshot of the closed period's trial balance and a hash of every account balance. On every subsequent sync, recompute and compare. If a closed period's numbers move, the app tells you immediately, names the accounts, and shows the delta.

**Why it matters for you specifically:** this is the finding that protects *you*. When a client says "these numbers are different from what you sent me," you either have an answer or you have an argument. Deterministic, no API gap, no AI involved.

`VL-CLOSED-PERIOD-DRIFT-001`

### B. Forced-reconciliation detection

QBO lets a user finish a reconciliation with a non-zero difference by posting an automatic adjustment to **Reconciliation Discrepancies**. That account having any balance means someone forced a reconciliation rather than finding the cause — a classic inherited-books problem, and directly detectable from the chart of accounts.

Pairs with **Opening Balance Equity**: a non-zero OBE balance is the other classic signature of a file someone set up themselves.

`VL-FORCED-RECON-001` · `VL-OBE-BALANCE-001`

### C. Unsafe auto-categorization pattern detection

Reddit complaints about QBO auto-adding transactions without review are a real signal, and it connects to something already in the spec: QBO bank rules with **auto-add enabled** post transactions with no human review at all. A bad auto-add rule can silently miscategorize months of activity.

You can ingest the bank rules export (already in the Import Bridge source table). A rule with auto-add on, matching a broad condition, is worth flagging — and if its category doesn't match how similar transactions were historically coded, that's a rule actively creating cleanup work.

`VL-AUTOADD-RULE-001`

---

## Where I disagree: the priority order

ChatGPT's order puts Control Grid first and Cleanup Assessment last. **For your situation, invert those two.**

The Control Grid serves monthly close work across a portfolio — valuable when you have clients. The Cleanup Assessment serves *getting* clients: it prices the engagement, justifies the price, and doubles as the sales artifact. You have zero clients. Build the thing that helps you get one.

**Revised order:**
1. **Cleanup Assessment** (read-only, no writes, immediate business value)
2. **Transaction Relationship Guard** (the error class that actually matters)
3. **Many-to-one statement matching** (or Page 4/5 cry wolf and you stop trusting them)
4. Account-Month Control Grid
5. Changed-after-close detection
6. Client Accounting Control Profile
7. Balance-sheet evidence workpapers
8. Sensitive-Write Preflight risk tiers
9. Client Exception Packet

---

## The thing worth saying about scope

This is now the fourth substantial round of features added to a spec for an app whose first vertical slice is not yet built. Steps 1.0–1.2 are done. The duplicate-detection slice — one rule, end to end — has not shipped.

Everything above is genuinely good. It is also, in total, several months of work. The risk isn't that any individual feature is wrong; it's that the spec keeps growing while nothing runs against a real client's books.

**Suggestion:** freeze the spec here. Treat this document and `CLEANUP_MODE.md` as the backlog, not the plan. Build the vertical slice, then the Cleanup Assessment, then go get a client — and let their actual books tell you which of these nine matter. Half of them will turn out to matter more than expected and two will turn out not to matter at all, and no amount of analysis will tell you which in advance.
