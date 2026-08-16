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
 * Idempotency mechanism: every entity this script creates gets a `note`
 * (Purchase.PrivateNote) or a name prefixed `VL-SPIKE-`. Before creating
 * anything, `apply` queries for an existing entity with that marker and
 * reuses it instead of creating a duplicate — so re-running `apply` on a
 * seed file that already ran is a no-op, not an accumulating mess.
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
}

interface SeedFile {
  description: string;
  requiresBaseline?: boolean;
  accounts?: SeedAccount[];
  vendors?: SeedVendor[];
  purchases?: SeedPurchase[];
}

const MANIFEST_PATH = join(process.cwd(), "spike", "fixtures", "seed-manifest.json");

interface Manifest {
  accounts: Record<string, string>; // name -> Id
  vendors: Record<string, string>; // displayName -> Id
  purchases: Record<string, { id: string; syncToken: string }>; // note -> {id, syncToken}
}

function loadManifest(): Manifest {
  if (existsSync(MANIFEST_PATH)) {
    return JSON.parse(readFileSync(MANIFEST_PATH, "utf8")) as Manifest;
  }
  return { accounts: {}, vendors: {}, purchases: {} };
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

  const existing = await client.query(`select Id, SyncToken from Purchase where PrivateNote = '${spec.note}'`);
  const found = (existing.body as any)?.QueryResponse?.Purchase?.[0];
  if (found) {
    manifest.purchases[spec.note] = { id: found.Id, syncToken: found.SyncToken };
    process.stdout.write(`  [found existing] ${spec.case}\n`);
    return;
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
    Line: [
      {
        Amount: spec.amountMinorUnits / 100,
        DetailType: "AccountBasedExpenseLineDetail",
        Description: spec.memo,
        AccountBasedExpenseLineDetail: { AccountRef: { value: expenseAccountId } }
      }
    ]
  });
  const purchase = (created.body as any).Purchase;
  manifest.purchases[spec.note] = { id: purchase.Id, syncToken: purchase.SyncToken };
  process.stdout.write(`  [created] ${spec.case} -> Purchase ${purchase.Id}\n`);
}

async function apply(seedName: string): Promise<void> {
  const client = new QboRawClient();
  const manifest = loadManifest();
  const path = join(process.cwd(), "spike", "seeds", `${seedName}.json`);
  const seed = JSON.parse(readFileSync(path, "utf8")) as SeedFile;

  process.stdout.write(`Applying seed "${seedName}": ${seed.description}\n`);

  for (const account of seed.accounts ?? []) {
    await ensureAccount(client, manifest, account);
  }
  for (const vendor of seed.vendors ?? []) {
    await ensureVendor(client, manifest, vendor);
  }
  for (const purchase of seed.purchases ?? []) {
    await ensurePurchase(client, manifest, purchase);
  }

  saveManifest(manifest);
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
