import Foundation

/// The subset of QBO's raw `Purchase` JSON shape this slice reads. Verified
/// field presence against the live sandbox in Wave 1 (docs/phase-0/SPIKE_QUEUE.md
/// item 6, `testPurchasesRead`) for `Id`, `TxnDate`, `TotalAmt`, `DocNumber`,
/// `PrivateNote`, `AccountRef`, `EntityRef`.
///
/// **`isVoided` detection: RESOLVED 2026-08-17, spike item 51.** A `TotalAmt
/// == 0` heuristic was tried first and DISPROVEN (false-positived on the
/// legitimate, never-voided `VL-SPIKE-ZERO` $0 fixture, Purchase #146 —
/// `backend/spike/seeds/edge-cases.json`). The owner then manually voided
/// Purchase #151 (docs/phase-0/11_VERTICAL_SLICE.md §11.4's worked example)
/// in the live QBO sandbox UI, and a re-read confirmed the real signal: QBO
/// adds a **top-level `"status": "Voided"` field, present ONLY on voided
/// transactions** — absent entirely (not `false`, not `null` — the key
/// itself is missing) on every non-voided Purchase checked, including the
/// same #146 control fixture that broke the old heuristic. QBO also
/// prefixes `PrivateNote` with `"Voided - "` automatically, a secondary
/// corroborating signal not used here as primary. See
/// `backend/spike/tests/13-manual-void-purchase-shape.spike.ts` and its
/// fixture for the full before/after evidence. Branch B's `isVoided`
/// exclusion (§11.1) is now provably reachable end-to-end against real data,
/// not just proven in the rule engine's offline tests.
public struct QBORawPurchase: Decodable, Sendable {
    public let id: String
    public let syncToken: String?
    public let txnDate: String
    public let totalAmt: Decimal
    public let docNumber: String?
    public let privateNote: String?
    public let accountRef: QBORawRef?
    public let entityRef: QBORawRef?
    public let status: String?
    public let line: [QBORawPurchaseLine]?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case syncToken = "SyncToken"
        case txnDate = "TxnDate"
        case totalAmt = "TotalAmt"
        case docNumber = "DocNumber"
        case privateNote = "PrivateNote"
        case accountRef = "AccountRef"
        case entityRef = "EntityRef"
        case status
        case line = "Line"
    }

    /// The verified signal (see the type-level doc comment): a voided
    /// Purchase carries `"status": "Voided"`. The key is absent — not
    /// present-and-false — on every non-voided Purchase, so `status ==
    /// "Voided"` is the whole check; no fallback to `TotalAmt` is needed
    /// or wanted, since that path is the one already proven unsafe.
    public var isVoided: Bool {
        status == "Voided"
    }

    /// The account each `AccountBasedExpenseLineDetail` line was coded to —
    /// verified present against the live sandbox (§4.1's field-completeness
    /// check, Wave 1 item 6). Added for `VL-CC-PAYMENT-001`, which needs to
    /// know what a Purchase's LINE was coded to, not just its payment
    /// account. Lines with a different `DetailType` (no
    /// `AccountBasedExpenseLineDetail`) are silently skipped, not guessed at.
    public var lineAccountIDs: [String] {
        (line ?? []).compactMap { $0.accountBasedExpenseLineDetail?.accountRef?.value }
    }
}

public struct QBORawPurchaseLine: Decodable, Sendable {
    /// QBO's own `Line.Id` — added for `updatePurchaseLineAccount`, which
    /// needs stable line identity, not an array index, to target a
    /// specific line safely.
    public let id: String?
    public let accountBasedExpenseLineDetail: QBORawAccountBasedExpenseLineDetail?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case accountBasedExpenseLineDetail = "AccountBasedExpenseLineDetail"
    }
}

public struct QBORawAccountBasedExpenseLineDetail: Decodable, Sendable {
    public let accountRef: QBORawRef?

    enum CodingKeys: String, CodingKey {
        case accountRef = "AccountRef"
    }
}

public struct QBORawRef: Decodable, Sendable {
    public let value: String
    public let name: String?

    enum CodingKeys: String, CodingKey {
        case value, name
    }
}

