---
title: Occasional tasks
collection: proadvisor-level1
course: Expenses and vendors - Level 1
retrieved: 2026-09-27
ui_verified: false
---

# Expenses and vendors: Occasional tasks

My own summary of lesson 4. It covers vendor refunds and credits, paying down credit cards, recurring expense transactions, and the AP and expense reports.

## 1. Vendor refunds vs vendor credits
The first question is whether the vendor gave money back (a **refund**) or a credit to use later (a **credit**). Either can come from a return, a settled dispute, a promotion, or a goodwill gesture.

### Refund (money received back)
- QBO has **no "vendor refund" transaction type**. Record it on a **Bank Deposit** (**+ Create > Bank deposit**), in the **Add funds to this deposit** section.
- **Received from**: the vendor. **Account**: the **same category/account used on the original purchase**. Add a description and the amount, then Save and close.
- Effect: cash goes up, and the original expense (or liability) account goes down.

### Vendor credit (amount owed to the client, used later)
- Posts as a **debit to Accounts Payable**. It reduces what the client owes the vendor, lowers AP on the balance sheet, and reduces the expense account, so total expenses on the P&L go down.
- Apply it to an existing open bill, or to a future purchase from the same vendor.
- **Create one from scratch:** **+ Create > Vendor credit** (in the Vendors column).
  - Choose the vendor and the **Payment date** (the date the credit was received). Optionally add the vendor's credit number in **Ref no.**
  - Use **Category details** for a promotion or discount (for example, a "Discounts given" account). Use **Item details** if the original bill was for items in the products and services list.
  - Add a description and amount. Mark it billable or assign a customer if the original expense was billed to a customer.
- **Create one from the original bill:** open the paid bill and either choose **More > Copy to vendor credit**, or use **Copy** (top of form) > **Copy data to another transaction** > **Vendor Credit** > Copy. The bill's lines copy across. Edit them for a partial credit, for example by removing items that weren't returned.
- **See it:** the credit appears on the vendor's **Transaction List** (Vendors > the vendor's name).
- **Apply it:**
  1. On the vendor's open bill, click **Mark as paid** in the Action column.
  2. The **Bill Payment** screen shows the bill under **Outstanding transactions** and the credit under **Credits**. QBO has already applied the credit, so the payment amount is the balance net of the credit.
  3. To keep the credit for later, untick it.
  4. Save. The bill payment then shows on the vendor's Transaction List at the net amount.
- The **Automatically apply credits** setting (Advanced > Automation) can apply credits for you. See the Setup tasks note.

## 2. Paying down credit cards
Two common client mistakes:
1. **Wrong transaction type.** Entering the card statement as a **bill** and the payment as a **bill payment**. This causes mismatched account balances and distorts cash-basis financial statements. Level 2 Banking covers why.
2. **Miscategorizing the payment.** Recording the card payment as an **expense**. If the card is connected to the bank feed, the individual card charges are already expensed, so expensing the payment as well **double-counts expenses**.

**Correct method:** **+ Create > Pay down credit card** (in the "Other" column). It records the payment as a transfer of money from the bank account to the credit card liability.
- **Which credit card did you pay?**: the credit card account.
- **Payee (optional)**: the bank that issued the card.
- **How much did you pay?** and **Date of payment**.
- **What did you use to make this payment?**: the bank account the money came from. There is also a checkbox for **I made a payment with a check**.
- Memo and attachments, then **Save and close**.

Practice solution: + Create > Pay down credit card. Card = Visa, leave Payee blank, amount $500, today's date, paid from Checking, then Save.

## 3. Recurring expense transactions
- Works for expenses, checks, bills, and purchase orders (and many other forms). Use it for money-out that happens at regular intervals for fixed amounts.
- **You cannot make recurring bill payments or pay-down-credit-card transactions.** A bill can recur, but its payments can't.
- Template types:
  - **Scheduled**: QuickBooks creates the transaction automatically on a set frequency or set dates, for example vehicle lease payments.
  - **Unscheduled**: a saved template you use by hand when needed, for ad-hoc transactions or ones whose details change (a different job each month, varying allocation). Example: one template for a 2-car garage cabinet package and another for a 3-car package.
  - **Reminder**: a hybrid for regular transactions that need editing before they're entered. QuickBooks reminds you instead of posting. Example: sales commissions that can only be calculated after the prior month is closed.
