import Foundation

/// docs/VOICE_LEDGER_HANDOFF.md D3: "Staleness is derived, never marked...
/// A page is fresh iff the evidence watermark it was completed against
/// still equals the current watermark for its declared inputs... Watermark
/// components include rule versions and materiality policy — so bumping a
/// rule version or changing materiality automatically stales completed
/// pages." Built 2026-08-29 — previously "not yet built," per that same
/// section's own note.
///
/// **Scoped to rule versions + materiality policy only, not a full
/// data-sync watermark.** D3's design also implies a component for "the
/// data itself changed" (e.g. a new transaction posted since this item
/// was completed) — that would need a content hash of the synced
/// `NormalizedDataSet` itself, a bigger change touching the sync path.
/// This is the real, honest slice: if the RULES that produced the
/// evidence a completion was based on have since changed version, or the
/// materiality floor used to size that evidence has changed, the
/// completion can no longer be trusted at face value — exactly the two
/// components D3's own text names explicitly. Extending to a full
/// content-hash watermark is a natural, additive next step, not a
/// redesign of this type.
public struct EvidenceWatermark: Codable, Hashable, Sendable {
    /// A stable, sorted `ruleID:major.minor.patch` signature across every
    /// registered rule — not a cryptographic hash. Equality is all this
    /// type is ever used for, and a canonical joined string is exact and
    /// simpler than pulling in a hashing dependency for no real benefit.
    public let ruleVersionsSignature: String
    public let materialityFloorMinorUnits: Int64

    public init(ruleVersionsSignature: String, materialityFloorMinorUnits: Int64) {
        self.ruleVersionsSignature = ruleVersionsSignature
        self.materialityFloorMinorUnits = materialityFloorMinorUnits
    }

    /// The watermark for "right now" — computed fresh at completion time
    /// and again whenever staleness is checked, never cached, so a rule
    /// version bump or materiality change is picked up on the very next
    /// check with no migration step of its own.
    public static func current(ruleIdentities: [RuleIdentity], materiality: MaterialityPolicy) -> EvidenceWatermark {
        let signature = ruleIdentities
            .map { "\($0.id.rawValue):\($0.version.major).\($0.version.minor).\($0.version.patch)" }
            .sorted()
            .joined(separator: "|")
        return EvidenceWatermark(ruleVersionsSignature: signature, materialityFloorMinorUnits: materiality.absoluteFloor.minorUnits)
    }
}
