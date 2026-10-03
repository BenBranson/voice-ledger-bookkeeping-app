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
import { createHash } from "node:crypto";
import { join } from "node:path";
import { QboRawClient } from "./qboRawClient.js";

interface SeedAccount {
  name: string;
  accountType: string;
  /** Required for some types, e.g. a second Equity account (QBO fault 6000 "only one account of this detail type"). */
  accountSubType?: string;
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
  /** Optional split lines (e.g. loan principal + interest). When present, replaces the single expenseAccount/amount line. */
  lines?: { account: string; amountMinorUnits: number; memo?: string }[];
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
  dueDate?: string;
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
  /** Optional multi-line invoice; replaces itemName/amount when present. `qty` + `unitPriceMinorUnits` sell a quantity (inventory); `taxable` marks the line for sales tax. */
  lines?: { itemName: string; amountMinorUnits: number; description?: string; qty?: number; unitPriceMinorUnits?: number; taxable?: boolean }[];
  /** Net-N due date, e.g. "2025-08-14". */
  dueDate?: string;
  /** Sales tax code by Name (e.g. "Tucson"); QBO computes the tax on lines marked taxable. */
  taxCode?: string;
}

/** Added 2026-10-02: customers this seed CREATES (the older SeedCustomerRef only looks up). `parent` makes it a sub-customer (job). */
interface SeedNewCustomer {
  displayName: string;
  parent?: string;
  city?: string;
  state?: string;
}

/** Added 2026-10-02: an inventory product with a starting quantity. QBO posts the opening value on `startDate`. */
interface SeedInventoryItem {
  name: string;
  qty: number;
  unitCostMinorUnits: number;
  salesPriceMinorUnits: number;
  startDate: string;
  incomeAccount: string;
  cogsAccount: string;
  assetAccount: string;
}

/** Added 2026-10-02: a customer credit memo (left unapplied unless QBO applies it). */
interface SeedCreditMemo {
  case: string;
  customer: string;
  itemName: string;
  amountMinorUnits: number;
  date: string;
  note: string;
}

interface SeedPayment {
  case: string;
  customer: string;
  amountMinorUnits: number;
  date: string;
  note: string;
  /** Apply the payment to this seeded invoice (by its note). */
  invoiceNote?: string;
  /** Deposit straight to this account (by name) instead of Undeposited Funds. */
  depositTo?: string;
}

interface SeedBillPayment {
  case: string;
  vendor: string;
  billNote: string;
  bankAccount: string;
  amountMinorUnits: number;
  date: string;
  note: string;
}

interface SeedTransfer {
  case: string;
  from: string;
  to: string;
  amountMinorUnits: number;
  date: string;
  note: string;
}

interface SeedFile {
  description: string;
  newCustomers?: SeedNewCustomer[];
  inventoryItems?: SeedInventoryItem[];
  creditMemos?: SeedCreditMemo[];
  requiresBaseline?: boolean;
  accounts?: SeedAccount[];
  vendors?: SeedVendor[];
  customers?: SeedCustomerRef[];
  purchases?: SeedPurchase[];
  bills?: SeedBill[];
  invoices?: SeedInvoice[];
  payments?: SeedPayment[];
  vendorCredits?: SeedVendorCredit[];
  billPayments?: SeedBillPayment[];
  transfers?: SeedTransfer[];
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
  billPayments?: Record<string, { id: string; syncToken: string }>;
  transfers?: Record<string, { id: string; syncToken: string }>;
  creditMemos?: Record<string, { id: string; syncToken: string }>;
  /** Added 2026-10-02: what each seed file CREATED, in creation order, so `teardown <seed>` removes exactly that and nothing else. */
  owned?: Record<string, { entity: string; id: string; key: string }[]>;
}

