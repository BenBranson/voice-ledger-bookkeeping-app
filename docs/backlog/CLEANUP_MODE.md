# Cleanup Mode — Design Addendum

Source: two QBO 2026 walkthroughs (Accounting Stuff's seven-step guide, and Hector Garcia CPA's two-hour master class). The second is the more valuable of the two, because it's a working CPA demonstrating the exact places QBO's own automation *creates* errors that a bookkeeper then has to find.

---

## 1. The single highest-value feature: the Cleanup Assessment

Before anything else, build this. It serves the business, not just the workflow.

**The problem it solves:** you're planning to quote $300–500 for a cleanup. You cannot price a cleanup you haven't looked at, and you cannot look at it manually without spending an hour you're not being paid for. Hector's own firm charges **$475 minimum just to assess the situation** before quoting the work — that's a real market data point from a CPA running a Miami firm.

**What it does:** connect the client's QBO (read-only), run every deterministic rule across the full available history, and produce a one-page assessment in under ten minutes:

- Months unreconciled, per account, with the last successful reconciliation date
- Balance in Uncategorized Income / Uncategorized Expense / Ask My Accountant
- Count of duplicate candidates, by tier
- Count of miscoded credit-card payments (see §2.1 — the highest-frequency error)
- Count of transactions still sitting in For Review (from an imported screenshot)
- Opening-balance integrity check
- Balance sheet: does it balance, are there negative assets
- **An estimated hours range and a suggested price band**

**Two uses, both valuable:**
1. **You price accurately** instead of guessing and eating the difference on a bad file.
2. **It's a sales document.** Hand the prospect a report showing "your books have 47 uncategorized transactions worth $18,400, three accounts unreconciled since March, and eleven likely duplicate charges" — that sells the cleanup better than any pitch. It's also the most concrete possible demonstration of "Pathfinder for small business, protector of the bottom line."

This is a Type A page. It needs no writes. It could ship before most of the 12-page workflow.

---

## 2. Error classes QBO's own AI creates — buildable as deterministic rules

These come straight from the transcripts. Each is a rule with a clear signature, and each catches a mistake QBO either makes or permits.

### 2.1 Credit-card payment coded to an expense account ⚠ highest value

Hector's exact words: *"This is a huge no-no. You never want the payment to a credit card be sent to an expense account."* And critically — **QBO's AI suggested exactly this**, proposing "general business expenses, advertising and marketing" for an American Express payment.

**Rule:** a transaction whose payee matches a known credit-card account (or whose description matches a card issuer pattern) coded to any expense account rather than the card's balance-sheet liability account.

**Why it matters for cleanup:** this error double-counts expenses — the card's own charges are already expensed, so the payment expenses them a second time. On a messy file it can be thousands of dollars of overstated expense. High frequency, high dollar impact, mechanically detectable.

`VL-CC-PAYMENT-001`

### 2.2 Payroll processor net amount coded to a single expense line

Hector booked an ADP payment straight to salaries and wages and flagged it himself as wrong: the net bank draw isn't the payroll expense. It should split into wages, employer taxes, and withholdings, and *"the 9,912 that you see here is the net amount that comes out of the bank, but the real payroll amount might be a completely different number."*

**Rule:** payment to a known payroll processor (ADP, Gusto, Paychex, Rippling, QuickBooks Payroll, Justworks, TriNet) coded entirely to one expense account.

**Resolution:** guided manual — the app can't know the split without the payroll register, so this becomes a Type C handoff with an instruction to pull the payroll report. Good candidate for Import Bridge: ingest the payroll register PDF, propose the JE split.

`VL-PAYROLL-LUMP-001`

### 2.3 QBO's cleaned vendor name diverges from the original bank description

This is the entire reason the Right Tool Chrome extension exists. QBO rewrites the raw bank text into a "clean" vendor name and *"sometimes they get it wrong."* Right Tool's fix is to display the original description in red underneath.

**You have a better version of this available** — the Import Bridge. Ingest the actual bank statement CSV, match on date and amount, and compare the statement's original description against the vendor QBO assigned. Divergences are miscategorization candidates.

**This is a genuine competitive feature.** People pay a monthly subscription for a Chrome extension that only *displays* the discrepancy. Yours can detect and rank it.

`VL-VENDOR-MISMATCH-001`

### 2.4 Prepaid / deferred expense booked to the wrong period

The billboard example from the first tutorial is the cleanest illustration of where QBO stops: it flagged that general business expenses dropped 100%, identified the $8,750 payment as the cause — and then *couldn't know the correct treatment.* A human had to open the attached invoice, see the campaign ran July 6 – August 2, and reclassify to prepaid expenses.

**Rule:** a large payment (above materiality) to a vendor, where an attached document contains a service period ending after the transaction date.

**This is where Universal Ingestion earns its whole existence.** The signal is only in the attachment, and only OCR gets it out. QBO flagged the anomaly; it could not read the invoice and reason about the period. That gap is exactly your app's thesis: *QBO is good at flagging what looks unusual, but it can't know the correct accounting treatment.*

