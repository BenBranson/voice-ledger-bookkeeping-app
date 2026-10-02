---
title: Voice Ledger rule catalog (the 31 checks it runs on client books)
collection: voice-ledger
source: Voice Ledger - Rule Catalog.pdf (generated 2026-09-27 from desktop/Sources/Core)
retrieved: 2026-09-27
ui_verified: false
---
# Voice Ledger rule catalog

## VL-DUP-EXP-001: Possible duplicate expense
Where it shows up: Transactions. Detection: Categorization | Resolution: Manual (QBO).
Why it matters: Each economic event should be recorded once. Two postings sharing vendor, amount, date, and payment account are presumptively the same event recorded twice, which overstates expense and understates cash or accounts payable.

## VL-DUP-EXP-002: Possible duplicate expense — paid from two different accounts
Where it shows up: Transactions. Detection: Categorization | Resolution: Manual (QBO).
Why it matters: Each economic event should be recorded once. Two postings sharing vendor, amount, and a nearby date — even from different payment accounts — are presumptively the same bill paid twice (e.g. once by card, once by check), which overstates expense.

## VL-CAT-UNCAT-001: Uncategorized transaction
Where it shows up: Transactions. Detection: Categorization | Resolution: Manual (QBO).
Why it matters: A transaction posted to QBO's default Uncategorized Expense/Income/Asset account was never assigned a real category. It's included in cash totals but not in any meaningful expense or income breakdown, which understates the accuracy of the P&L; until it's recategorized.

## VL-VENDOR-MISMATCH-001: Statement description doesn't match QBO's vendor name
Where it shows up: Transactions. Detection: Categorization | Resolution: Manual (QBO).
Why it matters: A posted transaction's vendor should be the entity that actually appears on the bank statement. If a statement line was matched to a QBO posting with a completely unrelated vendor name, the match itself may be wrong — a real error, not just a wording difference.

## VL-MISSING-PAYEE-001: Expense with no vendor
Where it shows up: Transactions. Detection: Categorization | Resolution: Manual (QBO).
Why it matters: Every expense should be traceable to who was paid. A Purchase with no VendorRef can't be matched to a 1099, can't be searched for later by vendor, and often means the transaction was added straight from the bank feed without anyone actually picking a payee.

## VL-RECON-MISSING-001: Statement line with no matching QBO posting
Where it shows up: Bank Feed Cleanup. Detection: Categorization | Resolution: Manual (QBO).
Why it matters: Every real bank/card transaction should eventually appear as a posted entry in QBO. A statement line with no matching Purchase or Bill on the same account means that activity was never entered — cash actually moved, but the books don't reflect it yet.

## VL-RECON-AMBIGUOUS-001: Statement line matches more than one QBO posting
Where it shows up: Bank Feed Cleanup. Detection: Categorization | Resolution: Manual (QBO).
Why it matters: Reconciliation assumes a one-to-one match between a bank line and a posted entry. When one statement line matches multiple posted transactions equally well, either one of those postings is a genuine duplicate, or two unrelated transactions coincidentally share the same account, amount, and date — either way, reconciliation cannot proceed on this line until a human picks the real match.

## VL-RECON-DIFF-001: Bank statement ending balance doesn't match QBO
Where it shows up: Bank Feed Cleanup. Detection: Categorization | Resolution: Manual (QBO).
Why it matters: A bank or credit card account's balance in QBO should track its real-world statement balance closely. A large gap between the two — beyond what a few days of normal, unreconciled activity would explain — usually means something is missing, duplicated, or miscoded in the posted transactions for that account.

## VL-CC-PAYMENT-001: Credit card payment coded to an expense account
Where it shows up: Cleanup Assessment. Detection: Relationship | Resolution: Staged API write (the only rule in this app that can propose one) or Manual (QBO).
Why it matters: A payment to a credit card settles a liability already incurred when each charge posted — it is a transfer between a liability account and an asset account, never an expense. Coding the payment itself to an expense account double-counts spending that was already expensed once, per charge.

## VL-PAYROLL-LUMP-001: Payroll processor payment coded to a single expense line
Where it shows up: Cleanup Assessment. Detection: Categorization | Resolution: Manual (QBO).
Why it matters: A payroll processor's net bank draw bundles wages, employer taxes, and withholdings into one number. Coding the whole draw to a single wages expense line overstates wages and omits employer tax expense and withholding liabilities entirely.

