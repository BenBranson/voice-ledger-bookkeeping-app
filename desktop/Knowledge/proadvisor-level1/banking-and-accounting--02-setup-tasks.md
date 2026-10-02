---
title: Setup tasks
collection: proadvisor-level1
course: Banking and accounting - Level 1
retrieved: 2026-09-27
ui_verified: false
---

# Banking and accounting: Setup tasks

My own summary of lesson 2. It covers a tour of the Accounting app, connecting bank and credit card accounts, and creating bank rules. Bank rules are covered in the most detail.

## 1. The Accounting app
Open it from **All apps** in the left menu, or from the app carousel on **Home**. Its screens:

| Screen | Purpose |
|---|---|
| **Client overview** | *Accountant-only view*: you see it when you open the client from Intuit Accountant Suite / QBOA, and the client can't. It shows a snapshot of subscription and integrations, banking activity, **common issues**, and transaction volume for a date range. Use it when onboarding a client and for regular health checks. |
| **Books review** | *Accountant-only*. Steps you through month-end: transaction review, account reconciliation, final review, and wrap-up (sending results to the client). You can also use it for a one-off cleanup. **Books Close** is an Intuit Accountant Suite add-on that runs month-end close across many clients in one workspace. |
| **Bank transactions** | The bank feed. Daily imports from connected bank and credit card accounts, to review, approve, or adjust. |
| **Integration transactions** | Transactions from connected sales and expense channels (Amazon Business, Shopify, PayPal, Squarespace, Square, Wix, and others). These carry item-level detail that a single bank line doesn't have. For example, an Amazon charge shows what was bought instead of one lump sum. |
| **Receipts** | Upload scanned receipts. QBO extracts the data, and the receipt is then matched to an existing transaction or used to create a new one. |
| **Reconcile** | Choose an account and reconcile it against the bank or credit card statement. |
| **Rules** | Bank rules and integration rules that categorize incoming transactions automatically. |
| **Chart of accounts** | The backbone of the books. Customize it per client; a service business needs different accounts than a product business. |
| **Recurring transactions** | Templates for sales and expense forms, for example monthly rent as a recurring bill. |
| **My accountant** | Where you and the client exchange information requests and shared documents. |
| **Live Experts** | A paid add-on staffed by Intuit's QuickBooks-certified bookkeepers. |

## 2. Connecting bank and credit card accounts
The client can connect as many accounts as they want.
1. **Sign-in.** Go to **Bank transactions** and click **Connect account** for the first account, or **Link account** for later ones. The **client** should enter their own bank credentials; you can help over a phone or video call. For some banks the primary account holder has to sign in.
   - Some banks let accountants have read-only access. That's useful, but **don't use it to set up the connection**.
   - **Never accept the client's banking password.** It's a security breach and a serious risk to you. If the client is nervous about security, point them to Intuit's "How we keep your data safe" article.
2. **Verification.** This depends on the bank: usually two-factor authentication (a code by voice, SMS, or email), sometimes security questions. If verification fails, the client may have to download, sign, and send a form.
3. **Chart of accounts.** Every connected account needs a matching account in the chart of accounts. Add one if it's missing.
4. **Opening balance.** Once the account connects, QBO usually fills the opening balance with the current bank balance. Find out what that balance really is and where it came from. For example, owner money put into a new business should be recorded as owner's equity.

ProAdvisor tip: when connecting, the client picks how far back to import, and each bank has its own limit. To go back further, **upload a .csv file** manually. This works for new connections and for accounts that are already linked.

**QuickBooks Checking** is Intuit's own small-business bank account. Once the client is approved, its transactions sync automatically, with no connection step.

## 3. The Bank transactions screen
- The **account dropdown** (top left) switches between accounts. Use **Reorder accounts** and the pencil icon to change the order of the tiles, then Save.
- **Update** refreshes the feed if the latest transactions haven't arrived. Normally the feed arrives daily without any action.
- The **Link account** dropdown has **Upload from file**, **Manage connections**, and **Order checks**. Upload from file is for connection errors (uncommon) or importing further back than the bank allows.
- **Account tiles**: one per connected account. Each shows the bank balance, the QuickBooks balance, and the number of pending transactions. The pencil opens **Edit Account**: name, account type, detail type, description, and a **Lock account** option.
- **Tabs**:
  - **Pending**: not yet matched or categorized.
  - **Posted**: matched or categorized, now in the books. Undo or uncategorize from here to send an item back to Pending.
  - **Excluded**: removed from the feed. **Use Exclude only for duplicates**, such as a transaction imported from a file and then again through the bank connection. Personal transactions are **not** excluded; categorize them as **owner's draw**.
- **All transactions** filter: Money in, Money out, Ready to post, Suggested matches, Transfers, Rules, and others.
- The small **List settings** gear on this screen is different from the main General Settings gear. It controls columns (Date, Check No., Bank description, Spent, Received, Files, Requests), automation, display, and transaction-detail settings.

## 4. Bank rules
**Purpose:** automatically assign the transaction type, category, payee, and (if the client uses them) class, project, and location to feed transactions that don't match an existing transaction. This saves time and keeps categorization consistent.