`VL-PREPAID-PERIOD-001`

### 2.5 Opening balance double-count

From the first tutorial: setting an opening balance *and* having the first transaction be an owner contribution double-counts starting cash. A standard cleanup finding on files someone set up themselves.

**Rule:** account has a non-zero opening balance entry, and an equity contribution exists within N days of the opening date for a similar amount.

`VL-OPENING-BAL-001`

### 2.6 Added instead of matched → duplicate

QBO's own guidance: *"Use match if you've already entered the invoice, bill, expense or payment. Use categorize if the transaction hasn't been recorded yet."* Getting this backwards is the #1 duplicate source, and it's exactly what your existing `VL-DUP-*` rules already catch. Worth noting the cleanup-specific variant: a **bill and a separate expense** representing the same purchase, which your duplicate taxonomy already lists.

### 2.7 The "AI guessed with no history" population

QBO shows a per-transaction indicator explaining its categorization logic — Hector clicked it and QBO said, in effect, *"I have no historical transactions, this is 100% a guess."*

**Worth a spike question:** is that provenance (rule-applied vs. AI-guessed vs. human-entered) exposed anywhere in the API? If yes, it's an enormous cleanup filter — sort the entire file by "categorized by a guess" and review only those. If no, record the negative; it's still worth knowing.

Add to the spike queue as `testCategorizationProvenance`.

---

## 3. The reconciliation gap map

Your stated case — *"some clients haven't reconciled in months."*

QBO reconciles **one month at a time, one account at a time**, and its reconciliation history is API-invisible (already confirmed, matrix row 5.3). So the cleanup bookkeeper has no single view of how deep the hole is.

**Build a grid:** accounts down the side, months across the top, each cell showing reconciled / partially reconciled / never / beginning-balance break. Populated from imported reconciliation reports and statement imports.

Two things it gives you:
- **Scoping** — "eleven account-months outstanding" is the number that sets the price
- **Ordering** — reconciliation must run oldest-first, because a beginning-balance error propagates forward. Working backward wastes the effort.

This has no equivalent in QBO and none in any tool you'd have access to.

---

## 4. Batch fixes — prepare in the app, execute in QBO

Hector's most-used cleanup feature is QBO's **"group and sort by column,"** which clusters the bank feed by vendor so you can categorize forty Adobe charges in one action. He called batch posting *"definitely one of my favorite features."*

**Do not rebuild this.** QBO does it well, in the place where the work happens.

**Do build the plan for it.** The app's Batch Fixes page should output a reviewed, approved batch plan — *these 47 transactions across 12 vendor groups, proposed category per group, total dollars, period impact, reversal plan* — that you then execute in QBO in a few grouped actions. The app does the thinking and the audit trail; QBO does the clicking.

---

## 5. Paper clients

For clients still on paper: this is the Import Bridge's other half. Statements as PDFs, receipts as photos, handwritten check registers. Tier 2 on-device OCR handles most; Tier 3 escalation handles handwriting.

**Cross-foot validation matters most here.** A paper statement that doesn't foot after extraction is the difference between a clean cleanup and one where you've silently transcribed a digit wrong across three months. This is the population where that guard actually pays for itself.

---

## 6. Honest note on your $300–500 price

Every cleanup rule above exists because these files take real time. A client with three months unreconciled, a hundred uncategorized transactions, and paper receipts is not a $300 engagement — Hector's firm charges $475 *just to assess* before quoting the work, and quotes monthly bookkeeping at $750–1,200.

Two suggestions, neither about the app:
- **Price the assessment separately** (even $150–200), then quote the cleanup from what it finds. You stop guessing, and the assessment fee is credited toward the work if they proceed.
- **Band the price by what the assessment measures** — account-months unreconciled and uncategorized transaction count are the two variables that actually drive the hours.

The app makes cleanups faster. It doesn't make a 200-transaction three-month cleanup worth $300. Being able to *show* the client why it's $900 instead is worth more than being able to do it in less time.

---

## 7. What this changes in the build

**New page: Cleanup Assessment (Type A).** Read-only, runs everything, outputs a scoped report with an hours estimate. Buildable early — it needs no writes, and it's the page with the most immediate business value.

**New rules for the backlog**, all Phase 2, all deterministic:
`VL-CC-PAYMENT-001` · `VL-PAYROLL-LUMP-001` · `VL-VENDOR-MISMATCH-001` · `VL-PREPAID-PERIOD-001` · `VL-OPENING-BAL-001`

**New spike item:** `testCategorizationProvenance` — is QBO's rule-vs-AI-vs-human categorization source exposed via API?

**Reconciliation gap map** added to Page 5's cleanup mode.

**Reframe Cleanup Mode:** not just "the 12 pages with a wider date range." It's triage-ordered rather than sequence-ordered — assessment first, then reconciliation oldest-first, then the highest-dollar miscoding classes, then everything else. The sequential close order is right for a monthly close and wrong for a rescue.
