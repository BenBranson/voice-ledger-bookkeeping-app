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
    /// Added for `VL-VENDCREDIT-UNAPPLIED-001`.
    case vendorCredit = "VendorCredit"
    /// Added for `VL-DUP-INV-001` — the sales-side counterpart to `bill`.
    /// `LedgerTransaction.vendorName` is reused for the customer name on an
    /// Invoice (see that field's doc comment) rather than adding a parallel
    /// `customerName` field, since no rule needs to distinguish the two yet.
    case invoice = "Invoice"
    /// Added for `VL-DUP-PAY-001`.
    case payment = "Payment"
    /// Added for Universal Ingestion Tier 1 (docs/phase-0/09_INGESTION_PIPELINE.md).
    /// Not a real QBO entity — a raw line from an imported bank/card
    /// statement, before it's compared against posted QBO activity. Kept in
    /// this enum anyway because `LedgerTransaction.entityKind` is typed
    /// against it and §4.1/§9.8's whole point is that a rule can't tell an
    /// API-sourced record from an imported one by shape — giving imports a
    /// separate parallel enum would defeat that.
    case importedBankStatementLine = "ImportedBankStatementLine"
    /// Added for `VL-FORCED-RECON-001` — not a QBO entity type at all, but
    /// `SourceDependency` needed some value to name "this rule's input is
    /// the P&L report, not a transaction list," and adding a case here
    /// (rather than a separate dependency type) keeps `SourceDependency`
    /// itself a single closed shape.
    case report = "Report"
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
    /// Live-verified present on 100% of accounts in the real sandbox
    /// (`QBORawAccount.fullyQualifiedName`'s doc comment, 2026-08-27) — a
    /// `nil` here means a genuine decode failure, not an unverified field.
    /// `ChartOfAccountsCleanup` treats `nil` as "exclude from duplicate
    /// detection," never as a reason to fall back to comparing leaf `name`
    /// alone.
    public let fullyQualifiedName: String?

    public init(id: String, name: String, accountType: LedgerAccountType, accountSubType: String? = nil, currentBalance: Money = .zero, fullyQualifiedName: String? = nil) {
        self.id = id
        self.name = name
        self.accountType = accountType
        self.accountSubType = accountSubType
        self.currentBalance = currentBalance
        self.fullyQualifiedName = fullyQualifiedName
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

/// docs/phase-0/04_DATA_MODEL.md. Added for `VL-BS-UNDEP-001`. Not a
/// `LedgerTransaction` — a `Deposit` isn't compared against other
/// transactions the way a Purchase/Bill/Invoice/Payment is; it exists only
/// to say which `Payment`s have already been swept out of Undeposited
/// Funds, via `linkedPaymentIDs` (`Deposit.Line[].LinkedTxn[].TxnId` where
/// `TxnType == "Payment"`, confirmed live as the authoritative signal —
/// a Payment-only check without this would false-positive on any payment
/// that was actually deposited days after its own `TxnDate`).
public struct LedgerDeposit: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let linkedPaymentIDs: [String]
    public let txnDate: AccountingDate?
    public let depositToAccountID: String?
    public let totalAmount: Money?

    public init(id: String, linkedPaymentIDs: [String], txnDate: AccountingDate? = nil, depositToAccountID: String? = nil, totalAmount: Money? = nil) {
        self.id = id
        self.linkedPaymentIDs = linkedPaymentIDs
        self.txnDate = txnDate
        self.depositToAccountID = depositToAccountID
        self.totalAmount = totalAmount
    }
}

