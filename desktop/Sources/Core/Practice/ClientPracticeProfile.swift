import Foundation

/// What the bookkeeper knows about a client that QuickBooks doesn't say:
/// which filings apply and which industry template to compare against.
/// Stored per realm (CLAUDE.md rule 9). Owner directive 2026-10-02.
public struct ClientPracticeProfile: Codable, Sendable, Equatable {
    public enum SalesTaxFrequency: String, Codable, Sendable, CaseIterable {
        case none, monthly, quarterly, yearly
        public var label: String {
            switch self {
            case .none: return "No sales tax"
            case .monthly: return "Monthly"
            case .quarterly: return "Quarterly"
            case .yearly: return "Yearly"
            }
        }
    }

    public var salesTaxFrequency: SalesTaxFrequency
    /// An LLC, corporation or partnership doing business in Texas, so the
    /// May 15 franchise tax Public Information Report applies.
    public var texasEntity: Bool
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
    /// False until the bookkeeper has reviewed this client's profile once.
    public var reviewed: Bool

    public init(salesTaxFrequency: SalesTaxFrequency = .none, texasEntity: Bool = true, files1099s: Bool = false, hasEmployees: Bool = false,
                filesIFTA: Bool = false, filesForm2290: Bool = false, statementsDueDay: Int = 10, reportBusinessDay: Int = 15,
                industry: IndustryTemplate.Kind = .general, reviewed: Bool = false) {
        self.salesTaxFrequency = salesTaxFrequency
        self.texasEntity = texasEntity
        self.files1099s = files1099s
        self.hasEmployees = hasEmployees
        self.filesIFTA = filesIFTA
        self.filesForm2290 = filesForm2290
        self.statementsDueDay = statementsDueDay
        self.reportBusinessDay = reportBusinessDay
        self.industry = industry
        self.reviewed = reviewed
    }
}