/**
 * Added 2026-10-02 after a 504 mid-seed: a timeout doesn't say whether QBO saved
 * the record, so a blind retry can create a duplicate nobody planted. Every create
 * carries QBO's `requestid` (same request → saved once), derived from the seed and
 * the exact body, and temporary failures (5xx, and QBO's 403 "statusCode: 500"
 * auth hiccup) are retried with that same id.
 */
async function createOnce(client: QboRawClient, entity: string, body: unknown) {
  const requestid = createHash("sha1").update(`${currentSeed}|${entity}|${JSON.stringify(body)}`).digest("hex").slice(0, 36);
  let last: Awaited<ReturnType<QboRawClient["post"]>> | undefined;
  for (let attempt = 1; attempt <= 4; attempt++) {
    last = await client.post(entity, body, { requestid });
    const transient = last.status >= 500 || (last.status === 403 && JSON.stringify(last.body ?? "").includes("statusCode: 500"));
    if (!transient) return last;
    process.stdout.write(`  [retry ${attempt}] ${entity}: HTTP ${last.status}\n`);
    await new Promise((r) => setTimeout(r, 1500 * attempt));
  }
  return last!;
}

/** The seed file `apply` is currently running, for ownership tracking. */
let currentSeed = "";

function own(manifest: Manifest, entity: string, id: string, key: string): void {
  if (!currentSeed) return;
  manifest.owned ??= {};
  (manifest.owned[currentSeed] ??= []).push({ entity, id, key });
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

  // Names aren't unique across types: this sandbox has "Job Materials" and
  // "Plants and Soil" as BOTH Income and Expense accounts. Picking the first
  // match posted 2026-09-29's lumber bills to Income — match the type too.
  const existing = await client.query(`select Id, AccountType from Account where Name = '${escapeQboStringLiteral(spec.name)}'`);
  const matches = ((existing.body as any)?.QueryResponse?.Account ?? []) as any[];
  const found = matches.find((a) => a.AccountType === spec.accountType) ?? (matches.length === 1 ? matches[0] : undefined);
  if (found) {
    manifest.accounts[spec.name] = found.Id;
    return found.Id;
  }

  const created = await createOnce(client, "account", { Name: spec.name, AccountType: spec.accountType, AccountSubType: spec.accountSubType });
  if (created.status !== 200) throw new Error(`Account create failed for "${spec.name}": HTTP ${created.status} ${JSON.stringify(created.body)}`);
  const id = (created.body as any).Account.Id;
  manifest.accounts[spec.name] = id;
  own(manifest, "Account", id, spec.name);
  return id;
}