/// docs/phase-0/04_DATA_MODEL.md §4.6 — verified against the live sandbox by
/// Wave 1's `testAccountsRead` (`docs/phase-0/SPIKE_QUEUE.md` item 5, 92
/// accounts read, every observed `AccountType` mapped cleanly to
/// `LedgerAccountType`'s closed enum).
public struct QBORawAccount: Decodable, Sendable {
    public let id: String
    public let name: String
    public let accountType: String
    public let accountSubType: String?
    public let currentBalance: Decimal?
    /// The full parent-to-leaf path (e.g. `"Job Expenses:Job Materials"`).
    /// **Live-verified 2026-08-27** against the real sandbox
    /// (`backend/spike/checkFullyQualifiedName.ts`): 90/90 accounts
    /// returned a real, non-empty value. `VL-COA-DUPACCT-001`'s
    /// investigation (`docs/phase-0/08_RULE_ENGINE.md` §8.8) found leaf
    /// `Name` alone produces systematic false positives — confirmed live in
    /// this same check: 8 real leaf-`Name` collisions exist in this
    /// sandbox, including `"Equipment Rental"` appearing as TWO different
    /// Expense accounts (`Job Expenses:Equipment Rental` vs. plain
    /// `Equipment Rental`) — same `AccountType`, different parent, exactly
    /// the same-type-different-parent case `ChartOfAccountsCleanupTests`
    /// covers with synthetic data. `FullyQualifiedName` correctly
    /// distinguishes every one of these 8 pairs. `ChartOfAccountsCleanup`
    /// still only compares accounts where this decoded to a real value —
    /// `nil` here now means a genuine decode failure, not an unverified
    /// field, and stays excluded from detection rather than falling back to
    /// leaf name.
    public let fullyQualifiedName: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case accountType = "AccountType"
        case accountSubType = "AccountSubType"
        case currentBalance = "CurrentBalance"
        case fullyQualifiedName = "FullyQualifiedName"
    }
}

/// Added 2026-08-17 for the Connection Page (step 1.3). Verified shape
/// against the live sandbox — `readCompanyInfo`'s response is a direct
/// `{ "CompanyInfo": {...} }` object, not a `QueryResponse` wrapper (it's a
/// GET-by-Id, not a query).
public struct QBORawCompanyInfoResponse: Decodable, Sendable {
    public let companyInfo: QBORawCompanyInfo

    enum CodingKeys: String, CodingKey {
        case companyInfo = "CompanyInfo"
    }
}

public struct QBORawCompanyInfo: Decodable, Sendable {
    public let id: String
    public let companyName: String

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case companyName = "CompanyName"
    }
}

/// docs/backlog's `VL-DUP-BILL-001`. Same shape as `QBORawPurchase` for the
/// fields this slice needs, except `VendorRef` (not `EntityRef`) and
/// `APAccountRef` (not `AccountRef`) — verified against a live sandbox Bill,
/// 2026-08-17.
public struct QBORawBill: Decodable, Sendable {
    public let id: String
    public let txnDate: String
    public let totalAmt: Decimal
    public let docNumber: String?
    public let privateNote: String?
    public let apAccountRef: QBORawRef?
    public let vendorRef: QBORawRef?
    public let status: String?
    public let line: [QBORawPurchaseLine]?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case txnDate = "TxnDate"
        case totalAmt = "TotalAmt"
        case docNumber = "DocNumber"
        case privateNote = "PrivateNote"
        case apAccountRef = "APAccountRef"
        case vendorRef = "VendorRef"
        case status
        case line = "Line"
    }

    public var isVoided: Bool {
        status == "Voided"
    }

    public var lineAccountIDs: [String] {
        (line ?? []).compactMap { $0.accountBasedExpenseLineDetail?.accountRef?.value }
    }
}

public struct QBOBillQueryResponse: Decodable, Sendable {
    public let queryResponse: QueryResponseBody

    enum CodingKeys: String, CodingKey {
        case queryResponse = "QueryResponse"
    }

    public struct QueryResponseBody: Decodable, Sendable {
        public let bill: [QBORawBill]?

        enum CodingKeys: String, CodingKey {
            case bill = "Bill"
        }
    }
}

