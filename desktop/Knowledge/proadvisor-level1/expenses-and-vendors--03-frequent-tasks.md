---
title: Frequent tasks
collection: proadvisor-level1
course: Expenses and vendors - Level 1
retrieved: 2026-09-27
ui_verified: false
---

# Expenses and vendors: Frequent tasks

My own summary of lesson 3. It covers the money-out workflow, purchase orders, expenses and checks, bills and bill payments, and the ways to upload receipts and bills.

## 1. The money-out workflow: which transaction to use

The first question is whether the client paid the vendor at the moment of purchase.

| Situation | Transaction | Accounts it hits | Basis |
|---|---|---|---|
| Paid at the time of purchase (card, cash, debit) | **Expense**, entered by hand or categorized in Bank transactions | Cash/bank or credit card | Cash-basis |
| Paid at the time of purchase **by paper check** | **Check**, not Expense. You can print a check or record a handwritten one. | Bank | Cash-basis |
| Pay later (vendor gives terms) | **Bill** now, then **Pay bill** (a Bill Payment) when paid | Accounts payable, then bank | Accrual-basis |
| Before either path, if the client wants it (Plus and Advanced only) | **Purchase order** | No posting | Non-posting |

- A bill is the mirror image of an invoice: the client sends invoices to customers and receives bills from vendors.
- For either path, the receipt or bill can be uploaded to create a new transaction, or attached to one that already exists.
- The course points to a PDF, "QuickBooks Sales and Expenses: Features, forms, and workflows", as the quick reference for this flow and its terms.

## 2. Purchase orders (Plus and Advanced)
- A PO documents a request to a vendor for specific items at an agreed quantity and price, with a promise to pay. It is **non-posting**: it doesn't change any account balance.
- How it works: the client creates the PO, the vendor delivers and invoices, and the client pays.
- Why clients use them: easier tracking (check that what arrived matches what was ordered), clear communication with the vendor, easier fulfilment for the vendor, and better control of spending and cash flow.
- Create one with **+ Create > Purchase order** (under Vendors).
- New POs have status **Open**. When the goods arrive, change **Purchase Order status** to **Closed**.
- **Copy** (top right of the form) can create a duplicate, or copy the PO's data into another transaction type: Bill, Check, Expense, Credit Card Credit, and others. Copying a PO into a bill or expense is the normal way to carry it forward.
- The setting must be on first: Account and settings > Expenses > **Use purchase orders**. It also requires the items table setting (see the Setup tasks lesson).

## 3. Recording expenses
**Best practice: connect the client's bank and credit card accounts.** Downloaded transactions land in **Bank transactions**, where you categorize each one or match it to a transaction already recorded. Most expenses are handled this way instead of being keyed in. The Banking and accounting course covers it in detail.

**Enter an expense by hand** when the client wants a large purchase recorded right away, or for reporting reasons. When the bank feed later brings in the payment, QuickBooks suggests a match to the manual entry.
1. **+ Create > Expense**. Choose the **Payee**, or **+ Add new** if the vendor doesn't exist yet.
2. Choose the **Payment account** (the account the money came from), the **Payment date**, and the **Payment method**.
3. Under **Category details**, choose the expense account for each line, then add a description and amount. Split across several lines if needed.
4. Optional: add product or service lines under **Item details**.
5. Optional: a **Memo**. It shows in the register, on printed checks, and in reports.
6. Attach the receipt, then **Save and close**.

**Autofill with Intuit AI:** start the expense by uploading the receipt (PDF, PNG, JPEG, or HEIC) in the **Autofill** panel. You can select a file, drag it in, or use **Snap photos**, which shows a QR code for a phone camera. QuickBooks reads the receipt, fills in the form, and attaches the file. Turning on **Show breakdown** splits the receipt into one category line per item. Review the lines, then Save and close.

**Items vs categories:** money-out transactions can use items (products and services) instead of categories, or both together. Using both means splitting the transaction. Items give more detail than the chart of accounts, for example tracking specific job materials inside "Job supplies". To show the item table on expense forms and in the bank feed, turn on gear > Account and settings > Expenses > **Show Items table on expense and purchase forms**.

**Always record the payee accurately.** It matters for four reasons:
- The records are correct.
- Transactions are easier to match in Bank transactions, which makes reconciliation simpler.
- Reports mean something, for example **Transaction List by Vendor**, 1099 reporting, and budgeting.
- The vendor's profile shows the full spending history with that vendor, which helps with relationships and negotiating.

Practice solution (check): **+ Create > Check**. Choose the Payee (the mailing address fills in automatically), set Bank account to Checking, fill in **Check no.**, choose the category, add a description and amount, then **Save and close**. The check then appears in **Expense transactions**.

