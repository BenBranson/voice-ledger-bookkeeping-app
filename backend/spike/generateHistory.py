#!/usr/bin/env python3
"""Writes spike/seeds/operating-history.json: 15 months (Jul 2025 - Sep 2026)
of realistic, seasonal landscaping-business activity for the SANDBOX company
only (CLAUDE.md rule 7). Deterministic (fixed random seed), so re-generating
produces the same file and `seed.ts apply` stays idempotent.

Owner request 2026-09-29: enough history to build and test trends, flux,
YTD, aging, the posting calendar, the cash forecast, and a profitable month.
"""
import json, random, calendar
from datetime import date, timedelta

rng = random.Random(20260929)
TODAY = date(2026, 9, 26)          # last date seeded (sandbox "today" is Sep 29)
MONTHS = [(2025, m) for m in range(7, 13)] + [(2026, m) for m in range(1, 10)]
# Odessa, TX landscaping: busy spring/summer, slow winter.
SEASON = {1: .62, 2: .68, 3: .9, 4: 1.12, 5: 1.25, 6: 1.22, 7: 1.15, 8: 1.08, 9: 1.0, 10: .92, 11: .78, 12: .66}
BASE_REVENUE = 12500

CUSTOMERS = ["0969 Ocean View Road", "55 Twin Lane", "Barnett Design", "Bill's Windsurf Shop", "Diego Rodriguez",
             "Dukes Basketball Camp", "Dylan Sollfrank", "Freeman Sporting Goods", "Gevelber Photography", "Jeff's Jalopies",
             "Kate Whelan", "Kookies by Kathy", "Pye's Cakes", "Rago Travel Agency", "Red Rock Diner",
             "Rondonuwu Fruit and Vegi", "Shara Barnett", "Sushi by Katsuyuki", "Video Games by Dan", "Wedding Planning by Whitney"]
ITEMS = [("Gardening", 1.0), ("Trimming", .6), ("Maintenance & Repair", .9), ("Installation", 1.6), ("Design", 1.3),
         ("Sod", 1.2), ("Pest Control", .5), ("Soil", .4)]

def cents(dollars): return int(round(dollars * 100))
def d(y, m, day): return date(y, m, min(day, calendar.monthrange(y, m)[1]))
def iso(x): return x.isoformat()

OWNER_DRAW_SUBTYPE = "PartnerDistributions"   # QBO rejects a second default-subtype Equity account
seed = {"description": "15-month operating history (Jul 2025 - Sep 2026) for a seasonal landscaping business. SANDBOX ONLY.",
        "accounts": [{"name": n, "accountType": t} for n, t in [
            ("Checking", "Bank"), ("Mastercard", "Credit Card"), ("Cost of Labor", "Expense"), ("Fuel", "Expense"),
            ("Job Materials", "Expense"), ("Plants and Soil", "Expense"), ("Supplies", "Expense"), ("Equipment Rental", "Expense"),
            ("Rent or Lease", "Expense"), ("Insurance", "Expense"), ("Telephone", "Expense"), ("Gas and Electric", "Expense"),
            ("Dues & Subscriptions", "Expense"), ("Advertising", "Expense"), ("Automobile", "Expense"), ("Notes Payable", "Long Term Liability"),
            ("Interest Paid", "Other Expense"), ("Owner's Draw", "Equity")]],
        "vendors": [{"displayName": v} for v in [
            "Gusto Payroll", "Chin's Gas and Oil", "Norton Lumber and Building Materials", "Tania's Nursery", "Hicks Hardware",
            "Ellis Equipment Rental", "Hall Properties", "Brosnahan Insurance Agency", "Cal Telephone", "PG&E",
            "Intuit QuickBooks", "Lee Advertising", "Diego's Road Warrior Bodyshop", "First Basin Bank", "Owner Draw"]],
        "purchases": [], "bills": [], "invoices": [], "payments": [], "billPayments": [], "transfers": []}

