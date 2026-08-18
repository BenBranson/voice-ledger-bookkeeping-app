import Foundation

/// docs/phase-0/10_STAGING_APPROVAL_AUDIT.md §10.3's round-trip fidelity
/// check, made real for Voice Ledger's first write-classified operation
/// (`updatePurchaseLineAccount`). The backend performs its own fresh
/// post-write read and comparison server-side — this type is the client's
/// view of that result, not a second independent check.
///
/// **`verified == false` is not the same as an HTTP error.** The write
/// itself succeeded (HTTP 200) but the backend's own round-trip read found
/// something unexpected — treat this the way
/// `docs/VOICE_LEDGER_HANDOFF.md`'s `UNKNOWN` write-state describes:
/// something is wrong, do not assume the write did what was intended, and
/// do not retry blindly (a retry against an already-applied write can
/// double it).
public struct WriteVerificationResult: Decodable, Sendable, Equatable {
    public let verified: Bool
    public let purchaseID: String
    public let lineID: String
    public let oldAccountID: String?
    public let newAccountID: String
    public let newSyncToken: String?
    public let unexpectedFieldChanges: [String]
    public let otherLinesUnchanged: Bool

    enum CodingKeys: String, CodingKey {
        case verified
        case purchaseID = "purchaseId"
        case lineID = "lineId"
        case oldAccountID = "oldAccountId"
        case newAccountID = "newAccountId"
        case newSyncToken
        case unexpectedFieldChanges
        case otherLinesUnchanged
    }
}