## 4. Recording and paying bills
- Recording a bill **debits** an expense account (the cost shows on the P&L) or an asset account (the balance sheet), and **credits Accounts Payable**. When the bill is paid, both AP and the bank balance go down.
- **Enter a bill:** **+ Create > Bill**. Choose the vendor, **Terms**, **Bill date** (the due date follows from the terms), and **Bill no.** Fill in **Category details** with the account, description, and customer/project if needed. Attach the vendor's invoice, then Save and close.
- **Autofill this bill:** upload the vendor's invoice and let Intuit AI fill in the lines. If the vendor on the invoice isn't in QuickBooks, a **New vendor found** alert offers two choices:
  - **Save without payment info** adds the vendor.
  - **Ask for payment info** adds the vendor and emails them an invitation to enter their own details, including bank information for direct payment.
- Saved bills sit in the **Unpaid** tab on **Expenses & Pay Bills > Bills**.
- Bills sent through the **QuickBooks Business Network** arrive in the **For review** tab with source "QuickBooks Vendor". After you approve one, it moves to Unpaid.
- **Upload multiple bills:** on the Bills screen, click the **Add bill** dropdown and choose **Upload multiple bills**. Intuit AI creates a draft for each file, to review and then create or match.

**Paying bills**
- **With Bill Pay:** on the Bills screen, use **Schedule payment** in the Action column for one bill. For several, tick the bills and choose **Schedule payment** from the batch actions. You choose the payment account and method (check or ACH). When a Bill Pay payment clears the bank, it **auto-matches** and doesn't appear in Bank transactions for manual review. Only Bill Pay withdrawals are matched this way, and not every transaction is eligible.
- **Without Bill Pay:** record the payment by one of these routes:
  - The Action dropdown on a bill, then **Mark as paid**. The same dropdown also has View/edit, Duplicate, Delete, and Manage payment info.
  - **Mark as paid** inside the bill itself.
  - Either route opens a **Bill Payment** form for that vendor. It lists **Outstanding Transactions**; tick the bill or bills being paid, then Save and close.
- **Several vendors at once:** **+ Create > Pay bills**. Choose the **Payment account** and **Payment date** (and a starting check number if needed), tick each payee's bills, adjust the payment amounts, then **Save and close** (or Save and print).

Practice solution (bill): **+ Create > Bill**, choose the vendor, set **Terms** to Net 30, choose the category (for example Advertising), add a description and the amount, then **Save and close**. The bill then appears in Expenses & Pay Bills.

## 5. Ways to upload receipts and bills
You don't have to start with a form. An upload can create a draft transaction, or be matched to one that already exists.
- **Business Feed > Autofill panel:** upload a PDF, JPG, or PNG and pick the transaction type to create (bill, expense, invoice, or estimate). AI fills it in for you to adjust and save.
- **Purchase notifications:** if the client links a Mastercard and a phone number (the **Purchase notifications** button on the Expenses screen), each purchase triggers a text message with a link to photograph the receipt. AI then matches the receipt to the bank transaction, ready for review in Bank transactions.
- **Single or multiple upload:** use the **Bills** screen (Add bill > Upload multiple bills > Upload from this device) or the **Receipts** screen in the **Accounting** app.
- **Email:** every company gets a unique address ending in @assist.intuit.com, shown on the Bills and Receipts screens. Anyone can email bills or receipts to it, including vendors and the client's staff. They are classified and appear for review. Admins can block senders.
- **Google Drive:** go to Receipts > **Upload receipts** dropdown > **Upload from Google Drive**. You must be signed in to that Drive account.
- **QuickBooks mobile app:** snap a photo of the receipt, and it lands on Accounting > **Receipts** for review.
- The Receipts screen has **For review** and **Reviewed** tabs. The Action column suggests **Match**, **Review**, or **Create bill**.

ProAdvisor tip: keeping the original receipt or bill attached makes the records accurate and audit-ready, because the source document is required if the client is audited.

## Pitfalls and checks
- A paper check goes in as a **Check**, not an Expense.
- If you enter an expense by hand, match it (don't add it again) when the bank feed brings in the same payment, or you'll double-count.
- Every autofilled transaction should be reviewed before saving.
- Paying a bill outside Bill Pay: record it as a **Bill Payment** against the bill. Recording it as a separate expense leaves the bill open in AP and double-counts the cost.
- Useful report: **Transaction List by Vendor** for spending by payee.

## Knowledge check
The two questions at the end appeared to be already answered (greyed out). I left them untouched.
