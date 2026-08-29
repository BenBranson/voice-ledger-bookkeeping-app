/**
 * One-off capability check for VL-AUTOADD-RULE-001: does QBO's public
 * Accounting API expose bank rules (auto-add rule configuration) as a
 * queryable entity at all? Read-only, throwaway.
 */
import "dotenv/config";
import { QboRawClient } from "./qboRawClient.js";

async function main() {
  const client = new QboRawClient();
  for (const entity of ["BankRule", "RecurTransaction"]) {
    try {
      const result = await client.query(`SELECT * FROM ${entity} MAXRESULTS 5`);
      console.log(entity, result.status, JSON.stringify(result.body).slice(0, 500));
    } catch (error) {
      console.log(entity, "ERROR", error);
    }
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
