---
title: Frequent tasks
collection: proadvisor-level1
course: Banking and accounting - Level 1
retrieved: 2026-09-27
ui_verified: false
---

# Banking and accounting: Frequent tasks (managing the bank feed)

My own summary of lesson 3. It covers day-to-day work in **Bank transactions**: moving everything in **Pending** to **Posted** accurately. Nothing in Pending is in the books yet.

## 1. How QBO decides what to do with an incoming bank transaction (in this order)
1. **Auto-post match**: the bank line matches a transaction created by QuickBooks Payroll, Payments, or Bill Pay. It posts automatically, never appears in Pending, and shows up in **Posted**.
2. **Auto-post rule**: bank rules with auto-add turned on run next. These also skip Pending and go straight to Posted.
3. **Match to an existing record**: QBO looks for a transaction already entered (expense, invoice, bill, and so on) and suggests a match. The AI can suggest more complex matches, including one bank line against several transactions, and matches with fees.
4. **Bank rules**: if there's no match, the rules list runs in priority order, and only the first rule that fits applies. **A rule isn't applied if a potential match was found.**
5. **Category history**: the AI suggests the category used before for this payee or bank description, and shows a snapshot of that history. If the payee isn't in From/To, it looks at similar transactions. It can also recommend a category from what other businesses use for that vendor, for example suggesting Job supplies for a new hardware store if earlier hardware purchases went there.
6. **Bank description research**: as a last resort, the AI researches the description text, for example recognizing a restaurant and suggesting Meals with clients.

ProAdvisor tip, "trust but verify": the AI and rules speed things up, but you remain responsible for accuracy. Posting daily keeps the books current, so you don't have to wait for month-end to see what's happening.

## 2. Match vs categorize
- **Match**: tie the bank line to a transaction **already recorded** in QuickBooks, such as an invoice payment, bill, or expense. This avoids duplicates.
  - **Exact match**: the recorded transaction and the bank line are the same event. For example, a $75 expense entered by hand and the $75 bank charge. Accepting adds a note to the existing transaction and moves the bank line to Posted. **No new transaction is created.**
  - **Linked match**: the bank line pays an open document. For example, a $750 bill is recorded, but the payment isn't. Accepting **creates a new Bill Payment** (or Receive Payment for an invoice) linked to the bill, and matches the bank line to it. The bill itself isn't replaced. If the bill payment had already been recorded, it would be an exact match instead.
- **Categorize**: only when **no record exists**. Assign an account (for example Supplies) **or** a product/service. You can't assign both on one line without splitting. The expanded row shows: Transaction type, From/To (payee), Account, Product/Service, Customer/project, Billable, and Memo.

## 3. Recommended order for clearing Pending (easiest first, so the list shrinks quickly)
1. **Receipts**: you have the evidence, so these are quick.
2. **Rules and pairs**: frequent, predictable transactions.
3. **Money-out**: usually specific and easy to verify.
4. **Money-in**: often customer payments, but with more nuances, so last.

## 4. The AI-powered list: what the screen tells you
- A **sparkle ("Suggested by AI") icon** marks where the AI suggested a payee (From/To) or a match or category (Match/Categorize).
- **Match/Categorize column**: a link to the suggested match (for example "Deposit - date - amount", or "3 Suggested matches found").
- **Hover over Bank Description** to see the full bank text. Expand a row to see why a match was suggested, with **Find other matches** if it's wrong.
- **From/To**: the AI fills in a vendor or customer it detects in the text. Click the sparkle to see its explanation. The label shows **Potential** if the name isn't in QBO yet, or **Vendor/Customer** if it already exists. Change it or **+ Add new** if it's wrong.
- **Category suggestion panel**: labeled **Top suggestion** or **Consider** depending on how much history there is, with **More info** to expand the row. The expanded row gathers the category, vendor, and customer suggestions in one panel where you can pick the category.
- **"Ready to post"** filter (All transactions dropdown): items the AI rates highly likely correct, such as the same vendor always coded the same way. Tick several and **Post** in bulk; the batch bar also has Edit, Exclude, and Request more info. A "Ready to post" banner appears when there are three or more.

