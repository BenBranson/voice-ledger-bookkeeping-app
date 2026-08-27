import Foundation

/// docs/VOICE_LEDGER_SPEC.md Page 9 (Sales Tax Review). Shapes confirmed
/// live against the real sandbox 2026-08-27
/// (`backend/spike/checkTaxEntities.ts`) — see that spike's output for the
/// exact observed JSON these were modeled from.
public struct QBORawTaxCode: Decodable, Sendable {
    public let id: String
    public let name: String
    public let taxable: Bool?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case taxable = "Taxable"
    }
}

/// `AgencyRef` is absent on some tax codes' rates but always present on a
/// real `TaxRate` row (confirmed live: all 3 rows in this sandbox carried
/// one) — kept optional anyway rather than assumed, matching this
/// codebase's convention of never trusting an unconfirmed-required field.
public struct QBORawTaxRate: Decodable, Sendable {
    public let id: String
    public let name: String
    public let rateValue: Double?
    public let active: Bool?
    public let agencyID: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case rateValue = "RateValue"
        case active = "Active"
        case agencyRef = "AgencyRef"
    }
    enum AgencyRefKeys: String, CodingKey {
        case value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        rateValue = try container.decodeIfPresent(Double.self, forKey: .rateValue)
        active = try container.decodeIfPresent(Bool.self, forKey: .active)
        if let agencyContainer = try? container.nestedContainer(keyedBy: AgencyRefKeys.self, forKey: .agencyRef) {
            agencyID = try? agencyContainer.decode(String.self, forKey: .value)
        } else {
            agencyID = nil
        }
    }
}

public struct QBORawTaxAgency: Decodable, Sendable {
    public let id: String
    public let displayName: String

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case displayName = "DisplayName"
    }
}

public struct QBOTaxCodeQueryResponse: Decodable, Sendable {
    public let queryResponse: QueryResponseBody
    enum CodingKeys: String, CodingKey { case queryResponse = "QueryResponse" }
    public struct QueryResponseBody: Decodable, Sendable {
        public let taxCode: [QBORawTaxCode]?
        enum CodingKeys: String, CodingKey { case taxCode = "TaxCode" }
    }
}

public struct QBOTaxRateQueryResponse: Decodable, Sendable {
    public let queryResponse: QueryResponseBody
    enum CodingKeys: String, CodingKey { case queryResponse = "QueryResponse" }
    public struct QueryResponseBody: Decodable, Sendable {
        public let taxRate: [QBORawTaxRate]?
        enum CodingKeys: String, CodingKey { case taxRate = "TaxRate" }
    }
}

public struct QBOTaxAgencyQueryResponse: Decodable, Sendable {
    public let queryResponse: QueryResponseBody
    enum CodingKeys: String, CodingKey { case queryResponse = "QueryResponse" }
    public struct QueryResponseBody: Decodable, Sendable {
        public let taxAgency: [QBORawTaxAgency]?
        enum CodingKeys: String, CodingKey { case taxAgency = "TaxAgency" }
    }
}
