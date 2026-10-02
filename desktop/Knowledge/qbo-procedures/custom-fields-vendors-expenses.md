---
title: Use custom fields for vendors and expenses
collection: qbo-procedures
source: https://quickbooks.intuit.com/learn-support/en-us/help-article/customize-forms/use-custom-fields-vendors-expenses-quickbooks/L7PSoFvYL_US_en_US
retrieved: 2026-09-27
ui_verified: false
---
# Use custom fields for vendors and expenses

Linked from the custom-fields hub page. How to create a field is in custom-fields-create-edit.md.

## Purpose / when to use
Example setups (QBO Advanced) for tracking vendor and expense details:
- Show a PO number on bills.
- Carry a vendor ID onto that vendor's transactions automatically.
- Record the vendor's invoice date separately from the bill date (useful when invoices arrive after the books are closed).
- Classify expenses by type for reporting.

## Steps in QBO
PO number: create a field "PO number"; data type Number (or Text and number if POs contain letters); put it on bills, and optionally invoices and sales receipts.

Vendor ID:
1. Create a field "Vendor ID" and select every form it should appear on (purchase orders, expenses, bills, vendor credits, invoices, estimates, sales receipts).
2. All apps > Expenses & Bills > Vendors > choose vendor > Vendor Details > Edit.
3. Enter the ID in the Vendor ID field > Save.

Invoice date: create a field "Invoice Date" and put it on the Bill form and any other expense forms needed.

Expense type: create a field "Expense type", data type Dropdown list, with values such as Flight, Car, Meals, Conference fee; put it on expense forms and/or bills.

## Prerequisites and plan limits
QBO Advanced only.

## Pitfalls
None stated.

## How to verify
Select the vendor on a transaction and confirm the field fills in. In reports, add the custom field as a column, or group, sort or filter by it.
