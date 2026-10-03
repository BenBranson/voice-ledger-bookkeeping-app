// One-off probe (2026-10-02): what this sandbox allows before designing the
// scenario seed — inventory tracking, sales tax, customer hierarchy. Read-only.
import "dotenv/config";
import { QboRawClient } from "./qboRawClient.js";

const c = new QboRawClient();
const prefs: any = (await c.get("preferences")).body;
const p = prefs.Preferences;
console.log("realm", c.realmId);
console.log("ProductAndServicesPrefs:", JSON.stringify(p?.ProductAndServicesPrefs));
console.log("TaxPrefs:", JSON.stringify(p?.TaxPrefs));
const ci: any = (await c.get(`companyinfo/${c.realmId}`)).body;
console.log("Company:", ci?.CompanyInfo?.CompanyName, ci?.CompanyInfo?.CompanyAddr?.CountrySubDivisionCode,
  "| offering:", JSON.stringify(ci?.CompanyInfo?.NameValue?.filter((n: any) => /Offer|Sku|Plan|Industry/i.test(n.Name))));
for (const q of [
  "select Id, Name, Type, QtyOnHand from Item where Type = 'Inventory' maxresults 10",
  "select Id, Name, Type from Item maxresults 40",
  "select Id, Name, Active from TaxCode maxresults 20",
  "select Id, Name, RateValue from TaxRate maxresults 20",
  "select Id, DisplayName, Job, ParentRef from Customer where Job = true maxresults 10",
  "select Id, Name, AccountType, AccountSubType from Account where AccountType in ('Other Current Asset','Cost of Goods Sold') maxresults 40",
  "select count(*) from CreditMemo",
  "select count(*) from RefundReceipt",
  "select count(*) from SalesReceipt"
]) {
  const r: any = (await c.query(q)).body;
  console.log("\n#", q, "\n", JSON.stringify(r?.QueryResponse ?? r).slice(0, 1500));
}
