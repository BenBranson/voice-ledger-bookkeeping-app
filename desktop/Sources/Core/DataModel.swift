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
/// difference, by design. Only the fields VL-DUP-EXP-001 needs are modeled;
/// this is deliberately not the full spec's transaction shape.
public struct LedgerTransaction: Identifiable, Hashable, Codable, Sendable {
    public let id: String // QBO Id for API-sourced records; a derived stable ID for imports
    public let entityKind: QBOEntityKind
    public let vendorName: String?
    public let txnDate: AccountingDate
    public let totalAmount: Money
    public let paymentAccountID: String?
    public let docNumber: String?
    public let isVoided: Bool
    public let memo: String?
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
    public let coverage: Coverage
    public let companyFacts: CompanyFacts

    public init(
        realmID: RealmID,
        period: AccountingPeriod,
        transactions: [LedgerTransaction],
        coverage: Coverage,
        companyFacts: CompanyFacts
    ) {
        self.realmID = realmID
        self.period = period
        self.transactions = transactions
        self.coverage = coverage
        self.companyFacts = companyFacts
    }
}
