import Foundation

/// docs/phase-0/04_DATA_MODEL.md. Not exhaustive — extended as later rules
/// need more entities. Only what VL-DUP-EXP-001 (docs/phase-0/11_VERTICAL_SLICE.md)
/// touches is here.
public enum QBOEntityKind: String, Hashable, Codable, Sendable {
    case purchase = "Purchase"
    case bill = "Bill"
    case billPayment = "BillPayment"
    case journalEntry = "JournalEntry"
    case account = "Account"
    case vendor = "Vendor"
    /// Added for `VL-DUP-INV-001` — the sales-side counterpart to `bill`.
    /// `LedgerTransaction.vendorName` is reused for the customer name on an
    /// Invoice (see that field's doc comment) rather than adding a parallel
    /// `customerName` field, since no rule needs to distinguish the two yet.
    case invoice = "Invoice"
    /// Added for `VL-DUP-PAY-001`.
    case payment = "Payment"
}

/// docs/phase-0/04_DATA_MODEL.md §4.6's closed enum — confirmed against the
/// live sandbox by Wave 1's `testAccountsRead` (docs/phase-0/SPIKE_QUEUE.md
/// item 5): every observed `AccountType` mapped cleanly to this list.
public enum LedgerAccountType: String, Hashable, Codable, Sendable {
    case bank = "Bank"
    case accountsReceivable = "Accounts Receivable"
    case otherCurrentAsset = "Other Current Asset"
    case fixedAsset = "Fixed Asset"
    case otherAsset = "Other Asset"
    case accountsPayable = "Accounts Payable"
    case creditCard = "Credit Card"
    case otherCurrentLiability = "Other Current Liability"
    case longTermLiability = "Long Term Liability"
    case equity = "Equity"
    case income = "Income"
    case otherIncome = "Other Income"
    case expense = "Expense"
    case otherExpense = "Other Expense"
    case costOfGoodsSold = "Cost of Goods Sold"

    /// True for the two expense-flavored types — what
    /// `VL-CC-PAYMENT-001` checks a mis-coded line against.
    public var isExpenseLike: Bool {
        self == .expense || self == .otherExpense
    }

    /// True for every asset and liability type. What `VL-BS-NEGBAL-001`
    /// checks a negative `CurrentBalance` against — QBO's `CurrentBalance`
    /// sign convention shows liabilities as positive-when-owed, so a
    /// negative balance on an asset OR a liability is abnormal (an
    /// overdrawn asset, or an overpaid liability). Deliberately excludes
    /// Equity/Income/Expense: a negative balance is unremarkable on those
    /// (e.g. an owner's draw exceeding contributions) and including them
    /// would just produce noise.
    public var isAssetOrLiability: Bool {
        switch self {
        case .bank, .accountsReceivable, .otherCurrentAsset, .fixedAsset, .otherAsset,
             .accountsPayable, .creditCard, .otherCurrentLiability, .longTermLiability:
            return true
        default:
            return false
        }
    }
}

/// docs/phase-0/04_DATA_MODEL.md. Only what the Cleanup Assessment rules
/// need — not the full chart-of-accounts shape (§6's Chart of Accounts
/// Cleanup page, not built).
public struct LedgerAccount: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let name: String
    public let accountType: LedgerAccountType
    /// QBO's `AccountSubType` — a raw passthrough string, not a closed enum
    /// like `LedgerAccountType`. QBO has dozens of subtypes across all
    /// account types; modeling them all isn't needed yet. `VL-OBE-BALANCE-001`
    /// checks this against the one value it needs (`"OpeningBalanceEquity"`)
    /// directly — verified live as the reliable structural signal for the
    /// system-created Opening Balance Equity account, more robust than
    /// matching on the account's (renameable) `name`.
    public let accountSubType: String?
    public let currentBalance: Money

    public init(id: String, name: String, accountType: LedgerAccountType, accountSubType: String? = nil, currentBalance: Money = .zero) {
        self.id = id
        self.name = name
        self.accountType = accountType
        self.accountSubType = accountSubType
        self.currentBalance = currentBalance
    }
}

/// docs/phase-0/04_DATA_MODEL.md. Added for the Connection Page (step 1.3) —
/// the smallest amount of connection-level (not period-level) info the UI
/// needs to show a real company name instead of just a bare realmId.
public struct CompanyConnectionInfo: Sendable, Codable, Hashable {
    public let companyName: String
    public let realmID: RealmID

    public init(companyName: String, realmID: RealmID) {
        self.companyName = companyName
        self.realmID = realmID
    }
}

/// docs/phase-0/04_DATA_MODEL.md. Only what `VL-DUP-VEND-001` needs.
public struct LedgerVendor: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let displayName: String
    public let isActive: Bool

    public init(id: String, displayName: String, isActive: Bool = true) {
        self.id = id
        self.displayName = displayName
        self.isActive = isActive
    }
}

