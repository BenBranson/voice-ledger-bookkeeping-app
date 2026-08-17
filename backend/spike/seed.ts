/**
 * Wave 0, item 0 (docs/phase-0/SPIKE_QUEUE.md): "Idempotent, versioned, with
 * hard teardown between suites." Built first, deliberately — §12.6's own
 * warning is that a manually-seeded sandbox drifts and becomes
 * unreproducible, at which point every test failure is ambiguous.
 *
 * Usage:
 *   npx tsx spike/seed.ts apply baseline
 *   npx tsx spike/seed.ts apply duplicates
 *   npx tsx spike/seed.ts teardown duplicates
 *   npx tsx spike/seed.ts teardown all
 *
 * Idempotency mechanism: a local manifest (spike/fixtures/seed-manifest.json)
 * saved after EVERY entity created, plus a DocNumber-based existing-check for
 * purchases as a secondary safety net if the manifest is ever deleted.
 * Accounts/vendors are matched by Name/DisplayName (both queryable). Every
 * purchase still carries a `note` (Purchase.PrivateNote) for human
 * readability in the QBO UI, but PrivateNote is NOT used for lookups — it
 * is not a queryable field in QBO's query language (confirmed 2026-08-16;
 * see the comment in ensurePurchase for how that was discovered).
 */