**Where:** Transactions > **Accounting** app > **Rules** > **New rule**. This opens the **Create rule** panel. There are two tabs, **Bank rules** and **Integration rules**.

A rule has **conditions** (which transactions to catch) and **actions** (what to do with them).

### Conditions (up to 5 per rule)
1. **Apply this rule to transactions that are**: **Money in** or **Money out**, **in** a chosen bank or credit card account, or **All bank accounts**. *Pitfall:* a rule tied to one specific account doesn't carry over if the client later changes account details.
2. **and include the following: Any / All**. Any means at least one condition must match; All means every condition must match. Choose carefully once you have more than one condition.
3. **Field** to test:
   - **Bank text** (bank detail): the raw data from the bank, which can include store number, city, state, phone, date, and cryptic abbreviations. Expand a feed line to see it.
   - **Description**: QBO's shortened, cleaned-up version of the bank text.
   - **Amount**.
   - The course says a Bank text rule is often more useful, because it checks both the bank detail and the description, while a Description rule checks only the description.
4. **Operator** for text: **Contains**, **Doesn't contain**, **Is exactly**.
   - **Contains**: catches every outlet of a chain. Enter just the chain name, not the store number or city. Make sure the text is unique; it must not also appear in other vendor names. *Example pitfall:* a gas station and a grocery store that share a brand name would both be caught.
   - **Doesn't contain**: filters specific transactions out of the rule.
   - **Is exactly**: an exact match, for example one specific location.
5. **Amount** operators: **Doesn't equal, Equals, Is greater than, Is less than**. For example, "Is less than" keeps unusually large charges out of the rule so a person reviews them.
6. **+ Add a condition** to combine, for example Bank text Contains "Fuel" AND Amount Is less than 75.00.
7. **Test rule** shows how many currently pending transactions the rule would apply to. If the count isn't what you expected, change the conditions.

### Actions ("Then")
1. **Assign** or **Exclude**. Exclude is rare; one example is a card that downloads pending transactions that later disappear. Excluded items go to the Excluded tab.
2. **Transaction type**:
   - Money out: **Expense, Transfer, Check, Credit card payment**.
   - Money in: **Deposit, Transfer, Credit card payment**. For money-in, best practice is to use third-party app integrations where possible, so rules aren't needed.
3. **Category** (a chart of accounts account) for plain money movements like fuel, supplies, or insurance, **or Product/service** for spending tied to what is sold or delivered, such as job materials.
4. **+ Add a split**: divide the transaction across accounts by **percentage or amount**. Example: a phone bill that includes a new handset goes partly to Equipment and partly to Services.
5. **Payee**: optional but recommended. The customer for money in, the vendor for money out.
6. **Customer** (money out): assign the cost to a customer, project, or sub-customer so it shows on **P&L by Customer**.
7. **+ Assign more**: **Replace bank memo** with your own text, optionally keeping the existing bank memo too.
8. **Auto-add** ("Automatically confirm transactions this rule applies to"):
   - **On**: the rule both categorizes and posts transactions, with no review. **Use it with caution and only once you're experienced with rules.** If you use it, add an amount condition so unusually large charges fall out of the rule and stay in Pending.
   - **Off**: the rule fills in the details, but the transaction stays in **Pending** for one-click confirmation, or editing if the rule got it wrong.
9. **Rules list**: from here you can edit, copy, disable or enable, move, and delete rules. **Order matters:** QBO applies rules in numerical priority order, and **only the first matching rule applies** to a transaction. Drag rows to change priority.

### Exporting and importing rules between clients
Rules that work well for one client can be reused for others:
1. In the source client, go to **Rules** > the dropdown next to **New rule** > **Export rules**. This downloads an **.xls** file. Don't edit the file; it has to stay in its specific format.
2. In the target client, go to **Rules** > dropdown > **Import rules**. Upload the .xls, **select the rules to import**, then **map the rule details** (for example, categories) to that client's accounts. QBO pre-fills matching names, and you may need to create new ones. Then **Import** and **Finish**.

### Practice (sample company)
The task: a rule so one vendor's purchases are coded to promotional costs but still reviewed before posting.
- Rules > New rule. Give it a unique name. Money out, All bank accounts.
- Condition 1: Bank text Contains the vendor name. Condition 2: Amount Is less than $250.
- Type Expense, category **Promotional**, payee the vendor. **Leave Auto-add off** so the transactions can be reviewed. Save.

## Pitfalls and checks
- Never take the client's bank password.
- Check the opening balance the connection creates, and reclassify it (usually to owner's equity) if needed.
- Personal spending goes to owner's draw, not Excluded.
- Bank rule text must be unique, or it will catch other vendors.
- Leave Auto-add off until a rule is proven, and cap auto-added rules with an amount condition.
- Rule priority determines which rule wins. Review the Rules list order when results look wrong.

## Knowledge check
The setup-tasks knowledge check at the end of this lesson is ungraded but counts toward unlocking the exam. I did **not** answer it; it is left for Ben.
