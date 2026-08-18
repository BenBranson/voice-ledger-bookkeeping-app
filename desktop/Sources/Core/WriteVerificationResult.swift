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
public struct WriteVerificationResult: Sendable, Equatable {
    public let verified: Bool
    public let purchaseID: String
    public let lineID: String
    public let oldAccountID: String?
    public let newAccountID: String
    public let newSyncToken: String?
    public let unexpectedFieldChanges: [String]
    public let otherLinesUnchanged: Bool
    /// The backend's full before/after entity snapshots, preserved as
    /// compact JSON text. **Previously silently dropped**: the backend
    /// always sends these (docs/VOICE_LEDGER_HANDOFF.md's Activity Log
    /// requirement, "before/after entity snapshots"), but this type used
    /// to be a plain `Decodable` struct that only listed the summary
    /// fields — `before`/`after` decoded fine on the backend's side and
    /// then vanished, since nothing asked for them. `nil` only when the
    /// backend's own key is absent or `null` (the pre-write read failed to
    /// find the entity, or the post-write verification read did).
    public let beforeSnapshotJSON: String?
    public let afterSnapshotJSON: String?

    public init(
        verified: Bool, purchaseID: String, lineID: String, oldAccountID: String?,
        newAccountID: String, newSyncToken: String?, unexpectedFieldChanges: [String],
        otherLinesUnchanged: Bool, beforeSnapshotJSON: String? = nil, afterSnapshotJSON: String? = nil
    ) {
        self.verified = verified
        self.purchaseID = purchaseID
        self.lineID = lineID
        self.oldAccountID = oldAccountID
        self.newAccountID = newAccountID
        self.newSyncToken = newSyncToken
        self.unexpectedFieldChanges = unexpectedFieldChanges
        self.otherLinesUnchanged = otherLinesUnchanged
        self.beforeSnapshotJSON = beforeSnapshotJSON
        self.afterSnapshotJSON = afterSnapshotJSON
    }

    private struct SummaryFields: Decodable {
        let verified: Bool
        let purchaseId: String
        let lineId: String
        let oldAccountId: String?
        let newAccountId: String
        let newSyncToken: String?
        let unexpectedFieldChanges: [String]
        let otherLinesUnchanged: Bool
    }

    /// Parses the summary fields via `JSONDecoder` (a fixed, known shape)
    /// AND separately re-serializes `before`/`after` from the same raw
    /// bytes via `JSONSerialization` — QBO's entity shape isn't a type
    /// this client owns or wants to model field-by-field just to preserve
    /// it for an audit log, so it's kept as text rather than partially
    /// modeled and partially dropped.
    public static func parse(from data: Data) throws -> WriteVerificationResult {
        let summary = try JSONDecoder().decode(SummaryFields.self, from: data)
        var raw: [String: Any] = [:]
        if let parsed = try? JSONSerialization.jsonObject(with: data), let dict = parsed as? [String: Any] {
            raw = dict
        }

        func snapshotJSON(_ key: String) -> String? {
            guard let value = raw[key], !(value is NSNull) else { return nil }
            guard let snapshotData = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { return nil }
            return String(data: snapshotData, encoding: .utf8)
        }

        return WriteVerificationResult(
            verified: summary.verified,
            purchaseID: summary.purchaseId,
            lineID: summary.lineId,
            oldAccountID: summary.oldAccountId,
            newAccountID: summary.newAccountId,
            newSyncToken: summary.newSyncToken,
            unexpectedFieldChanges: summary.unexpectedFieldChanges,
            otherLinesUnchanged: summary.otherLinesUnchanged,
            beforeSnapshotJSON: snapshotJSON("before"),
            afterSnapshotJSON: snapshotJSON("after")
        )
    }
}
