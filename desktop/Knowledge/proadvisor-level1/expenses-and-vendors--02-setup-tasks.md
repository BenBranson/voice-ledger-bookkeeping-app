---
title: Setup tasks
collection: proadvisor-level1
course: Expenses and vendors - Level 1
retrieved: 2026-09-27
ui_verified: false
---

# Expenses and vendors: Setup tasks

My own summary of lesson 2: finding your way around the Expenses & Pay Bills app, setting up vendors (including contractors), and the company settings that control expense entry.

## 1. The Expenses & Pay Bills app
You can open it two ways: **All apps** in the left menu, or the app carousel on the **Home** screen. Its screens:

| Screen | What it's for |
|---|---|
| **Expense transactions** | Every money-out transaction in a date range. Filter by transaction type using the dropdown. The **Filter** button narrows by status, delivery method, date, payee, and category. The **List settings** gear (top right) shows or hides columns such as attachments, memo, and due date. Tick the checkboxes to run batch actions: print or order checks, pay bills, or categorize several expenses at once. |
| **Vendors** | The vendor list, with contact details and the open balance owed to each vendor. Contractors appear here too. |
| **Bills** | Bills received that will be paid later. Tabs: **For review / Unpaid / Paid**. Filter with the **Bill Date** range and the **Vendor** dropdown. It also shows an email address you can forward receipts and bills to so they autofill. |
| **Bill payments** | Payments made through QuickBooks Bill Pay (only if the client uses Bill Pay). |
| **Mileage** | Trips tracked automatically in the QuickBooks mobile app, or added manually. Clients often forget mileage as a deduction, and this screen helps separate business miles from personal miles at year end. |
| **Contractors** | Vendors marked "track payments for 1099". A contractor added here also appears on the Vendors list, flagged for 1099. From here you can pay contractors and prepare 1099s (buttons: View 1099 filings, Prepare 1099s, Add a contractor, Pay contractors). If the client pays contractors through payroll, the contractor may not appear here, and their 1099 comes from payroll instead. |
| **1099s** | Where you prepare and e-file 1099s. Tabs: E-file, Recipients & W-9s, Completed forms. |

Terms:
- **Vendor**: a person or business that sells the client products or services.
- **Contractor**: a vendor who provides services and may need a 1099 at year end.
- **Bill**: an amount received from a vendor that will be paid later (accounts payable).

## 2. The Vendors screen
Controls on the screen:
- **Pay vendors**: starts Bill Pay activation if Bill Pay isn't already on. Its dropdown can also prepare 1099s and order checks.
- **New vendor**: adds a vendor. Its dropdown can import vendors from a CSV, Excel, or Google Sheets file, or add several vendors at once with the batch transactions feature.
- **Money bar**: shows unbilled, unpaid (overdue and open), and recently paid amounts. Click any segment to filter the list.
- **List settings gear**: shows or hides columns such as address and phone, and whether each vendor is 1099-eligible.
- **Checkboxes**: open the **Batch actions** banner, which can email vendors or make several vendors inactive at once.
- **Action column**: suggests the next step for each vendor, for example **Create bill** or **Pay balance**. The dropdown can create a bill, expense, purchase order, or check. You can make a vendor inactive only if their balance is zero.

## 3. Fields on the New vendor panel (fill in as many as you can)
- **Name and contact**
  - **Company name** prints on bills and purchase orders. **Vendor display name** is what QuickBooks shows everywhere, and it must be unique across customers, vendors, and employees.
  - If a business is both a customer and a vendor, tell the two records apart with punctuation, for example "Blue Star" and "Blue_Star".
  - As you type the company name, QuickBooks Business Network matches may be suggested.
  - Enter an email: it becomes the single source of truth for the vendor and lets QuickBooks send 1099s electronically. You can enter several addresses separated by commas, for example one for purchase orders and one for remittance advice.
  - **Name to print on checks** defaults to the display name. Change it when the legal payee is different, such as the entity name or the owner's name.
- **Address**: the remit-to address where payments are mailed. It also prints on the 1099. **Preview address** opens it in Google Maps.
- **Notes and attachments**: internal notes the vendor never sees (products, specifications, shipping account). Attachments can be up to 20 MB each, which makes this a good place to keep W-9s and certificates of insurance.
- **Payments (Bill Pay ACH info)**: the vendor's bank account number (5 to 17 digits) and routing number (9 digits) for Bill Pay. Double-check them, because money sent to the wrong account may not be recoverable.
- **Additional info: Taxes**
  - **Business ID No. / Social Security No.** is the vendor's TIN, used on the 1099.
  - Ticking **Track payments for 1099** makes the vendor a contractor: they appear on the Contractors screen and in the 1099 workflow.