## VL-OBE-BALANCE-001: Non-zero Opening Balance Equity
Where it shows up: Cleanup Assessment. Detection: Categorization | Resolution: Manual (QBO).
Why it matters: Opening Balance Equity is a temporary holding account QBO uses when a beginning balance is entered. A properly closed-out file has zero in this account — a nonzero balance means an opening balance was never reconciled to the actual books, a common signature of a self-set-up or never-fully-onboarded file.

## VL-BS-NEGBAL-001: Negative asset or liability balance
Where it shows up: Cleanup Assessment. Detection: Categorization | Resolution: Manual (QBO).
Why it matters: Asset and liability balances are conventionally non-negative in QBO's CurrentBalance sign convention. A negative asset balance means the account is overdrawn; a negative liability balance means it's been overpaid or miscoded — both indicate an error worth investigating, not a normal state.

## VL-DUP-VEND-001: Possible duplicate vendor record
Where it shows up: Cleanup Assessment. Detection: Categorization | Resolution: Manual (QBO).
Why it matters: Two vendor records for the same real-world payee split that vendor's transaction history across two IDs, which understates any per-vendor total, misses 1099 aggregation thresholds, and hides price trends over time.

## VL-DUP-BILL-001: Possible duplicate bill
Where it shows up: Cleanup Assessment. Detection: Categorization | Resolution: Manual (QBO).
Why it matters: Two bills from the same vendor, same date, same amount are presumptively the same liability entered twice, which overstates accounts payable and, if both are paid, overstates expense.

## VL-DUP-INV-001: Possible duplicate invoice
Where it shows up: Cleanup Assessment. Detection: Categorization | Resolution: Manual (QBO).
Why it matters: Two invoices to the same customer, same date, same amount are presumptively the same sale entered twice, which overstates revenue and accounts receivable.

## VL-DUP-PAY-001: Possible duplicate payment
Where it shows up: Cleanup Assessment. Detection: Categorization | Resolution: Manual (QBO).
Why it matters: Two Payment records from the same customer, same date, same amount are presumptively the same payment entered twice, which overstates cash received and understates the customer's actual open balance.

## VL-BS-UNDEP-001: Payment still sitting in Undeposited Funds
Where it shows up: Cleanup Assessment. Detection: Categorization | Resolution: Manual (QBO).
Why it matters: A Payment recorded in QuickBooks but not yet included in a bank Deposit sits in Undeposited Funds — a real asset, but not yet cash in the bank. Left there too long, it usually means the deposit was never actually made (or was made outside QBO and never recorded), which overstates readily available cash.

## VL-VENDCREDIT-UNAPPLIED-001: Unapplied vendor credit
Where it shows up: Cleanup Assessment. Detection: Categorization | Resolution: Manual (QBO).
Why it matters: A vendor credit is an asset the business is owed — it should reduce a future bill or come back as cash. Left unapplied indefinitely, it neither reduces expenses nor shows up as available cash, and is easy to lose track of entirely since QBO surfaces no reminder on its own.

## VL-FORCED-RECON-001: Reconciliation was forced despite a discrepancy
Where it shows up: Cleanup Assessment. Detection: Categorization | Resolution: Manual (QBO).
Why it matters: A reconciliation that doesn't balance to zero and is finished anyway with an adjustment means the underlying discrepancy was never actually explained — QBO posts the difference to its own “Reconciliation Discrepancies” account rather than resolving it, which papers over whatever mismatch caused it.

## VL-REPORT-TIE-001: Balance Sheet A/R or A/P doesn't tie to the aging report
Where it shows up: Cleanup Assessment. Detection: Categorization | Resolution: Manual (QBO).
Why it matters: The Balance Sheet's A/R balance should always equal the sum of every unpaid invoice on Aged Receivables (and A/P to Aged Payables) — they're two views of the same underlying open transactions. A mismatch means something posted directly to the receivable/payable account outside the normal invoice-and-payment (or bill-and-payment) flow, and the aging report can no longer explain what's actually owed.

## VL-FEE-AVOIDABLE-001: Possible avoidable fee (late fee, overdraft, or finance charge)
Where it shows up: Cleanup Assessment. Detection: Categorization | Resolution: Manual (QBO).
Why it matters: Late fees, overdraft charges, and finance charges are avoidable costs, not the cost of doing business — flagging them (rather than letting them blend into a generic ‘Bank Charges’ total) gives the owner a chance to negotiate a waiver, fix whatever process caused it (a bill paid late, an account that ran low), or renegotiate terms.

## VL-PERIOD-CLOSED-001: Transaction dated in a period Voice Ledger has locked
Where it shows up: Cleanup Assessment. Detection: Categorization | Resolution: Manual (QBO).
Why it matters: Once a period is closed, its transaction set should stop changing — that stability is what makes a closed period's reports trustworthy going forward. A transaction dated inside a period you've already locked means either a late entry slipped in after close, or an existing transaction was backdated into a period that should be settled.

