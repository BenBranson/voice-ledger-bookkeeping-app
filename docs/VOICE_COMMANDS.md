# Moneypenny — Voice Commands
Benjamin Branson Bookkeeping · Voice Ledger · kept in step with the app (a test fails if any phrase below stops working)

**How to talk to her:** press the microphone button (top left), then speak normally. Filler is fine — "hey Moneypenny", "please", "can you", "the" are ignored. Say numbers as digits or words: "$1,420", "fourteen twenty", "twelve hundred dollars". She hears "owe" as "own" sometimes; both work.
**Keyboard:** **Tab** = cut her off and listen again. **Tab** or "try again" after a wrong answer. The red mic button turns the microphone off. **`** (the key left of 1) closes a pop-up card.
**Every number she says comes straight from your books — the same figures as the pages.** She also tells you if the data is stale ("saved data from 2 hours ago — sync to refresh").

---

## 1. Go to any page
Say: **go to / open / pull up / take me to / show me + the page name.**
Example: *"go to profit and loss"* → opens the Profit & Loss page and says its name.

| Page you can name | Also works as |
|---|---|
| Dashboard | home |
| Charts & Cards | all charts, all cards, chart gallery |
| Findings | findings list |
| Firm Cockpit | cockpit |
| Cash Flow Forecast | forecast |
| Search by Amount | search |
| Pricing Calculator | pricing |
| Intake Questions | intake |
| Compliance Calendar | compliance, deadlines, due dates, tax calendar, sales by state, economic nexus |
| Scope Requests | out of scope, add ons |
| Industry Setup | industry |
| Client Diagnostics | diagnostics |
| Cleanup Assessment | cleanup |
| Balance Sheet Integrity | — |
| Chart of Accounts | chart of accounts cleanup |
| Bank Feed Cleanup | bank feed, bank |
| Batch Fixes | batch fix |
| Sales Tax Review | sales tax |
| Recurring Vendors | recurring |
| Month-End Close | month end, monthly close, close the books |
| Close Package | — |
| Activity Log | correction log |
| Balance Sheet | — |
| Profit & Loss | p and l, profit and loss |
| Cash Flow | cash flow report |
| Trial Balance | — |
| Aged Receivables | receivables, accounts receivable |
| Aged Payables | payables, accounts payable |
| General Ledger | — |
| Taxes | tax |
| Client Memory | — |
| Voice History | AI conversations |
| Connection | — |
| Scope & Period Lock | scope and period lock |
| Audio Settings | — |

**"Go back"** → returns to the page you were just on (it remembers up to 50 steps). **"Go forward"** → undoes a go-back.

## 2. Findings (the problems the app found)
| Say | What happens |
|---|---|
| **"pull up the duplicates"** (also "show me duplicates", "open duplicate transactions") | Opens Cleanup Assessment and says how many duplicate **pairs** are open, the total dollars at risk, and the largest. |
| **"show me the uncategorized transactions"** (also "miscategorized") | Opens Cleanup Assessment; says the count and total. |
| **"pull up the negative balances"** (also "overdrawn accounts") | Opens Balance Sheet Integrity; says count and total. |
| **"show me the personal expenses"** (also "owner draws") | Opens Cleanup Assessment; says count and total. |
| **"show me the late fees"** · **"price increases"** | Same, for fee findings and vendor price-increase findings. |
| **"balance sheet issues"** · **"suspense"** | Opens Balance Sheet Integrity. |
| **"show me all open findings"** (also "what's open", "everything open") | Opens Findings; says the total open and dollars. |
| **"open the $1,420 one"** · **"pull up the fourteen twenty finding"** | Opens the one finding with that exact dollar amount. If several match, she lists them and asks which. |
| **"pull up the Cool Cars payment"** · **"open the duplicate invoice"** | Opens the finding that matches the name or words. |
| **"why is this flagged"** · **"what should I do"** · **"fix it"** | Explains the finding that's open on screen and what the app recommends. (The only answer that uses the AI model; its figures are checked against your data.) |

## 3. Look up an amount
| Say | What happens |
|---|---|
| **"find $1,420"** · **"find fourteen twenty"** · **"search for $500"** · **"any transaction for 3,293.02"** | Searches the current month **and** the 24-month history for that exact amount. If the amount is an **account balance**, she says which account and how many postings make it up. If no single transaction matches, she looks for 2–3 that add up to it. Opens **Search by Amount** with the matches on screen, each with an Open in QBO link. |
| **"find Hicks Hardware"** | Says the vendor's transaction count and total, and opens **Search by Amount** listing every one of their transactions, each with an Open in QBO link. |

## 4. Balances and what we owe
| Say | What happens |
|---|---|
| **"what's the balance of the sweeper checking account"** · **"how much is in savings"** · **"balance of Mastercard"** | Says the account's current QuickBooks balance (overdrawn = in parentheses). |
| **"what do we owe"** · **"how much do we owe"** · **"what bills are due"** | Says total payables, how much is over 60 days past due, less credits; opens Aged Payables. |
| **"what do we owe Norton Lumber"** | Says what we owe that vendor — current vs. past due vs. over 90 days. For a vendor paid as each charge happens (like Gusto Payroll), she says nothing is owed and how many charges were paid. |
| **"who owes us"** · **"what are we owed"** · **"what do customers owe us"** | Says what customers owe, the credits, the net (matches the page TOTAL) and how much is over 60 days old; opens Aged Receivables. |
| **"who owes us the most"** · **"which customer owes us the most"** · **"who do we owe the most"** | Names the biggest customer (or vendor) balance, how much is over 60 days, and who is next; opens the aging page with a card. |
| **"what does Freeman Sporting Goods owe us"** · **"how much does Kate Whelan owe us"** | One customer's open balance: current, past due, over 90 days. Pops up their card. |
| **"is there anything unusual with Permian Supply"** · **"any issues with Cool Cars"** | Every open finding for that vendor or customer, largest first, with a card. |
| **"how much did we make this month"** · **"are we profitable"** | Net income for the month, with the 12-month chart. |
| **"how much have we paid Tania's Nursery"** · **"transactions from Hicks Hardware"** | Shows that vendor's count, total and last date. |

## 5. Quick numbers
| Say | What happens |
|---|---|
| **"what's our revenue this month"** · **"what was revenue last month"** | Says revenue (total income) for the loaded month, or the month before. |
| **"what's our net income"** · **"what's our profit"** | Says net income. |
| **"what's our cash balance"** · **"how much cash do we have"** | Says total bank balances. |
| **"what's due"** · **"next deadline"** · **"when is sales tax due"** | Reads the next three dates on this client's compliance calendar and opens it. |
| **"any new accounts"** | Says which bank, credit card or loan accounts appeared in QuickBooks since an earlier sync. |
| **"working capital"** · **"what's our working capital"** | Says working capital, the same figure as the Dashboard card. |
| **"current ratio"** · **"quick ratio"** | Says the ratio, the same figure as the Dashboard card. |
| **"gross margin"** · **"net margin"** · **"net margin last month"** | Says the margin as a percent, the same figure as the Dashboard card. |
| **"when did we last sync"** · **"is this current"** | Says how fresh the data is. |

## 6. Charts
| Say | What happens |
|---|---|
| **"charts"** | She asks which chart you want and waits for the name. |
| **"expenses"** (after she asks, or any time) or **"chart the expenses"** · **"expense chart"** · **"show me a pie chart of expenses"** | Pops up the top expense categories. |
| **"vendors chart"** · **"top vendors"** · **"vendor by spend"** · **"who do we pay the most"** | Spend by vendor for the month: expenses and bills only, never customers. |
| **"income vs expenses chart"** | Revenue to net income, step by step. |
| **"cost drivers chart"** · **"pareto"** | The biggest cost drivers. |
| **"revenue by month"** · **"revenue trend"** · **"chart revenue"** | A card with 12 months of revenue, centered on the month you're reviewing. |
| **"net income by month"** · **"profit trend"** | A card with 12 months of profit or loss, loss months flagged. |
| **"receivables chart"** · **"payables aging"** | Who owes us or what we owe, by customer or vendor and age, with QuickBooks links and what to do. |
| **"show net income trend"** · **"pull up revenue by month"** · **"show me the cash outlook"** | Saying show or pull up in front of a trend, by-month or outlook chart opens that chart instantly. |
| **"will we run out of cash"** · **"cash outlook"** | A card with the 13-week cash projection and the lowest week. |

## 7. Review mode (work through findings one at a time)
| Say | What happens |
|---|---|
| **"start review"** · **"show me anomalies"** · **"what needs my attention"** | Builds a queue of open findings and opens the first. |
| **"next"** · **"skip"** | Opens the next finding in the queue. |
| **"what's left"** · **"how many are left"** | Says progress. |
| **"check again"** · **"recheck"** · **"are we done"** | Re-syncs from QuickBooks and rebuilds the queue. |
| **"that one"** · **"open it"** | Reopens the last finding you looked at. |
| **"what were we doing"** | Reminds you what you were looking at. |
| **"open it in QuickBooks"** · **"show me in QuickBooks"** | Opens the finding you're on at its exact QuickBooks record, in your browser on the other monitor. |
| **"is it fixed"** · **"I fixed it"** · **"check it"** | Re-syncs from QuickBooks and tells you whether that finding cleared. If it did, she says how many are left and offers the next one; say **"yes"**. If not, she says what QuickBooks still shows and the suggested fix. |
| **"yes"** · **"no"** | Answers a question she just asked. If she misheard you, she instantly asks whether you meant the closest command; **"yes"** runs it. |

## 8. Guided month-end walkthrough (she walks you through the routine, one step at a time)
Say **"start month-end"** (also "start the monthly routine", "walk me through the month"). She goes through 16 steps in the order on the Monthly Routine sheet: for each one she opens the page, reads the numbers, and waits. Steps 3 and 5 are **yours to do in QuickBooks** (matching bank lines, reconciling); she tells you what to do, then re-syncs automatically when you say next. **Nothing in this mode changes your books.**

| Say (only while the walkthrough is running) | What happens |
|---|---|
| **"next"** · **"done"** · **"I did that"** · **"continue"** · **"skip"** | Moves to the next step (after a QuickBooks step it syncs first so the numbers are fresh). |
| **"repeat"** · **"say that again"** | Does the current step again. |
| **"previous step"** | Goes back one step. |
| **"where are we"** · **"how much is left"** | Says the step number and how many remain. |
| **"stop"** · **"end the routine"** · **"pause"** | Ends the walkthrough. |

## 9. Control
| Say | What happens |
|---|---|
| **"try again"** · **"that's wrong"** · **"never mind"** · **"scratch that"** | Clears her last answer and says Go ahead — then listens. |
| **"hi"** · **"status update"** · **"how are things"** | A short overview: open findings and dollars. |
| **Tab key** | Cuts her off mid-sentence and starts listening. |
| **` key** (left of 1) | Closes the open card, so you can click the next one right away. |

---
### Things she will **not** do by voice
She never changes your books by voice. Anything that would write to QuickBooks needs the on-screen confirmation. Voice only opens pages and reads figures.
### If she says "I didn't recognize that"
Say the page name ("go to …"), or a number ("find 1420"), or a question from the tables above. Open-ended questions the table doesn't cover go to the AI model, which may be slower (10–30 seconds).

### QuickBooks how-to questions
Ask in your own words, for example how to record a vendor credit, clear payments stuck in Undeposited Funds, merge duplicate vendors, or whether a contractor needs a 1099. She answers from a reference library of QuickBooks Online notes written from Intuit's ProAdvisor training and help pages. If the notes don't cover it, she says so rather than guessing a menu path. These go to the AI model, so they take 10–30 seconds.

### Cards
Most answers about money now pop up a card next to her spoken answer: a chart, the records behind it with Open in QBO links, and what to do. "Who owes us", "what do we owe", "find" a vendor, "balance of" an account, revenue, net income, cash, finding groups like duplicates, "what's due" and "any new accounts" all show one. Every card is also on the Charts & Cards page, one click each.

### Memory
She remembers the last 20 exchanges, including what she opened for you. When she offers something, such as pulling something up, just say yes.
