import Foundation

/// The subset of QBO's raw `Purchase` JSON shape this slice reads. Verified
/// field presence against the live sandbox in Wave 1 (docs/phase-0/SPIKE_QUEUE.md
/// item 6, `testPurchasesRead`) for `Id`, `TxnDate`, `TotalAmt`, `DocNumber`,
/// `PrivateNote`, `AccountRef`, `EntityRef`.
///
/// **`isVoided` detection: the `TotalAmt == 0` heuristic was tried and
/// DISPROVEN against the live sandbox, 2026-08-17.** A live `sync-check` run
/// (`VoiceLedgerDevTool`) against the real sandbox surfaced Purchase `#146` —
/// the `VL-SPIKE-ZERO` edge-case fixture (`backend/spike/seeds/edge-cases.json`),
/// a **legitimate, never-voided** $0 Purchase created specifically to test
/// that normalization "must not crash or duplicate-match on $0." The
/// heuristic flagged it `isVoided: true` anyway — a real false positive on
/// real data, not a hypothetical one. `TotalAmt == 0` conflates "voided" with
/// "genuinely a zero-dollar transaction," which is not a safe distinction to
/// guess at. Per `CLAUDE.md` rule 6 ("no feature labeled Automatic without
/// sandbox proof" — the inverse also holds: a heuristic sandbox-DISPROVEN
/// stays disproven, it doesn't get to keep running because it compiles),
/// `isVoidedHeuristic` below is now hardcoded to `false` rather than left
/// shipping a heuristic known to misfire. This means Branch B's `isVoided`
/// exclusion (docs/phase-0/11_VERTICAL_SLICE.md §11.1) currently can never
/// fire against real synced data — the resolution path is real in the rule
/// engine (see `RuleEngineGatingTests`/`DuplicatePostedExpenseRuleTests`) but
/// not yet reachable end-to-end against QBO until a real signal is found.
/// `docs/phase-0/SPIKE_QUEUE.md` item 51 (`testManualVoidPurchaseAPIShape`)
/// still needs to run — void Purchase #151 manually in the QBO UI, resync,
/// and see what actually changes (a `PrivateNote` marker, if any, is the next
/// candidate signal; `TotalAmt` alone is now known not to be one).
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

    /// See the type-level doc comment: `TotalAmt == 0` was tried and
    /// DISPROVEN against the live sandbox (false-positived on a legitimate
    /// $0 fixture, Purchase #146). Hardcoded `false` until spike item 51
    /// finds a real signal — this is an honest "we don't know," not a
    /// silent regression to the old (wrong) heuristic under another name.
    public var isVoidedHeuristic: Bool {
        false
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