## 5. Asking the client about a transaction
From Bank transactions you can **Request more info**, asking for details or files such as receipts through a link the client replies to. Requests can be assigned to specific people on the client's team.
- Setting: gear > **Account and settings** > **Accounting** tab > **Requests for more information** > toggle **Require sign-in to answer requests** (secure requests). Then add team members (name and email). They don't need a QuickBooks seat and don't count toward user limits.
- Once enabled, the AI assistant checks that the right receipt was uploaded and asks follow-up questions, which cuts down on back-and-forth.

## 6. Customizing the list (List settings gear on Bank transactions)
- **Columns**: Date, Bank description, Spent, and Received are fixed but can be reordered; Action is fixed in place. Optional columns: Check No., Files, Requests, **From/To** (on by default; keep it on, because a payee on every transaction makes spend-by-vendor answers and 1099 prep easy), Customer, Product/Service, Match/Categorize.
- Settings are saved **per client**.
- **Automation: Add new vendors**: QBO automatically adds vendors it identifies to the vendor list.

## 7. Receipts in the feed workflow
Receipts uploaded to **Accounting > Receipts** aren't in the books until reviewed. QBO checks already-recorded transactions for a match to prevent duplicates. It does **not** check items still in the Pending bank feed.
- **No record found**: Receipts > **Review** to correct or complete the details, then **Save and next** / **Save and close**, or **Create expense**.
- **One record found**: hover the receipt icon to preview it. Use the dropdown next to **Match** > **Review**, check the details, then Save and next. Otherwise, Match.
- **Two or more found**: choose the correct one in review.
- ProAdvisor tip: encourage clients who keep receipts in Google Drive or a shoebox to upload them or forward them to the QBO email address, even going back to the start of the year. It keeps the records together, avoids manual entry, and simplifies audits.

## 8. Rule-applied and paired transactions
- Without auto-add, rule hits sit in Pending with a **RULE** label in Match/Categorize. Filter the list by **Rules** to see them together.
- In the expanded row: check the fields and add a customer or project if needed. **Edit rule** opens the Create rule panel to fix the rule for all future transactions. **Categorization history** shows how earlier transactions from the same vendor were coded, which is a good consistency check. Then **Post**.
- **Pairs**: when money moves between two accounts that are **both connected**, QBO detects the matching date and amount on both sides and labels them **PAIR** (for example $2,000 out of Checking and $2,000 into Savings). Accept to record one transfer. If the other side is a credit card, QBO suggests recording it as **Pay down credit card**.

## 9. Money-out matching (partial; see the progress note)
- Filter the list to **Money out**, then sort by **Match/Categorize** to group the suggested matches, or by **Bank Description** to group similar sources.
- Expand a row and check that the date, bank detail, and amount line up with the suggested match. Open the linked record if needed, then click **Match**.

*Notes for the rest of this lesson (the rest of money-out, and money-in) are appended below if they were captured.*

## 10. More on money-out (captured before stopping)
- **Batch actions:** tick several transactions to **Match**, **Edit**, **Exclude**, or **Request more info** all at once. Matched items move to **Posted** and an accounting transaction is recorded.
- **Several suggested matches:** use what you know about the real transaction to pick one (ask the client if you're unsure), select its radio button, then click **Match**.
- **Bill Pay:** payments made through QuickBooks Bill Pay auto-match when they clear the bank and never appear in the list. This only applies to Bill Pay withdrawals, and not all of them are eligible.
- **Categorizing money-out:** filter to Money out and sort by Match/Categorize. You can edit From/To, Product/Service, and Match/Categorize inline. Expand a row to see the Top suggestion panel, and use **+ Add new** for a new vendor. Once posted, the transaction is recorded and added to that vendor's categorization history.
- **ProAdvisor tips for money-out trouble:**
  - **Old checks:** QBO only searches a **90-day window** for matches. With **Find match**, widen the date range. If there's still no match, the check probably wasn't recorded and can be entered as a new expense.
  - **Wrong account or amount:** an expense recorded against the wrong account (credit card instead of debit card) gets duplicated. If a bill was entered at $100 but $130 came out of the bank, the match is missed and the bill gets entered twice. Check the account and amount.
  - **Unknown money in:** research similar past transactions, and ask the client if you're still not sure.

## Not captured (session stopped)
- Money-in: the 7-step **Undeposited Funds / Payment to Deposit** walkthrough, matching deposits and customer payments, and categorizing money-in.
- The end-of-lesson practice task and knowledge check (the knowledge check would have been left for Ben anyway).