def purchase(note, vendor, account, expense, amount, when, card=False, lines=None, memo=None):
    if when > TODAY: return 0
    spec = {"case": note, "vendor": vendor, "account": "Mastercard" if card else account, "expenseAccount": expense,
            "amountMinorUnits": amount, "date": iso(when), "note": f"VL history {note}",
            "paymentType": "CreditCard" if card else "Check"}
    if lines: spec["lines"] = lines
    if memo: spec["memo"] = memo
    seed["purchases"].append(spec)
    return amount

loan_balance = 25000.00
unpaid_on_purpose = {("2026-03", 2), ("2026-05", 4), ("2026-07", 6)}   # aged receivables
card_spend = {}

for y, m in MONTHS:
    key = f"{y}-{m:02d}"
    season = SEASON[m]
    # ---- Sales: invoices, and payments applied to them, deposited to Checking
    target = BASE_REVENUE * season * rng.uniform(.9, 1.1)
    n_inv = max(6, int(round(target / 1150)))
    per = target / n_inv
    for i in range(1, n_inv + 1):
        when = d(y, m, rng.randint(2, 27))
        if when > TODAY: continue
        picks = [rng.choice(ITEMS) for _ in range(rng.choice([1, 1, 2, 2, 3]))]
        invoice_total = per * rng.uniform(.75, 1.25)
        weight_sum = sum(w for _, w in picks)
        lines = [{"itemName": item, "amountMinorUnits": cents(invoice_total * w / weight_sum)} for item, w in picks]
        total = sum(l["amountMinorUnits"] for l in lines)
        note = f"VL history {key} invoice {i:02d}"
        customer = rng.choice(CUSTOMERS)
        seed["invoices"].append({"case": f"{key} invoice {i:02d}", "customer": customer, "itemName": lines[0]["itemName"],
                                 "amountMinorUnits": total, "lines": lines, "date": iso(when), "dueDate": iso(when + timedelta(days=30)),
                                 "docNumber": f"H{str(y)[2:]}{m:02d}-{i:02d}", "note": note})
        paid = when + timedelta(days=rng.randint(6, 38))
        if (key, i) in unpaid_on_purpose or paid > TODAY: continue
        seed["payments"].append({"case": f"{key} payment {i:02d}", "customer": customer, "amountMinorUnits": total,
                                 "date": iso(paid), "note": f"VL history {key} payment {i:02d}", "invoiceNote": note, "depositTo": "Checking"})
    # ---- Payroll twice a month (labor ~24% of sales)
    for n, day in ((1, 15), (2, 28)):
        purchase(f"{key} payroll {n}", "Gusto Payroll", "Checking", "Cost of Labor", cents(target * .12 * rng.uniform(.95, 1.05)), d(y, m, day), memo="Crew payroll (net pay + taxes)")
    # ---- Fixed monthly costs
    purchase(f"{key} rent", "Hall Properties", "Checking", "Rent or Lease", 120000, d(y, m, 1), memo="Yard and shop rent")
    purchase(f"{key} insurance", "Brosnahan Insurance Agency", "Checking", "Insurance", 38500, d(y, m, 3))
    purchase(f"{key} phone", "Cal Telephone", "Checking", "Telephone", cents(96.40 + rng.uniform(0, 6)), d(y, m, 8))
    purchase(f"{key} utilities", "PG&E", "Checking", "Gas and Electric", cents(140 + 120 * season * rng.uniform(.8, 1.1)), d(y, m, 12))
    # ---- Card spending (paid off the following month)
    spend = 0
    for n, day in enumerate(sorted(rng.sample(range(2, 27), 3)), 1):
        spend += purchase(f"{key} fuel {n}", "Chin's Gas and Oil", "Checking", "Fuel", cents(rng.uniform(170, 290) * (0.8 + .3 * season)), d(y, m, day), card=True)
    spend += purchase(f"{key} supplies", "Hicks Hardware", "Checking", "Supplies", cents(rng.uniform(85, 240)), d(y, m, rng.randint(4, 24)), card=True)
    spend += purchase(f"{key} software", "Intuit QuickBooks", "Checking", "Dues & Subscriptions", 9000, d(y, m, 6), card=True, memo="QuickBooks Online subscription")
    card_spend[key] = spend
    # ---- Materials and plants (vary with season)
    for n in (1, 2):
        purchase(f"{key} plants {n}", "Tania's Nursery", "Checking", "Plants and Soil", cents(rng.uniform(260, 620) * season), d(y, m, rng.randint(3, 25)))
    if season >= 1.0:
        purchase(f"{key} equipment", "Ellis Equipment Rental", "Checking", "Equipment Rental", cents(rng.uniform(210, 430)), d(y, m, rng.randint(5, 22)))
    if m in (3, 6, 9, 12):
        purchase(f"{key} advertising", "Lee Advertising", "Checking", "Advertising", 45000, d(y, m, 10), memo="Quarterly mailer and yard signs")
    if m in (10, 2):
        purchase(f"{key} truck repair", "Diego's Road Warrior Bodyshop", "Checking", "Automobile", cents(rng.uniform(380, 720)), d(y, m, 17))
    # ---- Materials on account (bill), paid next month
    bill_date = d(y, m, 5)
    if bill_date <= TODAY:
        amount = cents(rng.uniform(650, 1100) * season)
        bnote = f"VL history {key} lumber bill"
        seed["bills"].append({"case": f"{key} lumber bill", "vendor": "Norton Lumber and Building Materials", "expenseAccount": "Job Materials",
                              "amountMinorUnits": amount, "date": iso(bill_date), "dueDate": iso(bill_date + timedelta(days=30)), "note": bnote})
        pay_date = bill_date + timedelta(days=rng.randint(24, 32))
        if pay_date <= TODAY and key not in ("2026-04",):      # April 2026 bill left unpaid on purpose (aged payable)
            seed["billPayments"].append({"case": f"{key} lumber bill payment", "vendor": "Norton Lumber and Building Materials", "billNote": bnote,
                                         "bankAccount": "Checking", "amountMinorUnits": amount, "date": iso(pay_date), "note": f"VL history {key} lumber payment"})
    # ---- Loan: principal + interest
    interest = round(loan_balance * .075 / 12, 2)
    principal = round(650 - interest, 2)
    if purchase(f"{key} loan payment", "First Basin Bank", "Checking", "Notes Payable", 65000, d(y, m, 10),
                lines=[{"account": "Notes Payable", "amountMinorUnits": cents(principal), "memo": "Principal"},
                       {"account": "Interest Paid", "amountMinorUnits": cents(interest), "memo": "Interest"}]):
        loan_balance -= principal
    # ---- Owner draw
    purchase(f"{key} owner draw", "Owner Draw", "Checking", "Owner's Draw", cents(rng.choice([1200, 1500, 1500, 1800])), d(y, m, 25), memo="Owner's draw")

# Pay each month's card balance on the 20th of the next month.
keys = [f"{y}-{m:02d}" for y, m in MONTHS]
for prev, (y, m) in zip(keys, MONTHS[1:]):
    when = d(y, m, 20)
    if when <= TODAY and card_spend.get(prev):
        seed["transfers"].append({"case": f"{prev} card payoff", "from": "Checking", "to": "Mastercard", "amountMinorUnits": card_spend[prev],
                                  "date": iso(when), "note": f"VL history {prev} card payoff"})

for a in seed["accounts"]:
    if a["name"] == "Owner's Draw": a["accountSubType"] = OWNER_DRAW_SUBTYPE
path = "spike/seeds/operating-history.json"
json.dump(seed, open(path, "w"), indent=1)
counts = {k: len(v) for k, v in seed.items() if isinstance(v, list)}
print(path, counts)
rev = {}
for inv in seed["invoices"]: rev[inv["date"][:7]] = rev.get(inv["date"][:7], 0) + inv["amountMinorUnits"]
print({k: round(v / 100) for k, v in sorted(rev.items())})
