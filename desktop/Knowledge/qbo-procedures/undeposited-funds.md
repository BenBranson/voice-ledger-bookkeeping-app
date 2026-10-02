---
title: Deposit payments through the Undeposited Funds account
collection: qbo-procedures
source: https://quickbooks.intuit.com/learn-support/en-us/help-article/payroll-setup/deposit-payments-undeposited-funds-account-online/L1td0m8Z2_US_en_US
retrieved: 2026-09-27
ui_verified: false
---
# Deposit payments through the Undeposited Funds account

## Purpose / when to use
Undeposited Funds is a temporary holding account for customer payments you intend to deposit later. Use it when several payments will go to the bank together as one deposit, so QBO shows a single deposit that matches the bank. Not needed when you deposit one payment at a time, or for payments processed through QuickBooks Payments, which QBO deposits for you.

## Steps in QBO
Find the account: All apps > Accounting > Chart of accounts; look for the account whose Detail type is Undeposited Funds (it may have been renamed).

Record a payment into it:
1. + Create > Receive payment (paying an invoice) or Sales receipt (no invoice).
2. Choose the customer; for invoice payments, tick the invoices being paid.
3. In Deposit to, pick the Undeposited Funds account.
4. Fill in payment method, reference/check number, amount (partial payments allowed).
5. Save.
Alternate path: Customer Hub > Customers > open the customer > Receive payment.

Then, when the money actually goes to the bank, record a Bank Deposit from the deposit slip; the waiting payments appear in the deposit window to select.

## Pitfalls
- Recording each payment straight to the bank when they were deposited together leaves several entries against one bank line, which makes matching and reconciliation harder.
- Forgetting to record the bank deposit leaves payments piling up in Undeposited Funds and the bank balance understated.

## How to verify
- Undeposited Funds rises by each payment, then falls by the deposit total.
- The bank register shows one deposit equal to the deposit slip.
- The invoice shows paid (A/R aging confirms).

## Bookkeeper note (not from source)
A balance that sits in Undeposited Funds for weeks usually means a deposit was never recorded, or was recorded separately and duplicated income. Voice Ledger flags this as VL-BS-UNDEP-001.