async function ensureVendor(client: QboRawClient, manifest: Manifest, spec: SeedVendor): Promise<string> {
  const cached = manifest.vendors[spec.displayName];
  if (cached) return cached;

  const existing = await client.query(`select Id from Vendor where DisplayName = '${escapeQboStringLiteral(spec.displayName)}'`);
  const found = (existing.body as any)?.QueryResponse?.Vendor?.[0];
  if (found) {
    manifest.vendors[spec.displayName] = found.Id;
    return found.Id;
  }

  const created = await createOnce(client, "vendor", { DisplayName: spec.displayName });
  if (created.status !== 200) throw new Error(`Vendor create failed for "${spec.displayName}": HTTP ${created.status} ${JSON.stringify(created.body)}`);
  const id = (created.body as any).Vendor.Id;
  manifest.vendors[spec.displayName] = id;
  own(manifest, "Vendor", id, spec.displayName);
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
  // An empty vendor seeds an expense with no payee (VL-MISSING-PAYEE-001), added 2026-10-02.
  const vendorId = spec.vendor === "" ? "(no payee)" : manifest.vendors[spec.vendor];
  const expenseAccountId = spec.lines ? "split" : manifest.accounts[spec.expenseAccount];
  if (!accountId || !vendorId || !expenseAccountId) {
    throw new Error(
      `Missing dependency for purchase "${spec.case}" — run 'apply baseline' first (account=${spec.account}, vendor=${spec.vendor}, expenseAccount=${spec.expenseAccount}).`
    );
  }

  const created = await createOnce(client, "purchase", {
    AccountRef: { value: accountId },
    EntityRef: spec.vendor === "" ? undefined : { value: vendorId, type: "Vendor" },
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
    Line: spec.lines
      ? spec.lines.map((line) => {
          const id = manifest.accounts[line.account];
          if (!id) throw new Error(`Missing account "${line.account}" for purchase "${spec.case}"`);
          return { Amount: line.amountMinorUnits / 100, DetailType: "AccountBasedExpenseLineDetail", Description: line.memo, AccountBasedExpenseLineDetail: { AccountRef: { value: id } } };
        })
      : [
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
  own(manifest, "Purchase", purchase.Id, spec.note);
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

  const created = await createOnce(client, "bill", {
    VendorRef: { value: vendorId },
    TxnDate: spec.date,
    DueDate: spec.dueDate,
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
  own(manifest, "Bill", bill.Id, spec.note);
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

  const created = await createOnce(client, "vendorcredit", {
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
  own(manifest, "VendorCredit", vendorCredit.Id, spec.note);
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
  // Corrected 2026-09-29, verified live: QBO's query parser rejects a
  // doubled quote (QueryParserError on 'Chin''s Gas and Oil') and accepts a
  // backslash escape ('Chin\'s Gas and Oil'). Backslashes are escaped first.
  return value.replace(/\\/g, "\\\\").replace(/'/g, "\\'");
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
  const specLines = spec.lines ?? [{ itemName: spec.itemName, amountMinorUnits: spec.amountMinorUnits }];
  const lines = [];
  for (const line of specLines) {
    const itemId = await ensureItem(client, manifest, line.itemName);
    const detail: any = { ItemRef: { value: itemId } };
    if (line.qty !== undefined && line.unitPriceMinorUnits !== undefined) { detail.Qty = line.qty; detail.UnitPrice = line.unitPriceMinorUnits / 100; }
    if (line.taxable) detail.TaxCodeRef = { value: "TAX" };
    lines.push({ Amount: line.amountMinorUnits / 100, Description: line.description, DetailType: "SalesItemLineDetail", SalesItemLineDetail: detail });
  }

  const body: any = { CustomerRef: { value: customerId }, TxnDate: spec.date, DueDate: spec.dueDate, DocNumber: spec.docNumber, PrivateNote: spec.note, Line: lines };
  if (spec.taxCode) {
    const tc = await client.query(`select Id from TaxCode where Name = '${escapeQboStringLiteral(spec.taxCode)}'`);
    const tcId = (tc.body as any)?.QueryResponse?.TaxCode?.[0]?.Id;
    if (!tcId) throw new Error(`Tax code "${spec.taxCode}" not found`);
    body.TxnTaxDetail = { TxnTaxCodeRef: { value: tcId } };
  }
  const created = await createOnce(client, "invoice", body);
  if (created.status !== 200) {
    throw new Error(`Invoice create failed for "${spec.case}": HTTP ${created.status} ${JSON.stringify(created.body)}`);
  }
  const invoice = (created.body as any).Invoice;
  manifest.invoices[spec.note] = { id: invoice.Id, syncToken: invoice.SyncToken };
  own(manifest, "Invoice", invoice.Id, spec.note);
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

  const body: any = {
    CustomerRef: { value: customerId },
    TotalAmt: spec.amountMinorUnits / 100,
    TxnDate: spec.date
  };
  if (spec.invoiceNote) {
    const invoice = manifest.invoices?.[spec.invoiceNote];
    if (!invoice) throw new Error(`Payment "${spec.case}" applies to unseeded invoice "${spec.invoiceNote}"`);
    body.Line = [{ Amount: spec.amountMinorUnits / 100, LinkedTxn: [{ TxnId: invoice.id, TxnType: "Invoice" }] }];
  }
  if (spec.depositTo) {
    const depositId = manifest.accounts[spec.depositTo];
    if (!depositId) throw new Error(`Payment "${spec.case}" deposit account "${spec.depositTo}" not seeded`);
    body.DepositToAccountRef = { value: depositId };
  }
  const created = await createOnce(client, "payment", body);
  if (created.status !== 200) {
    throw new Error(`Payment create failed for "${spec.case}": HTTP ${created.status} ${JSON.stringify(created.body)}`);
  }
  const payment = (created.body as any).Payment;
  manifest.payments[spec.note] = { id: payment.Id, syncToken: payment.SyncToken };
  own(manifest, "Payment", payment.Id, spec.note);
  process.stdout.write(`  [created] ${spec.case} -> Payment ${payment.Id}\n`);
}

// Added 2026-09-29 for the 15-month operating history: pays a seeded bill.
async function ensureBillPayment(client: QboRawClient, manifest: Manifest, spec: SeedBillPayment): Promise<void> {
  manifest.billPayments ??= {};
  if (manifest.billPayments[spec.note]) {
    process.stdout.write(`  [skip, already seeded] ${spec.case}\n`);
    return;
  }
  const vendorId = manifest.vendors[spec.vendor];
  const bankId = manifest.accounts[spec.bankAccount];
  const bill = manifest.bills?.[spec.billNote];
  if (!vendorId || !bankId || !bill) throw new Error(`Missing dependency for bill payment "${spec.case}"`);
  const created = await createOnce(client, "billpayment", {
    VendorRef: { value: vendorId },
    PayType: "Check",
    CheckPayment: { BankAccountRef: { value: bankId } },
    TotalAmt: spec.amountMinorUnits / 100,
    TxnDate: spec.date,
    PrivateNote: spec.note,
    Line: [{ Amount: spec.amountMinorUnits / 100, LinkedTxn: [{ TxnId: bill.id, TxnType: "Bill" }] }]
  });
  if (created.status !== 200) {
    throw new Error(`BillPayment create failed for "${spec.case}": HTTP ${created.status} ${JSON.stringify(created.body)}`);
  }
  const payment = (created.body as any).BillPayment;
  manifest.billPayments[spec.note] = { id: payment.Id, syncToken: payment.SyncToken };
  own(manifest, "BillPayment", payment.Id, spec.note);
  process.stdout.write(`  [created] ${spec.case} -> BillPayment ${payment.Id}\n`);
}

// Added 2026-09-29: moves money between balance-sheet accounts (e.g. paying the credit card).
async function ensureTransfer(client: QboRawClient, manifest: Manifest, spec: SeedTransfer): Promise<void> {
  manifest.transfers ??= {};
  if (manifest.transfers[spec.note]) {
    process.stdout.write(`  [skip, already seeded] ${spec.case}\n`);
    return;
  }
  const fromId = manifest.accounts[spec.from];
  const toId = manifest.accounts[spec.to];
  if (!fromId || !toId) throw new Error(`Missing account for transfer "${spec.case}"`);
  const created = await createOnce(client, "transfer", {
    FromAccountRef: { value: fromId },
    ToAccountRef: { value: toId },
    Amount: spec.amountMinorUnits / 100,
    TxnDate: spec.date,
    PrivateNote: spec.note
  });
  if (created.status !== 200) {
    throw new Error(`Transfer create failed for "${spec.case}": HTTP ${created.status} ${JSON.stringify(created.body)}`);
  }
  const transfer = (created.body as any).Transfer;
  manifest.transfers[spec.note] = { id: transfer.Id, syncToken: transfer.SyncToken };
  own(manifest, "Transfer", transfer.Id, spec.note);
  process.stdout.write(`  [created] ${spec.case} -> Transfer ${transfer.Id}\n`);
}

// Added 2026-10-02: creates a customer (or a job under `parent`) with a billing address.
async function ensureNewCustomer(client: QboRawClient, manifest: Manifest, spec: SeedNewCustomer): Promise<string> {
  manifest.customers ??= {};
  const cached = manifest.customers[spec.displayName];
  if (cached) return cached;
  const existing = await client.query(`select Id from Customer where DisplayName = '${escapeQboStringLiteral(spec.displayName)}'`);
  const found = (existing.body as any)?.QueryResponse?.Customer?.[0];
  if (found) { manifest.customers[spec.displayName] = found.Id; return found.Id; }
  const body: any = { DisplayName: spec.displayName, BillAddr: { City: spec.city, CountrySubDivisionCode: spec.state, Country: "USA" } };
  if (spec.parent) {
    const parentId = manifest.customers[spec.parent];
    if (!parentId) throw new Error(`Parent customer "${spec.parent}" must be listed before "${spec.displayName}"`);
    body.ParentRef = { value: parentId };
    body.Job = true;
    body.BillWithParent = true;
  }
  const created = await createOnce(client, "customer", body);
  if (created.status !== 200) throw new Error(`Customer create failed for "${spec.displayName}": HTTP ${created.status} ${JSON.stringify(created.body)}`);
  const id = (created.body as any).Customer.Id;
  manifest.customers[spec.displayName] = id;
  own(manifest, "Customer", id, spec.displayName);
  process.stdout.write(`  [created] customer ${spec.displayName} -> ${id}\n`);
  return id;
}

// Added 2026-10-02: an inventory product with its starting quantity on hand.
async function ensureInventoryItem(client: QboRawClient, manifest: Manifest, spec: SeedInventoryItem): Promise<string> {
  manifest.items ??= {};
  const cached = manifest.items[spec.name];
  if (cached) return cached;
  const existing = await client.query(`select Id from Item where Name = '${escapeQboStringLiteral(spec.name)}'`);
  const found = (existing.body as any)?.QueryResponse?.Item?.[0];
  if (found) { manifest.items[spec.name] = found.Id; return found.Id; }
  const income = await ensureAccount(client, manifest, { name: spec.incomeAccount, accountType: "Income" });
  const cogs = await ensureAccount(client, manifest, { name: spec.cogsAccount, accountType: "Cost of Goods Sold" });
  const asset = await ensureAccount(client, manifest, { name: spec.assetAccount, accountType: "Other Current Asset" });
  const created = await createOnce(client, "item", {
    Name: spec.name, Type: "Inventory", TrackQtyOnHand: true, QtyOnHand: spec.qty, InvStartDate: spec.startDate,
    UnitPrice: spec.salesPriceMinorUnits / 100, PurchaseCost: spec.unitCostMinorUnits / 100,
    IncomeAccountRef: { value: income }, ExpenseAccountRef: { value: cogs }, AssetAccountRef: { value: asset }
  });
  if (created.status !== 200) throw new Error(`Item create failed for "${spec.name}": HTTP ${created.status} ${JSON.stringify(created.body)}`);
  const id = (created.body as any).Item.Id;
  manifest.items[spec.name] = id;
  own(manifest, "Item", id, spec.name);
  process.stdout.write(`  [created] inventory item ${spec.name} (${spec.qty} on hand) -> ${id}\n`);
  return id;
}

async function ensureCreditMemo(client: QboRawClient, manifest: Manifest, spec: SeedCreditMemo): Promise<void> {
  manifest.creditMemos ??= {};
  if (manifest.creditMemos[spec.note]) { process.stdout.write(`  [skip, already seeded] ${spec.case}\n`); return; }
  const customerId = await ensureCustomer(client, manifest, { displayName: spec.customer });
  const itemId = await ensureItem(client, manifest, spec.itemName);
  const created = await createOnce(client, "creditmemo", {
    CustomerRef: { value: customerId }, TxnDate: spec.date, PrivateNote: spec.note,
    Line: [{ Amount: spec.amountMinorUnits / 100, DetailType: "SalesItemLineDetail", SalesItemLineDetail: { ItemRef: { value: itemId } } }]
  });
  if (created.status !== 200) throw new Error(`CreditMemo create failed for "${spec.case}": HTTP ${created.status} ${JSON.stringify(created.body)}`);
  const memo = (created.body as any).CreditMemo;
  manifest.creditMemos[spec.note] = { id: memo.Id, syncToken: memo.SyncToken };
  own(manifest, "CreditMemo", memo.Id, spec.note);
  process.stdout.write(`  [created] ${spec.case} -> CreditMemo ${memo.Id}\n`);
}

async function apply(seedName: string): Promise<void> {
  const client = new QboRawClient();
  const manifest = loadManifest();
  const path = join(process.cwd(), "spike", "seeds", `${seedName}.json`);
  const seed = JSON.parse(readFileSync(path, "utf8")) as SeedFile;

  process.stdout.write(`Applying seed "${seedName}": ${seed.description}\n`);
  currentSeed = seedName;

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
  for (const customer of seed.newCustomers ?? []) {
    await ensureNewCustomer(client, manifest, customer);
    saveManifest(manifest);
  }
  for (const item of seed.inventoryItems ?? []) {
    await ensureInventoryItem(client, manifest, item);
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
  for (const billPayment of seed.billPayments ?? []) {
    await ensureBillPayment(client, manifest, billPayment);
    saveManifest(manifest);
  }
  for (const transfer of seed.transfers ?? []) {
    await ensureTransfer(client, manifest, transfer);
    saveManifest(manifest);
  }
  for (const memo of seed.creditMemos ?? []) {
    await ensureCreditMemo(client, manifest, memo);
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

  // Added 2026-10-02: remove exactly what one seed file created, newest first (a payment
  // before the invoice it pays). Transactions are deleted; names (customers, vendors,
  // items, accounts) have no delete in QBO, so they are made inactive. Only seeds applied
  // after ownership tracking existed can be torn down this way.
  const owned = manifest.owned?.[seedName];
  if (!owned || owned.length === 0) {
    process.stdout.write(`Nothing recorded for seed "${seedName}" (seeds applied before 2026-10-02 aren't tracked). Nothing removed.\n`);
    return;
  }
  const maps: Record<string, keyof Manifest> = {
    Purchase: "purchases", Bill: "bills", Invoice: "invoices", Payment: "payments", VendorCredit: "vendorCredits",
    BillPayment: "billPayments", Transfer: "transfers", CreditMemo: "creditMemos",
    Customer: "customers", Vendor: "vendors", Item: "items", Account: "accounts"
  };
  const names = new Set(["Customer", "Vendor", "Item", "Account"]);
  const left: typeof owned = [];
  for (const rec of [...owned].reverse()) {
    const path = rec.entity.toLowerCase();
    const current = await client.get(`${path}/${rec.id}`);
    const entity = (current.body as any)?.[rec.entity];
    if (!entity) { process.stdout.write(`  [gone] ${rec.entity} ${rec.id}\n`); continue; }
    const result = names.has(rec.entity)
      ? await client.post(path, { ...entity, Active: false })
      : await client.post(path, { Id: rec.id, SyncToken: entity.SyncToken }, { operation: "delete" });
    if (result.status !== 200) {
      process.stdout.write(`  [FAILED] ${rec.entity} ${rec.id}: HTTP ${result.status} ${JSON.stringify(result.body).slice(0, 200)}\n`);
      left.unshift(rec);
      continue;
    }
    process.stdout.write(`  [${names.has(rec.entity) ? "deactivated" : "deleted"}] ${rec.entity} ${rec.id} (${rec.key})\n`);
    const key = maps[rec.entity];
    const map = key ? (manifest[key] as Record<string, unknown> | undefined) : undefined;
    if (map) delete map[rec.key];
  }
  manifest.owned![seedName] = left;
  saveManifest(manifest);
  process.stdout.write(left.length ? `${left.length} record(s) could not be removed; see FAILED lines.\n` : `Seed "${seedName}" fully removed.\n`);
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