- **Set one up:** gear > **Recurring transactions** (the course also calls this the Recurring transactions screen in the **Accounting** app) > **New**. Pick the **Transaction Type** (for example Bill or Expense), then OK.
  - Give the template a name, such as "Monthly bill for phone".
  - Choose the **Type** (Scheduled, Reminder, or Unscheduled) and **Create __ days in advance**.
  - Set the **Interval** (for example, Monthly on day 1st of every 1 month), the **Start date**, and the **End** (None, By, or After).
  - Complete the rest of the form as normal, then **Save template**.
- Practice solution: gear > Recurring transactions > New > Expense. Name it "Monthly Rent", type Scheduled, choose the payee and the Checking account, Monthly on the 1st, start the first of next month, End = None, category **Rent or Lease**, $500, then Save template.
- ProAdvisor tip: **review the recurring list regularly** so money-out that has stopped (for example, a paid-off loan) doesn't keep being recorded. A customer, vendor, employee, product/service, or account **can't be made inactive while a recurring transaction uses it**.

## 4. Reports for expenses and vendors
Go to **Reports & Analytics > Standard reports**. Two groups matter here:
- **What you owe** (accounts payable): Accounts payable aging summary, Accounts payable aging detail, Bills and Applied Payments, Bill Payment List, Unpaid Bills, Vendor Balance Summary, Vendor Balance Detail, 1099 Contractor Balance Summary, 1099 Contractor Balance Detail.
- **Expenses and vendors** (all purchases, through bills or directly): Check Detail, 1099 Transaction Detail Report, Purchases by Product/Service Detail, Purchase List, Transaction List by Vendor, Purchases by Vendor Detail, Expenses by Vendor Summary, Vendor Contact List, Vendor Phone List.

Summary reports give overview totals. Detail reports list the transactions in a period. List reports show list items such as vendors or products.

| Report | Shows | Use it to |
|---|---|---|
| **A/P Aging Summary** | Unpaid bills and unused credits by vendor, in columns by days past due (Current, 1-30, 31-60, 61-90, 91+) | Get an overview of payables and outgoing cash. **Tie-out: run it with the same "as of" date as an accrual-basis Balance Sheet. The totals must equal the Accounts Payable line.** It only has data if bills are entered before they're paid. |
| **A/P Aging Detail** | Each unpaid bill and unused credit, grouped by days past due | Spot payment trends and confirm vendor credits were applied. The same tie-out to the accrual Balance Sheet applies. To group by vendor instead of age, use **Vendor Balance Detail**, **Vendor Balance Summary**, or the A/P Aging Summary. |
| **1099 Contractor Balance Summary / Detail** | The amount owed to each contractor (open bills only; expenses aren't included) | See balances owed to contractors. **Not** the 1099 amount, because a 1099 reports what was *paid*. Don't use these for year-end 1099s. |
| **Transaction List by Vendor** | Every expense-type transaction (checks, expenses, bills, bill payments, vendor credits, POs) grouped by vendor for a period | Review a vendor's activity and confirm every bill is accounted for. Good for spotting duplicates. |
| **Expenses by Vendor Summary** | Total spent with each vendor in the period | Answer "how much am I spending at X?" and catch overspending. |
| **Check Detail** | Checks written, with a Cleared column showing uncleared ones | QuickBooks' version of a check register. |

**Cash vs accrual:** most reports can run on either basis. **Accounts payable is inherently accrual**, so AP reports have no basis option. Expense reports do have the option, and their totals will differ depending on the basis you choose.

## Pitfalls
- A vendor refund goes on a **Bank Deposit** coded to the original expense account. Don't code it to income.
- A credit card payment goes through **Pay down credit card** (a transfer). Never code it as an expense, and never set up the card statement as a bill.
- Check whether a vendor credit was auto-applied when you pay a bill. Untick it to keep it for later.
- Recurring templates keep posting after the obligation ends. Review them.

## Knowledge check
The two questions at the end of this lesson are **unanswered**. This is the course's remaining incomplete item, and it counts toward unlocking the exam. I did **not** answer them; that is for Ben. They don't block navigation.