/// docs/backlog's `VL-DUP-INV-001`. Same shape as `QBORawBill` for the
/// fields this slice needs, except `CustomerRef` (not `VendorRef`) and no
/// `APAccountRef`/`AccountRef` equivalent read (this rule only needs
/// customer/date/amount, not line-level account detail). `isVoided` reuses
/// the same `status == "Voided"` signal verified live for Purchase (spike
/// item 51) — NOT independently re-verified against a live voided Invoice,
/// since no Invoice has been voided in this sandbox to check against. Flagged
/// here rather than silently assumed: if a duplicate Invoice's exclusion via
/// voiding is ever reported not to resolve, check this assumption first.
public struct QBORawInvoice: Decodable, Sendable {
    public let id: String
    public let txnDate: String
    public let totalAmt: Decimal
    public let docNumber: String?
    public let privateNote: String?
    public let customerRef: QBORawRef?
    public let status: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case txnDate = "TxnDate"
        case totalAmt = "TotalAmt"
        case docNumber = "DocNumber"
        case privateNote = "PrivateNote"
        case customerRef = "CustomerRef"
        case status
    }

    public var isVoided: Bool {
        status == "Voided"
    }
}

public struct QBOInvoiceQueryResponse: Decodable, Sendable {
    public let queryResponse: QueryResponseBody

    enum CodingKeys: String, CodingKey {
        case queryResponse = "QueryResponse"
    }

    public struct QueryResponseBody: Decodable, Sendable {
        public let invoice: [QBORawInvoice]?

        enum CodingKeys: String, CodingKey {
            case invoice = "Invoice"
        }
    }
}

/// docs/backlog's `VL-DUP-PAY-001`. Verified live against a real
/// sample-company `Payment` (Id 128) before this struct was written:
/// `CustomerRef`, `TotalAmt`, `TxnDate`, `Id` all present as expected. No
/// `status` field was observed on any Payment checked (none of the sample
/// data has ever been voided), so `isVoided` decodes the same key as
/// Purchase/Bill for structural consistency but is UNVERIFIED for
/// Payment — always `false` in practice until a real voided Payment can be
/// checked. Flagged rather than silently assumed.
public struct QBORawPayment: Decodable, Sendable {
    public let id: String
    public let txnDate: String
    public let totalAmt: Decimal
    public let privateNote: String?
    public let customerRef: QBORawRef?
    /// Added for `VL-BS-UNDEP-001` — verified live present on every real
    /// Payment checked. Almost always Undeposited Funds by default, but
    /// QBO does let a Payment deposit straight to a real bank account, so
    /// this is read rather than assumed.
    public let depositToAccountRef: QBORawRef?
    public let status: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case txnDate = "TxnDate"
        case totalAmt = "TotalAmt"
        case privateNote = "PrivateNote"
        case customerRef = "CustomerRef"
        case depositToAccountRef = "DepositToAccountRef"
        case status
    }

    public var isVoided: Bool {
        status == "Voided"
    }
}

public struct QBOPaymentQueryResponse: Decodable, Sendable {
    public let queryResponse: QueryResponseBody

    enum CodingKeys: String, CodingKey {
        case queryResponse = "QueryResponse"
    }

    public struct QueryResponseBody: Decodable, Sendable {
        public let payment: [QBORawPayment]?

        enum CodingKeys: String, CodingKey {
            case payment = "Payment"
        }
    }
}

/// Added 2026-08-17 for `VL-BS-UNDEP-001`. Verified live: `Line[].LinkedTxn[]`
/// with `TxnType == "Payment"` is the real signal QBO uses to record which
/// Payments a Deposit swept up — a real sandbox Deposit (Id 121) was found
/// referencing 5 Payments this way, including one dated 4 days before the
/// deposit itself.
public struct QBORawDeposit: Decodable, Sendable {
    public let id: String
    public let line: [QBORawDepositLine]?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case line = "Line"
    }

    public var linkedPaymentIDs: [String] {
        (line ?? []).flatMap { line in
            (line.linkedTxn ?? []).filter { $0.txnType == "Payment" }.map(\.txnId)
        }
    }
}

public struct QBORawDepositLine: Decodable, Sendable {
    public let linkedTxn: [QBORawLinkedTxn]?

    enum CodingKeys: String, CodingKey {
        case linkedTxn = "LinkedTxn"
    }
}

public struct QBORawLinkedTxn: Decodable, Sendable {
    public let txnId: String
    public let txnType: String

    enum CodingKeys: String, CodingKey {
        case txnId = "TxnId"
        case txnType = "TxnType"
    }
}

