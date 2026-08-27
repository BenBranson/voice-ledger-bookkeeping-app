import Foundation

/// docs/VOICE_LEDGER_SPEC.md Page 9 (Sales Tax Review, Type A + C):
/// "reads tax codes, rates, agencies, taxable treatment, transaction-level
/// detail, liability balances." **This is the codes/rates/agencies slice
/// only** — transaction-level detail and liability balances are not built
/// here (liability balances would mean cross-referencing an agency's
/// `DisplayName` against Balance Sheet line labels, a fuzzy match this
/// codebase's own `VL-COA-DUPACCT-001` lesson argues against doing without
/// a live positive case to verify it against first). All three entity
/// reads live-verified 2026-08-27 against the real sandbox
/// (`backend/spike/checkTaxEntities.ts`).
public struct TaxCode: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let name: String
    /// `nil` when QBO didn't return the field at all — kept distinct from
    /// `false`, since "not taxable" and "unknown" are different claims.
    public let taxable: Bool?

    public init(id: String, name: String, taxable: Bool?) {
        self.id = id
        self.name = name
        self.taxable = taxable
    }
}

public struct TaxRate: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let name: String
    public let ratePercent: Double?
    public let isActive: Bool
    public let agencyID: String?

    public init(id: String, name: String, ratePercent: Double?, isActive: Bool, agencyID: String?) {
        self.id = id
        self.name = name
        self.ratePercent = ratePercent
        self.isActive = isActive
        self.agencyID = agencyID
    }
}

public struct TaxAgency: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

/// The Type C half of Page 9: "confirm filing jurisdiction, frequency,
/// whether return and payment were submitted, Tax Center adjustments, and
/// outstanding notices — none of which the public API confirms." A
/// human's attestation, recorded not treated as proof (`CLAUDE.md`: same
/// posture as every other attestation in this codebase), not a per-field
/// structured form — a free-text note plus one confirmation flag, matching
/// `EngagementScope`'s deliberately minimal shape rather than modeling
/// jurisdiction/frequency as separate typed fields with no real client
/// history yet to validate that structure against.
public struct SalesTaxAttestation: Codable, Sendable, Equatable {
    public var filingStatusConfirmed: Bool
    public var attestedBy: String?
    public var attestedAt: Date?
    public var note: String?

    public init(filingStatusConfirmed: Bool = false, attestedBy: String? = nil, attestedAt: Date? = nil, note: String? = nil) {
        self.filingStatusConfirmed = filingStatusConfirmed
        self.attestedBy = attestedBy
        self.attestedAt = attestedAt
        self.note = note
    }
}