/// docs/phase-0/08_RULE_ENGINE.md §8.1, §9.7. Whether a rule's input is
/// known-complete or only partially known. `.pass` may only be recorded
/// when coverage is `.complete` — enforced by the engine, not by rules
/// individually (§8.1's defense against a rule author forgetting).
public enum Coverage: Hashable, Codable, Sendable {
    case complete
    case partial(reason: String)
}

/// docs/phase-0/09_INGESTION_PIPELINE.md §9.8. Where a normalized record's
/// data actually came from — carried through to the finding, never
/// summarized away (§9.8: "reachable, not merely labeled").
public enum Provenance: Hashable, Codable, Sendable {
    case qboAPI(readAt: Date)
    case importedFile(documentID: String, importedAt: Date, extractionMethod: ExtractionMethod, coverage: Coverage)
}

public enum ExtractionMethod: String, Hashable, Codable, Sendable {
    case deterministicParse
    case onDeviceVision
    case claudeVision
}

/// docs/phase-0/04_DATA_MODEL.md. The normalized shape both the QBO API path
/// and the import path resolve into (§9.8) — `/core` rules cannot tell the
/// difference, by design. Only the fields the rules actually built so far
/// need are modeled; this is deliberately not the full spec's transaction
/// shape.
public struct LedgerTransaction: Identifiable, Hashable, Codable, Sendable {
    public let id: String // QBO Id for API-sourced records; a derived stable ID for imports
    public let entityKind: QBOEntityKind
    /// The counterparty name — `EntityRef`'s name for `Purchase`/`Bill`
    /// (a vendor), `CustomerRef`'s name for `Invoice` (a customer). Named
    /// `vendorName` because the vendor-side entities came first; reused
    /// rather than adding a parallel `customerName` since no rule needs to
    /// tell the two apart, only compare same-kind-to-same-kind.
    public let vendorName: String?
    public let txnDate: AccountingDate
    public let totalAmount: Money
    public let paymentAccountID: String?
    public let docNumber: String?
    public let isVoided: Bool
    public let memo: String?
    /// The account(s) each Line was coded to (e.g. `AccountBasedExpenseLineDetail.AccountRef`)
    /// — distinct from `paymentAccountID`, which is the top-level account
    /// money moved FROM. Added for `VL-CC-PAYMENT-001`: detecting a
    /// credit-card payment miscoded to an expense account requires knowing
    /// what the LINE was coded to, not just what account paid for it.
    public let lineAccountIDs: [String]
    public let provenance: Provenance

    public init(
        id: String,
        entityKind: QBOEntityKind,
        vendorName: String?,
        txnDate: AccountingDate,
        totalAmount: Money,
        paymentAccountID: String?,
        docNumber: String?,
        isVoided: Bool,
        memo: String?,
        lineAccountIDs: [String] = [],
        provenance: Provenance
    ) {
        self.id = id
        self.entityKind = entityKind
        self.vendorName = vendorName
        self.txnDate = txnDate
        self.totalAmount = totalAmount
        self.paymentAccountID = paymentAccountID
        self.docNumber = docNumber
        self.isVoided = isVoided
        self.memo = memo
        self.lineAccountIDs = lineAccountIDs
        self.provenance = provenance
    }
}

/// docs/phase-0/08_RULE_ENGINE.md §8.2b, §11.2. Cached company-level facts a
/// rule may read without doing its own I/O ("context carries no I/O", §8.2).
/// `customTxnNumbersForPurchases` is VL-DUP-EXP-001's T2-conditional flag,
/// populated from `VendorAndPurchasesPrefs.UseCustomTxnNumbers`.
public struct CompanyFacts: Hashable, Codable, Sendable {
    public var customTxnNumbersForPurchases: Bool

    public init(customTxnNumbersForPurchases: Bool) {
        self.customTxnNumbersForPurchases = customTxnNumbersForPurchases
    }
}

/// docs/phase-0/04_DATA_MODEL.md §4.11. Built from the client store before a
/// rule runs; carries coverage so the engine can gate `.pass` on it (§8.1).
public struct NormalizedDataSet: Sendable {
    public let realmID: RealmID
    public let period: AccountingPeriod
    public let transactions: [LedgerTransaction]
    /// Added for the Cleanup Assessment rules (`VL-CC-PAYMENT-001`), which
    /// need to cross-reference a transaction's line accounts against the
    /// chart of accounts (e.g. "is this line coded to an Expense-type
    /// account?"). Defaults empty so existing callers (VL-DUP-EXP-001,
    /// which needs no account data) don't have to supply it.
    public let accounts: [LedgerAccount]
    /// Added for `VL-DUP-VEND-001`.
    public let vendors: [LedgerVendor]
    public let coverage: Coverage
    public let companyFacts: CompanyFacts

    public init(
        realmID: RealmID,
        period: AccountingPeriod,
        transactions: [LedgerTransaction],
        accounts: [LedgerAccount] = [],
        vendors: [LedgerVendor] = [],
        coverage: Coverage,
        companyFacts: CompanyFacts
    ) {
        self.realmID = realmID
        self.period = period
        self.transactions = transactions
        self.accounts = accounts
        self.vendors = vendors
        self.coverage = coverage
        self.companyFacts = companyFacts
    }
}
