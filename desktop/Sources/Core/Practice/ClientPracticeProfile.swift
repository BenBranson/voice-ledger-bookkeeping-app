import Foundation

/// What the bookkeeper knows about a client that QuickBooks doesn't say:
/// where it is, what kind of entity it is, which filings apply, and which
/// industry template to compare against. Stored per realm (CLAUDE.md rule
/// 9). Owner directives 2026-10-02 (compliance calendar; clients nationwide).
public struct ClientPracticeProfile: Codable, Sendable, Equatable {
    public enum SalesTaxFrequency: String, Codable, Sendable, CaseIterable {
        case none, monthly, quarterly, semiannual, yearly
        public var label: String {
            switch self {
            case .none: return "No sales tax"
            case .monthly: return "Monthly"
            case .quarterly: return "Quarterly"
            case .semiannual: return "Twice a year"
            case .yearly: return "Yearly"
            }
        }
    }

    public enum EntityType: String, Codable, Sendable, CaseIterable {
        case soleProprietor, singleMemberLLC, multiMemberLLC, partnership, sCorporation, cCorporation
        public var label: String {
            switch self {
            case .soleProprietor: return "Sole proprietor (no LLC)"
            case .singleMemberLLC: return "Single-member LLC"
            case .multiMemberLLC: return "Multi-member LLC"
            case .partnership: return "Partnership"
            case .sCorporation: return "S corporation"
            case .cCorporation: return "C corporation"
            }
        }
        /// Registered with the state, so annual reports apply.
        public var isRegisteredEntity: Bool { self != .soleProprietor }
        public var isCorporation: Bool { self == .sCorporation || self == .cCorporation }
    }

    /// Two-letter state where the business is formed and operates.
    public var state: String
    public var entityType: EntityType
    /// Month (1–12) and year the entity was formed, for anniversary-based reports.
    public var formationMonth: Int?
    public var formationYear: Int?
    public var salesTaxFrequency: SalesTaxFrequency
    public var files1099s: Bool
    public var hasEmployees: Bool
    /// IFTA quarterly fuel tax (interstate trucking).
    public var filesIFTA: Bool
    /// IRS Form 2290 heavy vehicle use tax (55,000 lb or more).
    public var filesForm2290: Bool
    /// Day of the month the client's statements are due (agreement term).
    public var statementsDueDay: Int
    /// Business day of the following month the monthly package is due.
    public var reportBusinessDay: Int
    public var industry: IndustryTemplate.Kind
    /// The client's last physical inventory count, for the inventory review.
    public var inventoryCount: Money?
    public var inventoryCountDate: AccountingDate?
    /// False until the bookkeeper has reviewed this client's profile once.
    public var reviewed: Bool

    public init(state: String = "TX", entityType: EntityType = .singleMemberLLC, formationMonth: Int? = nil, formationYear: Int? = nil,
                salesTaxFrequency: SalesTaxFrequency = .none, files1099s: Bool = false, hasEmployees: Bool = false,
                filesIFTA: Bool = false, filesForm2290: Bool = false, statementsDueDay: Int = 10, reportBusinessDay: Int = 15,
                industry: IndustryTemplate.Kind = .general, inventoryCount: Money? = nil, inventoryCountDate: AccountingDate? = nil, reviewed: Bool = false) {
        self.state = state
        self.entityType = entityType
        self.formationMonth = formationMonth
        self.formationYear = formationYear
        self.salesTaxFrequency = salesTaxFrequency
        self.files1099s = files1099s
        self.hasEmployees = hasEmployees
        self.filesIFTA = filesIFTA
        self.filesForm2290 = filesForm2290
        self.statementsDueDay = statementsDueDay
        self.reportBusinessDay = reportBusinessDay
        self.industry = industry
        self.inventoryCount = inventoryCount
        self.inventoryCountDate = inventoryCountDate
        self.reviewed = reviewed
    }

    private enum CodingKeys: String, CodingKey {
        case state, entityType, formationMonth, formationYear, salesTaxFrequency, files1099s, hasEmployees, filesIFTA, filesForm2290
        case statementsDueDay, reportBusinessDay, industry, inventoryCount, inventoryCountDate, reviewed, texasEntity
    }

    /// Tolerant decoding: profiles saved by v1.59 (Texas-only, `texasEntity`)
    /// load with defaults for the newer fields instead of failing.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let legacyTexasEntity = try c.decodeIfPresent(Bool.self, forKey: .texasEntity)
        state = try c.decodeIfPresent(String.self, forKey: .state) ?? "TX"
        entityType = try c.decodeIfPresent(EntityType.self, forKey: .entityType) ?? (legacyTexasEntity == false ? .soleProprietor : .singleMemberLLC)
        formationMonth = try c.decodeIfPresent(Int.self, forKey: .formationMonth)
        formationYear = try c.decodeIfPresent(Int.self, forKey: .formationYear)
        salesTaxFrequency = (try? c.decodeIfPresent(SalesTaxFrequency.self, forKey: .salesTaxFrequency)) ?? SalesTaxFrequency.none
        files1099s = try c.decodeIfPresent(Bool.self, forKey: .files1099s) ?? false
        hasEmployees = try c.decodeIfPresent(Bool.self, forKey: .hasEmployees) ?? false
        filesIFTA = try c.decodeIfPresent(Bool.self, forKey: .filesIFTA) ?? false
        filesForm2290 = try c.decodeIfPresent(Bool.self, forKey: .filesForm2290) ?? false
        statementsDueDay = try c.decodeIfPresent(Int.self, forKey: .statementsDueDay) ?? 10
        reportBusinessDay = try c.decodeIfPresent(Int.self, forKey: .reportBusinessDay) ?? 15
        industry = (try? c.decodeIfPresent(IndustryTemplate.Kind.self, forKey: .industry)) ?? .general
        inventoryCount = try c.decodeIfPresent(Money.self, forKey: .inventoryCount)
        inventoryCountDate = try c.decodeIfPresent(AccountingDate.self, forKey: .inventoryCountDate)
        reviewed = try c.decodeIfPresent(Bool.self, forKey: .reviewed) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(state, forKey: .state)
        try c.encode(entityType, forKey: .entityType)
        try c.encodeIfPresent(formationMonth, forKey: .formationMonth)
        try c.encodeIfPresent(formationYear, forKey: .formationYear)
        try c.encode(salesTaxFrequency, forKey: .salesTaxFrequency)
        try c.encode(files1099s, forKey: .files1099s)
        try c.encode(hasEmployees, forKey: .hasEmployees)
        try c.encode(filesIFTA, forKey: .filesIFTA)
        try c.encode(filesForm2290, forKey: .filesForm2290)
        try c.encode(statementsDueDay, forKey: .statementsDueDay)
        try c.encode(reportBusinessDay, forKey: .reportBusinessDay)
        try c.encode(industry, forKey: .industry)
        try c.encodeIfPresent(inventoryCount, forKey: .inventoryCount)
        try c.encodeIfPresent(inventoryCountDate, forKey: .inventoryCountDate)
        try c.encode(reviewed, forKey: .reviewed)
    }
}