import "dotenv/config";
import { readFileSync, existsSync, mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { QboRawClient } from "./qboRawClient.js";

interface SeedAccount {
  name: string;
  accountType: string;
}

interface SeedVendor {
  displayName: string;
}

interface SeedPurchase {
  case: string;
  vendor: string;
  account: string;
  expenseAccount: string;
  amountMinorUnits: number;
  date: string;
  docNumber?: string;
  note: string;
  memo?: string;
  /** QBO requires PaymentType to match the AccountRef's account type — "Check" fails outright (fault 6430) against a Credit Card account. Defaults to "Check"; pass "CreditCard" when `account` is Credit Card-typed. */
  paymentType?: "Check" | "CreditCard" | "Cash";
}

interface SeedBill {
  case: string;
  vendor: string;
  expenseAccount: string;
  amountMinorUnits: number;
  date: string;
  note: string;
}

interface SeedVendorCredit {
  case: string;
  vendor: string;
  expenseAccount: string;
  amountMinorUnits: number;
  date: string;
  note: string;
}

interface SeedCustomerRef {
  /** The exact DisplayName of an EXISTING customer (e.g. one of QBO's own sample-company customers) — this looks the customer up, it never creates one. Voice Ledger has no customer-creation path; Invoice seeding is only meaningful against a sandbox that already has customers. */
  displayName: string;
}

interface SeedInvoice {
  case: string;
  customer: string;
  itemName: string;
  amountMinorUnits: number;
  date: string;
  docNumber?: string;
  note: string;
}

interface SeedPayment {
  case: string;
  customer: string;
  amountMinorUnits: number;
  date: string;
  note: string;
}

interface SeedFile {
  description: string;
  requiresBaseline?: boolean;
  accounts?: SeedAccount[];
  vendors?: SeedVendor[];
  customers?: SeedCustomerRef[];
  purchases?: SeedPurchase[];
  bills?: SeedBill[];
  invoices?: SeedInvoice[];
  payments?: SeedPayment[];
  vendorCredits?: SeedVendorCredit[];
}

const MANIFEST_PATH = join(process.cwd(), "spike", "fixtures", "seed-manifest.json");

interface Manifest {
  accounts: Record<string, string>; // name -> Id
  vendors: Record<string, string>; // displayName -> Id
  customers?: Record<string, string>; // displayName -> Id
  items?: Record<string, string>; // name -> Id
  purchases: Record<string, { id: string; syncToken: string }>; // note -> {id, syncToken}
  bills?: Record<string, { id: string; syncToken: string }>; // note -> {id, syncToken}
  invoices?: Record<string, { id: string; syncToken: string }>; // note -> {id, syncToken}
  payments?: Record<string, { id: string; syncToken: string }>; // note -> {id, syncToken}
  vendorCredits?: Record<string, { id: string; syncToken: string }>; // note -> {id, syncToken}
}

function loadManifest(): Manifest {
  if (existsSync(MANIFEST_PATH)) {
    const loaded = JSON.parse(readFileSync(MANIFEST_PATH, "utf8")) as Manifest;
    loaded.bills ??= {};
    loaded.customers ??= {};
    loaded.items ??= {};
    loaded.invoices ??= {};
    loaded.payments ??= {};
    loaded.vendorCredits ??= {};
    return loaded;
  }
  return { accounts: {}, vendors: {}, purchases: {}, bills: {}, customers: {}, items: {}, invoices: {}, payments: {}, vendorCredits: {} };
}

function saveManifest(manifest: Manifest): void {
  mkdirSync(join(process.cwd(), "spike", "fixtures"), { recursive: true });
  writeFileSync(MANIFEST_PATH, JSON.stringify(manifest, null, 2));
}

async function ensureAccount(client: QboRawClient, manifest: Manifest, spec: SeedAccount): Promise<string> {
  const cached = manifest.accounts[spec.name];
  if (cached) return cached;

  const existing = await client.query(`select Id from Account where Name = '${spec.name}'`);
  const found = (existing.body as any)?.QueryResponse?.Account?.[0];
  if (found) {
    manifest.accounts[spec.name] = found.Id;
    return found.Id;
  }

  const created = await client.post("account", { Name: spec.name, AccountType: spec.accountType });
  const id = (created.body as any).Account.Id;
  manifest.accounts[spec.name] = id;
  return id;
}

async function ensureVendor(client: QboRawClient, manifest: Manifest, spec: SeedVendor): Promise<string> {
  const cached = manifest.vendors[spec.displayName];
  if (cached) return cached;

  const existing = await client.query(`select Id from Vendor where DisplayName = '${spec.displayName}'`);
  const found = (existing.body as any)?.QueryResponse?.Vendor?.[0];
  if (found) {
    manifest.vendors[spec.displayName] = found.Id;
    return found.Id;
  }

  const created = await client.post("vendor", { DisplayName: spec.displayName });
  const id = (created.body as any).Vendor.Id;
  manifest.vendors[spec.displayName] = id;
  return id;
}

async function ensurePurchase(client: QboRawClient, manifest: Manifest, spec: SeedPurchase): Promise<void> {
  if (manifest.purchases[spec.note]) {
    process.stdout.write(`  [skip, already seeded] ${spec.case}\n`);
    return;
  }

  // Capability-spike finding (2026-08-16): this used to query by PrivateNote,
  // which QBO rejects outright — "property 'PrivateNote' is not queryable"
  // (fault 4001). The original code used `?.` optional chaining on the
  // result, which silently turned that query ERROR into "no existing match
  // found" and fell through to re-creating the purchase, colliding with
  // QBO's duplicate-DocNumber constraint on the ALREADY-created one. Two
  // compounding bugs: an unqueryable field, and an error path that looked
  // like an empty-result path. Fixed by querying DocNumber instead (verified
  // queryable) when the spec provides one; manifest tracking (now saved
  // incrementally — see apply()) is the primary idempotency mechanism for
  // specs without a DocNumber.
  if (spec.docNumber) {
    const existing = await client.query(`select Id, SyncToken from Purchase where DocNumber = '${spec.docNumber}'`);
    if (existing.status !== 200) {
      throw new Error(`Existing-purchase lookup failed for "${spec.case}": HTTP ${existing.status} ${JSON.stringify(existing.body)}`);
    }
    const found = (existing.body as any)?.QueryResponse?.Purchase?.[0];
    if (found) {
      manifest.purchases[spec.note] = { id: found.Id, syncToken: found.SyncToken };
      process.stdout.write(`  [found existing] ${spec.case}\n`);
      return;
    }
  }

  const accountId = manifest.accounts[spec.account];
  const vendorId = manifest.vendors[spec.vendor];
  const expenseAccountId = manifest.accounts[spec.expenseAccount];
  if (!accountId || !vendorId || !expenseAccountId) {
    throw new Error(
      `Missing dependency for purchase "${spec.case}" — run 'apply baseline' first (account=${spec.account}, vendor=${spec.vendor}, expenseAccount=${spec.expenseAccount}).`
    );
  }

  const created = await client.post("purchase", {
    AccountRef: { value: accountId },
    EntityRef: { value: vendorId, type: "Vendor" },
    TxnDate: spec.date,
    DocNumber: spec.docNumber,
    PrivateNote: spec.note,
    // Capability-spike finding (2026-08-16): Purchase requires PaymentType
    // and rejects creation without it — undocumented in our original design,
    // discovered by this seeding run failing with QBO fault code 2020
    // ("Required parameter PaymentType is missing"). "Check" matches
    // docs/phase-0/11_VERTICAL_SLICE.md §11.2's in-scope description
    // ("a Purchase with PaymentType == Check is in scope"); override to
    // "CreditCard" when spec.account is Credit Card-typed — QBO fault 6430
    // ("Invalid account type used") otherwise.
    PaymentType: spec.paymentType ?? "Check",
    Line: [
      {
        Amount: spec.amountMinorUnits / 100,
        DetailType: "AccountBasedExpenseLineDetail",
        Description: spec.memo,
        AccountBasedExpenseLineDetail: { AccountRef: { value: expenseAccountId } }
      }
    ]
  });
  if (created.status !== 200) {
    throw new Error(`Purchase create failed for "${spec.case}": HTTP ${created.status} ${JSON.stringify(created.body)}`);
  }
  const purchase = (created.body as any).Purchase;
  manifest.purchases[spec.note] = { id: purchase.Id, syncToken: purchase.SyncToken };
  process.stdout.write(`  [created] ${spec.case} -> Purchase ${purchase.Id}\n`);
}

// Added 2026-08-17 for VL-DUP-BILL-001. Same idempotency shape as
// ensurePurchase, minus the DocNumber-based existing-check (Bill specs
// here don't set one) — manifest tracking is the sole idempotency
// mechanism, same fallback ensurePurchase uses for note-only specs.
async function ensureBill(client: QboRawClient, manifest: Manifest, spec: SeedBill): Promise<void> {
  manifest.bills ??= {};
  if (manifest.bills[spec.note]) {
    process.stdout.write(`  [skip, already seeded] ${spec.case}\n`);
    return;
  }

  const vendorId = manifest.vendors[spec.vendor];
  const expenseAccountId = manifest.accounts[spec.expenseAccount];
  if (!vendorId || !expenseAccountId) {
    throw new Error(
      `Missing dependency for bill "${spec.case}" — run 'apply baseline' first (vendor=${spec.vendor}, expenseAccount=${spec.expenseAccount}).`
    );
  }

  const created = await client.post("bill", {
    VendorRef: { value: vendorId },
    TxnDate: spec.date,
    PrivateNote: spec.note,
    Line: [
      {
        Amount: spec.amountMinorUnits / 100,
        DetailType: "AccountBasedExpenseLineDetail",
        AccountBasedExpenseLineDetail: { AccountRef: { value: expenseAccountId } }
      }
    ]
  });
  if (created.status !== 200) {
    throw new Error(`Bill create failed for "${spec.case}": HTTP ${created.status} ${JSON.stringify(created.body)}`);
  }
  const bill = (created.body as any).Bill;
  manifest.bills[spec.note] = { id: bill.Id, syncToken: bill.SyncToken };
  process.stdout.write(`  [created] ${spec.case} -> Bill ${bill.Id}\n`);
}

async function ensureVendorCredit(client: QboRawClient, manifest: Manifest, spec: SeedVendorCredit): Promise<void> {
  manifest.vendorCredits ??= {};
  if (manifest.vendorCredits[spec.note]) {
    process.stdout.write(`  [skip, already seeded] ${spec.case}\n`);
    return;
  }

  const vendorId = manifest.vendors[spec.vendor];
  const expenseAccountId = manifest.accounts[spec.expenseAccount];
  if (!vendorId || !expenseAccountId) {
    throw new Error(
      `Missing dependency for vendor credit "${spec.case}" — run 'apply baseline' first (vendor=${spec.vendor}, expenseAccount=${spec.expenseAccount}).`
    );
  }

  const created = await client.post("vendorcredit", {
    VendorRef: { value: vendorId },
    TxnDate: spec.date,
    PrivateNote: spec.note,
    Line: [
      {
        Amount: spec.amountMinorUnits / 100,
        DetailType: "AccountBasedExpenseLineDetail",
        AccountBasedExpenseLineDetail: { AccountRef: { value: expenseAccountId } }
      }
    ]
  });
  if (created.status !== 200) {
    throw new Error(`VendorCredit create failed for "${spec.case}": HTTP ${created.status} ${JSON.stringify(created.body)}`);
  }
  const vendorCredit = (created.body as any).VendorCredit;
  manifest.vendorCredits[spec.note] = { id: vendorCredit.Id, syncToken: vendorCredit.SyncToken };
  process.stdout.write(`  [created] ${spec.case} -> VendorCredit ${vendorCredit.Id}\n`);
}

// Looks up an EXISTING customer by DisplayName — never creates one. Voice
// Ledger has no customer-creation path (`CLAUDE.md` scope), so Invoice
// seeding only works against a sandbox that already has customers (every
// QBO sample company does, e.g. "Amy's Bird Sanctuary").
// QBO's query language escapes a literal single quote by doubling it —
// found live 2026-08-17 when "Amy's Bird Sanctuary" broke this exact query
// unescaped. Only applied to the two functions added in this pass
// (ensureCustomer, ensureItem); the pre-existing ensureAccount/ensureVendor
// queries have the same latent bug but are out of scope for this fix.
function escapeQboStringLiteral(value: string): string {
  return value.replace(/'/g, "''");
}

async function ensureCustomer(client: QboRawClient, manifest: Manifest, spec: SeedCustomerRef): Promise<string> {
  manifest.customers ??= {};
  const cached = manifest.customers[spec.displayName];
  if (cached) return cached;

  const existing = await client.query(`select Id from Customer where DisplayName = '${escapeQboStringLiteral(spec.displayName)}'`);
  const found = (existing.body as any)?.QueryResponse?.Customer?.[0];
  if (!found) {
    throw new Error(`Customer "${spec.displayName}" not found in this sandbox — Voice Ledger cannot create one, only seed against an existing customer.`);
  }
  manifest.customers[spec.displayName] = found.Id;
  return found.Id;
}

// Looks up an EXISTING Item by Name — never creates one, same reasoning as
// ensureCustomer. Every QBO sample company ships default Service items
// (e.g. "Design").
async function ensureItem(client: QboRawClient, manifest: Manifest, name: string): Promise<string> {
  manifest.items ??= {};
  const cached = manifest.items[name];
  if (cached) return cached;

  const existing = await client.query(`select Id from Item where Name = '${escapeQboStringLiteral(name)}'`);
  const found = (existing.body as any)?.QueryResponse?.Item?.[0];
  if (!found) {
    throw new Error(`Item "${name}" not found in this sandbox — Voice Ledger cannot create one, only seed against an existing item.`);
  }
  manifest.items[name] = found.Id;
  return found.Id;
}

async function ensureInvoice(client: QboRawClient, manifest: Manifest, spec: SeedInvoice): Promise<void> {
  manifest.invoices ??= {};
  if (manifest.invoices[spec.note]) {
    process.stdout.write(`  [skip, already seeded] ${spec.case}\n`);
    return;
  }

  const customerId = await ensureCustomer(client, manifest, { displayName: spec.customer });
  const itemId = await ensureItem(client, manifest, spec.itemName);

  const created = await client.post("invoice", {
    CustomerRef: { value: customerId },
    TxnDate: spec.date,
    DocNumber: spec.docNumber,
    PrivateNote: spec.note,
    Line: [
      {
        Amount: spec.amountMinorUnits / 100,
        DetailType: "SalesItemLineDetail",
        SalesItemLineDetail: { ItemRef: { value: itemId } }
      }
    ]
  });
  if (created.status !== 200) {
    throw new Error(`Invoice create failed for "${spec.case}": HTTP ${created.status} ${JSON.stringify(created.body)}`);
  }
  const invoice = (created.body as any).Invoice;
  manifest.invoices[spec.note] = { id: invoice.Id, syncToken: invoice.SyncToken };
  process.stdout.write(`  [created] ${spec.case} -> Invoice ${invoice.Id}\n`);
}

// Payment's raw shape (verified live 2026-08-17 against a real sample-
// company Payment, Id 128) showed no PrivateNote field in any observed
// record, so — unlike ensurePurchase/ensureBill/ensureInvoice — this does
// NOT attempt a PrivateNote-based existing-check or set one on create.
// Manifest tracking is the ENTIRE idempotency mechanism here, same
// fallback ensureBill already documents for specs without a DocNumber.
async function ensurePayment(client: QboRawClient, manifest: Manifest, spec: SeedPayment): Promise<void> {
  manifest.payments ??= {};
  if (manifest.payments[spec.note]) {
    process.stdout.write(`  [skip, already seeded] ${spec.case}\n`);
    return;
  }

  const customerId = await ensureCustomer(client, manifest, { displayName: spec.customer });

  const created = await client.post("payment", {
    CustomerRef: { value: customerId },
    TotalAmt: spec.amountMinorUnits / 100,
    TxnDate: spec.date
  });
  if (created.status !== 200) {
    throw new Error(`Payment create failed for "${spec.case}": HTTP ${created.status} ${JSON.stringify(created.body)}`);
  }
  const payment = (created.body as any).Payment;
  manifest.payments[spec.note] = { id: payment.Id, syncToken: payment.SyncToken };
  process.stdout.write(`  [created] ${spec.case} -> Payment ${payment.Id}\n`);
}

async function apply(seedName: string): Promise<void> {
  const client = new QboRawClient();
  const manifest = loadManifest();
  const path = join(process.cwd(), "spike", "seeds", `${seedName}.json`);
  const seed = JSON.parse(readFileSync(path, "utf8")) as SeedFile;

  process.stdout.write(`Applying seed "${seedName}": ${seed.description}\n`);

  // Saved after EVERY entity, not once at the end. Capability-spike finding
  // (2026-08-16): a mid-run failure (e.g. the 4th of 5 purchases hits a
  // validation fault) used to lose track of the 3 that succeeded, because
  // the manifest was only written on a clean exit. Re-running `apply` after
  // such a failure then tried to re-create already-existing entities and
  // collided with QBO's own constraints (duplicate DocNumber) — the
  // idempotency mechanism this file's own doc comment promises didn't
  // survive a partial failure, which is exactly when it's needed most.
  for (const account of seed.accounts ?? []) {
    await ensureAccount(client, manifest, account);
    saveManifest(manifest);
  }
  for (const vendor of seed.vendors ?? []) {
    await ensureVendor(client, manifest, vendor);
    saveManifest(manifest);
  }
  for (const purchase of seed.purchases ?? []) {
    await ensurePurchase(client, manifest, purchase);
    saveManifest(manifest);
  }
  for (const bill of seed.bills ?? []) {
    await ensureBill(client, manifest, bill);
    saveManifest(manifest);
  }
  for (const invoice of seed.invoices ?? []) {
    await ensureInvoice(client, manifest, invoice);
    saveManifest(manifest);
  }
  for (const payment of seed.payments ?? []) {
    await ensurePayment(client, manifest, payment);
    saveManifest(manifest);
  }
  for (const vendorCredit of seed.vendorCredits ?? []) {
    await ensureVendorCredit(client, manifest, vendorCredit);
    saveManifest(manifest);
  }

  process.stdout.write(`Done. Manifest at ${MANIFEST_PATH}\n`);
}

/**
 * Hard teardown. Purchases support a real delete operation
 * (docs/phase-0/02_QBO_CAPABILITY_MATRIX.md, TXN profile) — this is sandbox
 * spike data, so a permanent hard delete is the correct choice here, unlike
 * anywhere in the production write path (docs/phase-0/10_STAGING_APPROVAL_AUDIT.md
 * explicitly never uses hard delete).
 */
async function teardown(seedName: string): Promise<void> {
  const client = new QboRawClient();
  const manifest = loadManifest();

  if (seedName === "all") {
    for (const [note, ref] of Object.entries(manifest.purchases)) {
      await client.post("purchase", { Id: ref.id, SyncToken: ref.syncToken }, { operation: "delete" });
      process.stdout.write(`  [deleted] ${note} -> Purchase ${ref.id}\n`);
    }
    manifest.purchases = {};
    // Accounts have no delete operation (docs/phase-0/02_QBO_CAPABILITY_MATRIX.md
    // §2.1's NAME profile) — deactivate instead, or leave them; sandbox
    // companies are cheap to recreate wholesale if they get too cluttered.
    saveManifest(manifest);
    process.stdout.write("Purchases torn down. Accounts/vendors left in place (no delete API — see comment).\n");
    return;
  }

  process.stdout.write(`Selective teardown by seed file isn't implemented — use 'teardown all', or recreate the sandbox company.\n`);
}

const [, , command, target] = process.argv;

if (command === "apply" && target) {
  apply(target).catch((error) => {
    process.stderr.write(`${error instanceof Error ? error.message : error}\n`);
    process.exit(1);
  });
} else if (command === "teardown" && target) {
  teardown(target).catch((error) => {
    process.stderr.write(`${error instanceof Error ? error.message : error}\n`);
    process.exit(1);
  });
} else {
  process.stdout.write(
    "Usage: npx tsx spike/seed.ts apply <baseline|duplicates|reconciliation|closed-period|edge-cases>\n" +
      "       npx tsx spike/seed.ts teardown all\n"
  );
  process.exit(64);
}
