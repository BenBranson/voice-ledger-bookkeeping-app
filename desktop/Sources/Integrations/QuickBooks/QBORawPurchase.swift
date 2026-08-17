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
    public let txnDate: String
    public let totalAmt: Decimal
    public let docNumber: String?
    public let privateNote: String?
    public let accountRef: QBORawRef?
    public let entityRef: QBORawRef?
    public let status: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case txnDate = "TxnDate"
        case totalAmt = "TotalAmt"
        case docNumber = "DocNumber"
        case privateNote = "PrivateNote"
        case accountRef = "AccountRef"
        case entityRef = "EntityRef"
        case status
    }

    /// The verified signal (see the type-level doc comment): a voided
    /// Purchase carries `"status": "Voided"`. The key is absent — not
    /// present-and-false — on every non-voided Purchase, so `status ==
    /// "Voided"` is the whole check; no fallback to `TotalAmt` is needed
    /// or wanted, since that path is the one already proven unsafe.
    public var isVoided: Bool {
        status == "Voided"
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