## VL-PERSONAL-001: Possible personal expense or owner draw
Where it shows up: Cleanup Assessment. Detection: Categorization | Resolution: Manual (QBO).
Why it matters: A personal expense or owner draw recorded as a business expense overstates deductible expenses and understates the owner's equity withdrawal — it needs to be reclassified to an equity/draw account, not left in ordinary expenses, both for accurate books and for tax purposes.

## VL-VEND-ANOMALY-001: Unusually large amount for this vendor
Where it shows up: Cleanup Assessment. Detection: Categorization | Resolution: Manual (QBO).
Why it matters: A transaction several times larger than the same vendor's typical amount this period is worth a second look — it could be a data-entry error (an extra digit, a decimal point in the wrong place), a duplicate that didn't match on exact amount, or a genuine one-time charge that's correctly entered but still worth confirming.

## VL-CLOSED-PERIOD-DRIFT-001: A locked period's Trial Balance no longer matches its snapshot
Where it shows up: Cleanup Assessment. Detection: Categorization | Resolution: Manual (QBO).
Why it matters: Once a period is locked, its Trial Balance should stop moving — that's the whole point of a close. If the same period's Trial Balance looks different than it did at lock time, something changed after the close: a backdated entry, an edit to an existing transaction, or a deletion. Whatever it is, the reports already delivered for this period may no longer be accurate.

## VL-VEND-PRICE-001: Vendor is charging more per transaction than last period
Where it shows up: Cleanup Assessment. Detection: Categorization | Resolution: Manual (QBO).
Why it matters: When a vendor bills the same number of times as last period but the average amount per charge is materially higher, that's a real price change worth confirming — either a legitimate rate increase (worth knowing about and budgeting for) or a billing error (worth catching before it repeats next month too).

## VL-CAT-MISCODE-001: Transaction coded differently than this vendor's usual account
Where it shows up: Cleanup Assessment. Detection: Categorization | Resolution: Manual (QBO).
Why it matters: A vendor that's always been coded to the same expense account probably belongs there again — a transaction from that vendor landing on a different account this period is more likely a miscoding slip than a real change in what's being purchased.

## VL-BS-DRCR-001: Income or Expense account on the wrong side of the Trial Balance
Where it shows up: Cleanup Assessment. Detection: Categorization | Resolution: Manual (QBO).
Why it matters: An Income account normally carries a credit balance and an Expense account normally carries a debit balance — that's what those account types mean. One showing up on the opposite side of the Trial Balance usually means a transaction was entered with the wrong sign, or coded as a negative amount instead of using a proper credit/refund transaction.

## VL-RELATIONSHIP-003: Purchase looks like a bank-to-bank transfer, not an expense
Where it shows up: Cleanup Assessment. Detection: Relationship | Resolution: Manual (QBO).
Why it matters: Moving money between two of the company's own bank accounts isn't income or an expense — it's a transfer, and QBO has a dedicated Transfer entity for it. A Purchase whose line is coded to another bank account is that same movement recorded the wrong way: it can inflate apparent spending activity and miscode what should be a simple balance-sheet-to-balance-sheet movement.

## VL-RELATIONSHIP-005: Loan payment coded to a single expense line
Where it shows up: Cleanup Assessment. Detection: Categorization | Resolution: Manual (QBO).
Why it matters: A loan or note payment bundles two different things into one bank draw: principal (which reduces the loan liability on the balance sheet, not an expense) and interest (a real expense). Coding the whole payment to a single expense line overstates that expense and leaves the loan balance on the books wrong — it never goes down even as real payments are made.

## VL-TRANSPOSITION-001: Possible transposition error
Where it shows up: Cleanup Assessment. Detection: Categorization | Resolution: Manual (QBO).
Why it matters: Swapping two adjacent digits in a dollar amount (e.g. entering $540 instead of $450) always changes the value by a multiple of 9 — a well-known property of positional number systems, not a coincidence. Two same-vendor, same-account postings within a few days of each other, whose amounts differ by a multiple of 9, are worth comparing against the source document for a possible data-entry error.

## How Voice Ledger rules work
Every finding comes from deterministic code, not AI. Each has a severity, confidence, dollar exposure, evidence, a pre-approval checklist and a risk-if-ignored statement. Severity is high when exposure is at or above the $25 materiality floor. Every rule except VL-CC-PAYMENT-001 is fixed manually in QuickBooks; that one can propose a staged write that still needs explicit approval and write access turned on.
