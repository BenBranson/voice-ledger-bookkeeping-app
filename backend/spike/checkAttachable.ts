/**
 * One-off capability check for VL-PREPAID-PERIOD-001: does this sandbox
 * have any real Attachable entities, and does a raw Attachable query even
 * work? Read-only. Not wired into the production catalog — see
 * qboRawClient.ts's own doc comment for why this file exists at all.
 */
import "dotenv/config";
import { QboRawClient } from "./qboRawClient.js";

async function main() {
  const client = new QboRawClient();
  console.log(`Querying Attachable for realm ${client.realmId}...`);

  const result = await client.query("SELECT * FROM Attachable MAXRESULTS 20");
  console.log(`status: ${result.status}`);
  console.log(JSON.stringify(result.body, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