- **Additional info: continued**
  - **Billing rate (/hr)** appears only when the client uses Projects (Plus and Advanced plans).
  - **Terms**: for example Due on receipt, Net 15, Net 30.
  - **Account no.**: the client's account number with the vendor. It prints on the check memo, which helps with utility payments.
  - **Default expense category**: the account used by default on bills and expenses for this vendor. You can override it on each transaction.
  - **Opening balance**: leave it empty in almost every case. If you do use it, the offsetting entry goes to **Opening Balance Equity**. It is better practice to enter the actual open bills, because they are easier to troubleshoot later.

Practice solution from the course (sample company): go to Expenses & Pay Bills > **Vendors** > **New vendor**. Enter first and last name, company name, address, email, and phone. Leave Opening balance at zero, set **Terms** to Net 30, enter the Business ID No., tick **Track payments for 1099**, then **Save**.

## 4. Contractors and 1099s
- The IRS requires a 1099 for any independent contractor, freelancer, or unincorporated vendor paid above the year's threshold by check, cash, or ACH. Check current IRS guidance for the threshold.
- Collect a completed **W-9** *before* the engagement or the first payment. Without one you may have to renegotiate rates later, and the client could be required to withhold tax.
- Ways to pay a contractor: by check, or electronically through **QuickBooks Contractor Payments** or **QuickBooks Bill Pay**.
  - **Contractor Payments** (a version of QuickBooks Payroll): unlimited next-day direct deposits that sync to the books. Contractors can be invited to fill in their W-9 and bank details themselves.
  - **Bill Pay**: pay vendors and contractors in one place. Unlimited 1099s are included on the Bill Pay Premium and Elite plans.
- ProAdvisor tip: follow the IRS and Department of Labor guidance on whether someone is a contractor or an employee.

## 5. QuickBooks Bill Pay (an add-on)
- Lets the client pay bills from inside QuickBooks and schedule future payments to avoid late fees.
- **Bill Pay Basic** is available in Simple Start, Essentials, Plus, and Advanced. Turn it on from Intuit Accountant Suite / QBO Accountant, or from the client's own company. The business owner completes a short application that verifies the business and connects a bank account.
- Basic includes 5 free ACH payments a month. Clients with heavier AP can upgrade to Premium or Elite.

## 6. QuickBooks Business Network
- Connects QuickBooks businesses with each other. An invoice a vendor sends through the network arrives in the client's QuickBooks as a bill ready for review, with no manual entry. Contact details stay current automatically.
- Accountants can join too, and any member can invite vendors to join.
- The client controls whether other members can find them: **Settings > Account and settings > Advanced > Business Network > Allow members to find me**.

## 7. Settings that affect expenses (gear > Account and settings)
**Expenses tab > Bills and expenses**
- **Show Items table on expense and purchase forms**: adds a product/service line table to purchase orders, expenses, bills, and vendor credits, and shows it in Bank transactions. You need it for inventory, and it helps other clients too. **Turning it off also turns off Use purchase orders.**
- **Track expenses and items by customer**: adds a customer column to expense forms.
- **Make expenses and items billable**: adds a billable column, with an optional default markup percentage and a choice of tracking billable income in one account or several. Level 2 covers this in detail.
- **Default bill payment terms**: standard terms applied to new bills.

**Expenses tab > Purchase orders** (Plus and Advanced only)
- **Use purchase orders**: records the intention to buy.
- Custom fields (managed under Settings > Lists > Custom fields), custom transaction numbers, and a default message on purchase orders.

**Expenses tab > Messages**
- The default email sent with purchase orders: greeting, subject line, and body, plus options to CC yourself or other addresses.

**Advanced tab > Automation** (affects all transactions, not only expenses)
- **Pre-fill forms with previously entered content**: copies fields from the last transaction for that name. It speeds up entry when a vendor is always coded the same way, but it causes wrong entries if nobody reviews the pre-filled lines. Use with care.
- **Automatically apply credits**: mostly affects AR, but it also affects AP. A prepayment to a vendor creates a vendor credit, which then auto-applies to the next bill, and that may not be what you want.
- **Automatically apply bill payments**: applies a payment to the oldest open bill. It causes problems when the client doesn't pay oldest-first, which is common in construction where bills are paid as jobs complete.

## Pitfalls
- Opening balances on vendors create Opening Balance Equity. Enter the real open bills instead.
- Vendor display names must be unique across all name lists.
- Get the W-9 before paying a contractor.
- Turning off the items table silently turns off purchase orders.
- Automatic credit and payment application can put payments on the wrong bills. Check open bills after entry.

## Knowledge check
This lesson ends with two ungraded knowledge-check questions. They count toward unlocking the exam, and they appeared to be already answered. I did not answer or change them.
