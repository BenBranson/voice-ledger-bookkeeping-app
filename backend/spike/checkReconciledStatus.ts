// Spike, second half of VL-FORCED-RECON-001's sandbox verification
// (2026-08-18): does the QBO API expose a "this transaction is reconciled"
// signal? The owner cleanly reconciled Savings through 01/25/2026 in the
// sandbox UI (the $200 "Money to savings" transfer, difference $0.00, no
// adjustment) specifically so this could be checked against a real
// reconciled transaction, not a guess.
import "dotenv/config";
import { QboRawClient } from "./qboRawClient.js";

const client = new QboRawClient();

const transfer = await client.query("SELECT * FROM Transfer WHERE TxnDate = '2026-01-25'");
console.log("Transfer query:", JSON.stringify(transfer.body, null, 2));

const deposit = await client.query("SELECT * FROM Deposit WHERE TxnDate = '2026-01-25'");
console.log("Deposit query:", JSON.stringify(deposit.body, null, 2));