public struct QBODepositQueryResponse: Decodable, Sendable {
    public let queryResponse: QueryResponseBody

    enum CodingKeys: String, CodingKey {
        case queryResponse = "QueryResponse"
    }

    public struct QueryResponseBody: Decodable, Sendable {
        public let deposit: [QBORawDeposit]?

        enum CodingKeys: String, CodingKey {
            case deposit = "Deposit"
        }
    }
}

/// docs/backlog's `VL-VENDCREDIT-UNAPPLIED-001` — the vendor-refunds/vendor-
/// credits cleanup workflow. Verified live against a real created
/// VendorCredit (Id 224): `Balance` is a real top-level field, separate
/// from `TotalAmt`, showing how much of the credit remains unapplied.
public struct QBORawVendorCredit: Decodable, Sendable {
    public let id: String
    public let txnDate: String
    public let totalAmt: Decimal
    public let balance: Decimal?
    public let vendorRef: QBORawRef?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case txnDate = "TxnDate"
        case totalAmt = "TotalAmt"
        case balance = "Balance"
        case vendorRef = "VendorRef"
    }
}

public struct QBOVendorCreditQueryResponse: Decodable, Sendable {
    public let queryResponse: QueryResponseBody

    enum CodingKeys: String, CodingKey {
        case queryResponse = "QueryResponse"
    }

    public struct QueryResponseBody: Decodable, Sendable {
        public let vendorCredit: [QBORawVendorCredit]?

        enum CodingKeys: String, CodingKey {
            case vendorCredit = "VendorCredit"
        }
    }
}

/// Added 2026-08-17 for `VL-DUP-VEND-001`.
public struct QBORawVendor: Decodable, Sendable {
    public let id: String
    public let displayName: String
    public let active: Bool?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case displayName = "DisplayName"
        case active = "Active"
    }
}

public struct QBOVendorQueryResponse: Decodable, Sendable {
    public let queryResponse: QueryResponseBody

    enum CodingKeys: String, CodingKey {
        case queryResponse = "QueryResponse"
    }

    public struct QueryResponseBody: Decodable, Sendable {
        public let vendor: [QBORawVendor]?

        enum CodingKeys: String, CodingKey {
            case vendor = "Vendor"
        }
    }
}

public struct QBOAccountQueryResponse: Decodable, Sendable {
    public let queryResponse: QueryResponseBody

    enum CodingKeys: String, CodingKey {
        case queryResponse = "QueryResponse"
    }

    public struct QueryResponseBody: Decodable, Sendable {
        public let account: [QBORawAccount]?

        enum CodingKeys: String, CodingKey {
            case account = "Account"
        }
    }
}

public struct QBOPurchaseQueryResponse: Decodable, Sendable {
    public let queryResponse: QueryResponseBody

    enum CodingKeys: String, CodingKey {
        case queryResponse = "QueryResponse"
    }

    public struct QueryResponseBody: Decodable, Sendable {
        public let purchase: [QBORawPurchase]?

        enum CodingKeys: String, CodingKey {
            case purchase = "Purchase"
        }
    }
}

/// The subset of QBO's raw `Preferences` JSON this slice reads — just
/// `VendorAndPurchasesPrefs.UseCustomTxnNumbers`, verified present against
/// the live sandbox 2026-08-16 (docs/phase-0/11_VERTICAL_SLICE.md §11.2).
public struct QBOPreferencesQueryResponse: Decodable, Sendable {
    public let queryResponse: QueryResponseBody

    enum CodingKeys: String, CodingKey {
        case queryResponse = "QueryResponse"
    }

    public struct QueryResponseBody: Decodable, Sendable {
        public let preferences: [QBORawPreferences]?

        enum CodingKeys: String, CodingKey {
            case preferences = "Preferences"
        }
    }
}

public struct QBORawPreferences: Decodable, Sendable {
    public let vendorAndPurchasesPrefs: VendorAndPurchasesPrefs?

    enum CodingKeys: String, CodingKey {
        case vendorAndPurchasesPrefs = "VendorAndPurchasesPrefs"
    }

    public struct VendorAndPurchasesPrefs: Decodable, Sendable {
        public let useCustomTxnNumbers: Bool?

        enum CodingKeys: String, CodingKey {
            case useCustomTxnNumbers = "UseCustomTxnNumbers"
        }
    }
}
