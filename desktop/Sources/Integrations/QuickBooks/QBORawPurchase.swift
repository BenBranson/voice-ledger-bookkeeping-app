import Foundation

/// The subset of QBO's raw `Purchase` JSON shape this slice reads. Verified
/// field presence against the live sandbox in Wave 1 (docs/phase-0/SPIKE_QUEUE.md
/// item 6, `testPurchasesRead`) for `Id`, `TxnDate`, `TotalAmt`, `DocNumber`,
/// `PrivateNote`, `AccountRef`, `EntityRef`.
///
/// **`isVoided` detection is NOT verified against a live sandbox — flagged,
/// not silently assumed.** `?operation=void` on `Purchase` is confirmed
/// unsupported (docs/phase-0/11_VERTICAL_SLICE.md §11.1), so the only way a
/// real Purchase becomes voided is a manual void in the QBO UI directly. This
/// session never performed that manual UI action and re-read the result, so
/// `QBORawPurchase.isVoidedHeuristic` below is a documented assumption about
/// QBO's general behavior (TotalAmt zeroed, memo marked), not a sandbox-proven
/// fact. `CLAUDE.md` rule 6 requires sandbox proof before this can be trusted
/// in a shipped feature — see the new spike item this finding adds to
/// `docs/phase-0/SPIKE_QUEUE.md`.
public struct QBORawPurchase: Decodable, Sendable {
    public let id: String
    public let txnDate: String
    public let totalAmt: Decimal
    public let docNumber: String?
    public let privateNote: String?
    public let accountRef: QBORawRef?
    public let entityRef: QBORawRef?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case txnDate = "TxnDate"
        case totalAmt = "TotalAmt"
        case docNumber = "DocNumber"
        case privateNote = "PrivateNote"
        case accountRef = "AccountRef"
        case entityRef = "EntityRef"
    }

    /// See the type-level doc comment. `TotalAmt == 0` is the proxy; it is
    /// deliberately NOT wired into normalization as ground truth-strength
    /// until a spike test confirms it (see `QBOSyncClient.normalizePurchases`'s
    /// call site for how this is surfaced instead of silently trusted).
    public var isVoidedHeuristic: Bool {
        totalAmt == 0
    }
}

public struct QBORawRef: Decodable, Sendable {
    public let value: String
    public let name: String?

    enum CodingKeys: String, CodingKey {
        case value, name
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
