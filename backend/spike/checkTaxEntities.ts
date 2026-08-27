/**
 * One-off capability check for docs/VOICE_LEDGER_SPEC.md Page 9 (Sales Tax
 * Review): is TaxCode/TaxRate/TaxAgency actually readable in this sandbox,
 * and what does the shape look like? Same spike-only convention as the
 * rest of spike/*.
 *
 * Usage: QBO_SPIKE_REALM_ID=<realmId> npx tsx spike/checkTaxEntities.ts
 */
import "dotenv/config";
import { QboRawClient } from "./qboRawClient.js";

const client = new QboRawClient();

for (const entity of ["TaxCode", "TaxRate", "TaxAgency"]) {
  try {
    const result = await client.query(`select * from ${entity} MAXRESULTS 10`);
    const body: any = result.body;
    const rows = body?.QueryResponse?.[entity] ?? [];
    console.log(`\n=== ${entity} === status=${result.status} rows=${rows.length}`);
    if (body?.Fault) {
      console.log(`  Fault: ${JSON.stringify(body.Fault)}`);
    }
    for (const row of rows.slice(0, 3)) {
      console.log(`  ${JSON.stringify(row)}`);
    }
  } catch (e) {
    console.log(`\n=== ${entity} === threw: ${e}`);
  }
}

// Also check CompanyInfo for whether sales tax is even enabled for this company.
const companyInfo = await client.get("companyinfo/9341456442848752");
const ci: any = companyInfo.body;
console.log(`\n=== CompanyInfo tax-relevant fields ===`);
console.log(JSON.stringify({
  Country: ci?.CompanyInfo?.Country,
  NameValue: ci?.CompanyInfo?.NameValue
}, null, 2));