/// docs/phase-0/04_DATA_MODEL.md. Added for `VL-VENDCREDIT-UNAPPLIED-001`
/// (the vendor-refunds/vendor-credits cleanup workflow). Not a
/// `LedgerTransaction` — this rule needs `balance` (how much of the credit
/// is still unapplied) alongside `totalAmount` (the original credit
/// amount), a distinction no other entity built so far needs. `balance`
/// is QBO's own `VendorCredit.Balance` field, verified live as the
/// authoritative "still unapplied" signal — not something derived from
/// cross-referencing BillPayment/JournalEntry activity.
public struct LedgerVendorCredit: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let vendorName: String?
    public let txnDate: AccountingDate
    public let totalAmount: Money
    public let balance: Money
    public let provenance: Provenance

    public init(id: String, vendorName: String?, txnDate: AccountingDate, totalAmount: Money, balance: Money, provenance: Provenance) {
        self.id = id
        self.vendorName = vendorName
        self.txnDate = txnDate
        self.totalAmount = totalAmount
        self.balance = balance
        self.provenance = provenance
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
/// One `AccountBasedExpenseLineDetail` line, identity-tracked. Added
/// alongside `LedgerTransaction.lines` for the same reason — see that
/// field's doc comment.
public struct LedgerTransactionLine: Hashable, Codable, Sendable {
    public let id: String
    public let accountID: String
    /// The line's Description text, if any. Optional so caches saved before
    /// 2026-10-02 still decode.
    public let description: String?

    public init(id: String, accountID: String, description: String? = nil) {
        self.id = id
        self.accountID = accountID
        self.description = description
    }
}

public extension LedgerTransaction {
    /// Every note a person wrote on the transaction: the form's Memo plus each
    /// line's Description. Keyword checks read this, never `memo` alone (owner
    /// test 2026-10-02: "personal expense" typed on the line was missed).
    var noteText: String {
        ([memo] + lines.map(\.description)).compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

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
    /// Added for `updatePurchaseLineAccount` (Voice Ledger's first write
    /// operation): the write op needs QBO's own `Line.Id` to target a
    /// specific line safely (an array index could silently hit the wrong
    /// line if QBO ever reorders them). Deliberately additive alongside
    /// `lineAccountIDs` rather than replacing it — three already-verified
    /// rules (`VL-CC-PAYMENT-001`, `VL-PAYROLL-LUMP-001`,
    /// `VL-CAT-UNCAT-001`) only need account IDs and were left untouched.
    /// Both are populated from the same `raw.line` read in
    /// `QBOSyncClient.normalize`, so they cannot drift from each other.
    public let lines: [LedgerTransactionLine]
    /// Also added for `updatePurchaseLineAccount` — the write op's stale-
    /// object check needs a `SyncToken` to compare against. `nil` for
    /// entity kinds/sources that don't carry one (e.g. an imported
    /// statement line); a write attempt against a `nil` token is simply
    /// refused by the caller before it reaches the network, never sent as
    /// an empty string.
    public let syncToken: String?
    public let provenance: Provenance
    /// Two-letter state of the customer on a sales transaction (ship-to
    /// address, else bill-to), for the economic-nexus screen. Nil when
    /// QBO has no address or for purchases. Added 2026-10-02.
    public let customerState: String?

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
        lines: [LedgerTransactionLine] = [],
        syncToken: String? = nil,
        provenance: Provenance,
        customerState: String? = nil
    ) {
        self.customerState = customerState
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
        self.lines = lines
        self.syncToken = syncToken
        self.provenance = provenance
    }

    // Gauntlet Loop, Gauntlet B round 8 (2026-08-24): the identical
    // backward-compatibility bug found and fixed in `Finding`/`EvidenceItem`
    // (see their `init(from:)` comments) — `lineAccountIDs`/`lines` are
    // non-optional with a default only on the `init(...)` parameter, which
    // synthesized `Decodable` does not honor for a missing key. Worse here
    // than for `Finding`: `ClientStore.loadImportedStatementLines()` is
    // called un-guarded inside `AppState.syncAndEvaluate()`'s main `do`
    // block, so a decode failure fails the ENTIRE sync silently (no error
    // ever rendered), not just the findings list. `syncToken` is `Optional`
    // and needs no fix — Swift's synthesis already defaults it to `nil`.
    private enum CodingKeys: String, CodingKey {
        case id, entityKind, vendorName, txnDate, totalAmount, paymentAccountID
        case docNumber, isVoided, memo, lineAccountIDs, lines, syncToken, provenance, customerState
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        entityKind = try container.decode(QBOEntityKind.self, forKey: .entityKind)
        vendorName = try container.decodeIfPresent(String.self, forKey: .vendorName)
        txnDate = try container.decode(AccountingDate.self, forKey: .txnDate)
        totalAmount = try container.decode(Money.self, forKey: .totalAmount)
        paymentAccountID = try container.decodeIfPresent(String.self, forKey: .paymentAccountID)
        docNumber = try container.decodeIfPresent(String.self, forKey: .docNumber)
        isVoided = try container.decode(Bool.self, forKey: .isVoided)
        memo = try container.decodeIfPresent(String.self, forKey: .memo)
        lineAccountIDs = try container.decodeIfPresent([String].self, forKey: .lineAccountIDs) ?? []
        lines = try container.decodeIfPresent([LedgerTransactionLine].self, forKey: .lines) ?? []
        syncToken = try container.decodeIfPresent(String.self, forKey: .syncToken)
        provenance = try container.decode(Provenance.self, forKey: .provenance)
        customerState = try container.decodeIfPresent(String.self, forKey: .customerState)
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
    /// Added for `VL-BS-UNDEP-001`.
    public let deposits: [LedgerDeposit]
    /// Added for `VL-VENDCREDIT-UNAPPLIED-001`.
    public let vendorCredits: [LedgerVendorCredit]
    /// Added for `VL-FORCED-RECON-001`. Live-verified 2026-08-18: a forced
    /// reconciliation's discrepancy adjustment does NOT show up on
    /// `Account.CurrentBalance` (confirmed 0 despite a real $4,264.76
    /// adjustment) and posts no queryable `JournalEntry` either — the ONLY
    /// place it's visible via the API is the P&L report, as an "Other
    /// Expenses" line literally named "Reconciliation Discrepancies".
    /// Empty means "not fetched this sync," not "genuinely empty P&L" —
    /// the rule treats empty as `.cannotEvaluate`, same posture as every
    /// other optional-coverage source in this dataset.
    public let profitAndLossLines: [ReportLine]
    /// Added for `VL-REPORT-TIE-001`. Same "empty means not fetched, not
    /// genuinely empty" posture as `profitAndLossLines` — a real company
    /// always has SOME balance sheet lines once synced.
    public let balanceSheetLines: [ReportLine]
    /// Added for `VL-REPORT-TIE-001` — the Balance Sheet's A/R line should
    /// tie out exactly to the sum of every unpaid invoice, which is what
    /// Aged Receivables actually enumerates.
    public let agedReceivablesLines: [AgingLine]
    /// Added for `VL-REPORT-TIE-001` — same tie-out, for A/P against Aged
    /// Payables.
    public let agedPayablesLines: [AgingLine]
    /// Added for `VL-CLOSED-PERIOD-DRIFT-001` — the Trial Balance report for
    /// this exact `period`, compared against the snapshot captured at lock
    /// time (`RuleContext.periodLockSnapshot`). Same "empty means not
    /// fetched" posture as the other report arrays above.
    public let trialBalanceLines: [TrialBalanceLine]
    /// Added for `VL-VEND-PRICE-001` — the prior period's Purchases only
    /// (see `QBOSyncClient.fetchPurchases`'s doc comment for why Purchases
    /// only, not Bills too), fetched independently from `transactions`
    /// (which is always the CURRENT `period`'s activity). Empty means "not
    /// fetched this sync," same posture as the other optional-coverage
    /// arrays above — a real prior period with genuinely zero purchases is
    /// a rare but real possible case the rule can't distinguish from
    /// "never fetched," so it treats empty as `.cannotEvaluate` either way.
    public let priorPeriodTransactions: [LedgerTransaction]
    /// Transactions from the months BEFORE `period` (the app's 24-month history,
    /// when loaded). Lets a rule judge "normal for this vendor" from real history
    /// instead of the same month (added 2026-10-02). Empty when history isn't loaded.
    public let historyTransactions: [LedgerTransaction]
    public let coverage: Coverage
    public let companyFacts: CompanyFacts

    public init(
        realmID: RealmID,
        period: AccountingPeriod,
        transactions: [LedgerTransaction],
        accounts: [LedgerAccount] = [],
        vendors: [LedgerVendor] = [],
        deposits: [LedgerDeposit] = [],
        vendorCredits: [LedgerVendorCredit] = [],
        profitAndLossLines: [ReportLine] = [],
        balanceSheetLines: [ReportLine] = [],
        agedReceivablesLines: [AgingLine] = [],
        agedPayablesLines: [AgingLine] = [],
        trialBalanceLines: [TrialBalanceLine] = [],
        priorPeriodTransactions: [LedgerTransaction] = [],
        historyTransactions: [LedgerTransaction] = [],
        coverage: Coverage,
        companyFacts: CompanyFacts
    ) {
        self.historyTransactions = historyTransactions
        self.realmID = realmID
        self.period = period
        self.transactions = transactions
        self.accounts = accounts
        self.vendors = vendors
        self.deposits = deposits
        self.vendorCredits = vendorCredits
        self.profitAndLossLines = profitAndLossLines
        self.balanceSheetLines = balanceSheetLines
        self.agedReceivablesLines = agedReceivablesLines
        self.agedPayablesLines = agedPayablesLines
        self.trialBalanceLines = trialBalanceLines
        self.priorPeriodTransactions = priorPeriodTransactions
        self.coverage = coverage
        self.companyFacts = companyFacts
    }
}


extension NormalizedDataSet {
    /// An account's balance at the END of the reviewed period, in QBO's
    /// `CurrentBalance` sign convention (assets positive when normal;
    /// liabilities and equity negative when normal).
    ///
    /// Found 2026-10-02 while testing with seeded September data: the
    /// balance-sheet rules read `currentBalance`, which is TODAY's balance, so
    /// a July review showed today's figures labeled July, and anything entered
    /// later changed July's findings (Opening Balance Equity was $8,337.50 on
    /// July 31; the July finding said $9,247.50). The period's own Balance
    /// Sheet report is the July 31 truth. Its amounts are shown credit-positive
    /// for liabilities and equity, so those flip sign (verified against the
    /// sandbox: A/P 3,913.76 on the report vs -3,523.60 CurrentBalance today).
    /// An account absent from a loaded balance sheet had no balance then.
    /// Falls back to `currentBalance` only when no balance sheet is loaded.
    public func periodEndBalance(of account: LedgerAccount) -> Money {
        guard !balanceSheetLines.isEmpty else { return account.currentBalance }
        guard let line = balanceSheetLines.first(where: { !$0.isSummary && $0.accountID == account.id }), let amount = line.amount else {
            return Money(minorUnits: 0, currency: account.currentBalance.currency)
        }
        let credit: Bool
        switch account.accountType {
        case .accountsPayable, .creditCard, .otherCurrentLiability, .longTermLiability, .equity: credit = true
        default: credit = false
        }
        return credit ? Money(minorUnits: -amount.minorUnits, currency: amount.currency) : amount
    }

    /// True when `periodEndBalance` is reading the period's balance sheet, not today's balance.
    public var balancesArePeriodEnd: Bool { !balanceSheetLines.isEmpty }
}

extension LedgerAccount {
    /// Liabilities, equity and income carry credit balances. QBO's
    /// `CurrentBalance` (stored as-is) is NEGATIVE for these when normal:
    /// Accounts Payable owed $3,523.60 reads -3523.60 (verified against the
    /// aging report, owner test 2026-10-02; `NegativeBalanceRule` relies on
    /// the same convention).
    public var isCreditNormal: Bool {
        switch accountType {
        case .accountsPayable, .creditCard, .otherCurrentLiability, .longTermLiability, .equity, .income, .otherIncome: return true
        default: return false
        }
    }

    /// The balance as the Balance Sheet shows it: positive when normal
    /// (cash on hand, money owed on a card), negative when on the wrong side.
    public var presentedBalance: Money { isCreditNormal ? Money(minorUnits: -currentBalance.minorUnits, currency: currentBalance.currency) : currentBalance }

    public var hasAbnormalBalance: Bool { presentedBalance.minorUnits < 0 }
}
