---
title: Branson's 12-step month-end close workflow (Voice Ledger)
collection: voice-ledger
source: VOICE_LEDGER_SPEC.md (Branson's own design spec, v9)
retrieved: 2026-09-27
ui_verified: false
---
# Branson's 12-step month-end close workflow

## How the close is organised
Voice Ledger runs on one monitor and QuickBooks Online on the other. Every step of the monthly close gets its own page, even steps the app can't do, so nothing is forgotten. Three kinds of step: API-driven (the app reads QBO and runs checks), import-driven (export a file such as a bank statement and drop it in), and guided manual (the app gives the QBO procedure and records that Branson did it). Earlier steps gate later ones: don't fix anything until access, scope and a baseline exist. A step never counts as done on missing data; "no statement imported" means coverage incomplete, not passed. A new client onboarding and a messy-books cleanup are the same flow with a wider date range; for a cleanup, assess first, reconcile oldest month first (a wrong beginning balance carries forward), then fix the biggest-dollar miscoding, then the rest.

## Step 1: Access and evidence pack
Confirm the company name and realm ID, read the company info, chart of accounts and baseline reports, and save them as the starting-state evidence pack (evidence, not a restorable backup). Branson confirms he has proper QuickBooks Online Accountant access to the client.

## Step 2: Scope and period lock
Record what the engagement covers and which period. Read the QBO closing date if one is set. Branson sets the official QBO closing date himself and confirms the client's filing status; neither can be set or checked through the API.

## Step 3: File health scan
Review accounts, posted transactions, balance sheet, P&L, trial balance and general ledger for problems: duplicates, uncategorized items, miscoding, negative balances. This is Voice Ledger's own health scan, not QuickBooks' Books Review.

## Step 4: Bank feed cleanup
Compare what is posted in QBO against the imported bank or card statement to find duplicates and missing postings. QBO's For Review queue, suggested matches and bank rules can't be read through the API. A statement line missing from QBO is fixed through the bank feed in QBO, never by creating a transaction from scratch, or it may be added twice when the feed brings it in.

## Step 5: Reconciliation
Compare statement lines against the ledger, find unmatched and duplicate items, and work out the difference. Branson finishes the reconciliation in QBO. Without statement evidence or Branson confirming he reconciled in QBO, this step is never marked done. Never force a reconciliation that doesn't balance; the difference goes to a Reconciliation Discrepancies account and hides the real problem.

## Step 6: Chart of accounts cleanup
Find duplicate or messy accounts and prepare a merge plan. Save the reconciliation reports first. Branson performs any merge in QBO: merges are permanent, can lose reconciliation history, need matching account and detail types, and cannot be undone.

## Step 7: Batch fixes
Recategorize transactions in small batches with a preview of what changes: how many transactions, total dollars, old and new category, effect on the reports, and how to reverse it. QuickBooks Online Accountant's own Reclassify Transactions tool is an alternative for big jobs. Closed periods reject changes.

## Step 8: Balance sheet integrity
The strongest checks: negative asset or liability balances, suspense activity, stale clearing accounts, undeposited funds sitting too long, loan balances that never go down, equity postings that need review, unexpected balance changes, and accounts on the wrong side (debit vs credit).

## Step 9: Sales tax review (skip if the client has none)
Review tax codes, rates, agencies and liability balances. Branson confirms the filing jurisdiction, frequency, return period, whether the return and payment were filed, any Tax Center adjustments and outstanding notices.

## Step 10: Taxes
A rough estimate of possible tax exposure from the books, always labeled an estimate. Voice Ledger contains no tax law; the set-aside rate is whatever Branson or the client's CPA provides. It is never filing advice.

## Step 11: Month-end close
Work the checklist and carry-forward items, run a final validation scan, then Branson sets the official QBO closing date and completes QuickBooks' Books Close. If anything upstream changes after a step was completed, the later steps need re-checking.

## Step 12: Reporting and close package
Produce the P&L, balance sheet, cash flow, general ledger, trial balance and aging reports, the branded client PDF, and the close package: reports, variances, warnings, completed checklist, corrections made, open carry-forward items, client questions and answers, and who closed the period and when.
