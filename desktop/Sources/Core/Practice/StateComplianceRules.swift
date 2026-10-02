import Foundation

/// State-by-state filing rules for the compliance calendar (owner directive
/// 2026-10-02: clients nationwide). A state is `verified` only when its
/// sales tax due dates and its annual-report rule were checked on that
/// state's own revenue department and Secretary of State sites (sources
/// listed per state). Unverified states never get a guessed date: the
/// calendar lists them as "verify with the state" items (CLAUDE.md rule 5).
public struct StateRule: Sendable, Equatable {
    public struct SalesTax: Sendable, Equatable {
        /// Day of the following month a monthly return is due (0 = last day).
        public var monthlyDay: Int?
        /// Day of the month after the quarter a quarterly return is due (0 = last day).
        public var quarterlyDay: Int?
        /// Months the state's quarters END in (New York's run Mar–May etc.).
        public var quarterEndMonths: [Int] = [3, 6, 9, 12]
        /// (month, day) due dates for semiannual filers, first half then second half.
        public var semiannual: [(Int, Int)]?
        /// (month, day) the yearly return for the prior year is due.
        public var yearly: (Int, Int)?
        /// An annual return every filer owes in addition (Michigan, Feb 28).
        public var allFilersAnnual: (Int, Int)?
        public var agency: String

        public static func == (a: SalesTax, b: SalesTax) -> Bool {
            a.monthlyDay == b.monthlyDay && a.quarterlyDay == b.quarterlyDay && a.quarterEndMonths == b.quarterEndMonths && a.agency == b.agency
        }
    }

    public enum AnnualReport: Sendable, Equatable {
        case none
        /// Same date every year.
        case fixed(month: Int, day: Int)
        /// Last day of the month the entity was formed.
        case endOfAnniversaryMonth
        /// Before the first day of the anniversary month (last day of the month before).
        case beforeAnniversaryMonth
        /// Every two years, by the end of the anniversary month.
        case biennialEndOfAnniversaryMonth
        /// Last day of the second month after the anniversary month (Colorado).
        case endOfSecondMonthAfterAnniversary
        /// Each corporation has its own date; look it up.
        case lookUp
    }

    /// A dated state filing besides sales tax and the annual report.
    public struct ExtraFiling: Sendable, Equatable {
        public let key: String
        public let month: Int
        public let day: Int
        public let title: String
        public let detail: String
        /// Only LLCs owe it (California's $800 LLC tax).
        public let llcOnly: Bool
    }

    public let code: String
    public let name: String
    /// nil = no statewide sales tax.
    public let salesTax: SalesTax?
    public let hasStatewideSalesTax: Bool
    /// The LLC annual report rule; corporations use `corporationReport` when known.
    public let annualReport: AnnualReport?
    public let annualReportName: String
    public let corporationReport: AnnualReport?
    public let extraFilings: [ExtraFiling]
    /// Undated reminders worth knowing (franchise and gross-receipts taxes etc.).
    public let notes: [String]
    public let hasStateIncomeTax: Bool
    /// Remote-seller sales threshold, when checked on the state's site.
    public let nexusThreshold: NexusThreshold?
    public let verified: Bool
    public let sources: [String]

    public var label: String { "\(name) (\(code))" }
}

public struct NexusThreshold: Sendable, Equatable {
    public let amount: Money
    public let minimumTransactions: Int?   // both must be exceeded (New York)
    public let description: String
}

public enum StateComplianceRules {
    static func usd(_ d: Int64) -> Money { Money(minorUnits: d * 100, currency: .usd) }

    /// Most states use $100,000 in sales over 12 months (some add a 200-transaction test).
    /// Used only to SCREEN states that have no checked threshold.
    public static let commonNexusScreen = NexusThreshold(amount: usd(100_000), minimumTransactions: nil,
        description: "$100,000 in sales over 12 months is the most common state threshold; check this state's exact rule")

    private static let noIncomeTax: Set<String> = ["AK", "FL", "NV", "NH", "SD", "TN", "TX", "WA", "WY"]
    private static let noSalesTax: Set<String> = ["AK", "DE", "MT", "NH", "OR"]

    private static let names: [(String, String)] = [
        ("AL", "Alabama"), ("AK", "Alaska"), ("AZ", "Arizona"), ("AR", "Arkansas"), ("CA", "California"), ("CO", "Colorado"), ("CT", "Connecticut"),
        ("DE", "Delaware"), ("DC", "District of Columbia"), ("FL", "Florida"), ("GA", "Georgia"), ("HI", "Hawaii"), ("ID", "Idaho"), ("IL", "Illinois"),
        ("IN", "Indiana"), ("IA", "Iowa"), ("KS", "Kansas"), ("KY", "Kentucky"), ("LA", "Louisiana"), ("ME", "Maine"), ("MD", "Maryland"),
        ("MA", "Massachusetts"), ("MI", "Michigan"), ("MN", "Minnesota"), ("MS", "Mississippi"), ("MO", "Missouri"), ("MT", "Montana"), ("NE", "Nebraska"),
        ("NV", "Nevada"), ("NH", "New Hampshire"), ("NJ", "New Jersey"), ("NM", "New Mexico"), ("NY", "New York"), ("NC", "North Carolina"),
        ("ND", "North Dakota"), ("OH", "Ohio"), ("OK", "Oklahoma"), ("OR", "Oregon"), ("PA", "Pennsylvania"), ("RI", "Rhode Island"),
        ("SC", "South Carolina"), ("SD", "South Dakota"), ("TN", "Tennessee"), ("TX", "Texas"), ("UT", "Utah"), ("VT", "Vermont"), ("VA", "Virginia"),
        ("WA", "Washington"), ("WV", "West Virginia"), ("WI", "Wisconsin"), ("WY", "Wyoming")
    ]

    public static var allStates: [(code: String, name: String)] { names.map { (code: $0.0, name: $0.1) } }

    public static func name(for code: String) -> String? { names.first { $0.0 == code.uppercased() }?.1 }

    /// The checked states. Each source is the state's own site, retrieved 2026-10-02.
    private static let verifiedRules: [String: StateRule] = {
        func st(_ monthly: Int?, _ quarterly: Int?, agency: String, quarters: [Int] = [3, 6, 9, 12], semi: [(Int, Int)]? = nil, yearly: (Int, Int)? = nil, allAnnual: (Int, Int)? = nil) -> StateRule.SalesTax {
            StateRule.SalesTax(monthlyDay: monthly, quarterlyDay: quarterly, quarterEndMonths: quarters, semiannual: semi, yearly: yearly, allFilersAnnual: allAnnual, agency: agency)
        }
        func rule(_ code: String, _ sales: StateRule.SalesTax?, _ report: StateRule.AnnualReport, reportName: String, corp: StateRule.AnnualReport? = nil,
                  extra: [StateRule.ExtraFiling] = [], notes: [String] = [], nexus: NexusThreshold? = nil, sources: [String]) -> StateRule {
            StateRule(code: code, name: name(for: code)!, salesTax: sales, hasStatewideSalesTax: sales != nil, annualReport: report, annualReportName: reportName,
                      corporationReport: corp, extraFilings: extra, notes: notes, hasStateIncomeTax: !noIncomeTax.contains(code), nexusThreshold: nexus, verified: true, sources: sources)
        }
        let list: [StateRule] = [
            rule("TX", st(20, 20, agency: "Texas Comptroller", yearly: (1, 20)), .fixed(month: 5, day: 15), reportName: "Franchise tax Public Information Report (and franchise tax report if revenue is over $2.65 million)",
                 corp: .fixed(month: 5, day: 15), notes: ["No state income tax. The franchise (margin) tax applies to LLCs, corporations and partnerships; at or under the $2.65 million no tax due threshold only the Public Information or Ownership Information Report is filed."],
                 nexus: NexusThreshold(amount: usd(500_000), minimumTransactions: nil, description: "$500,000 of Texas revenue in the preceding 12 months"),
                 sources: ["comptroller.texas.gov/taxes/sales", "comptroller.texas.gov/taxes/franchise", "comptroller.texas.gov/taxes/sales/remote-sellers.php"]),
            rule("CA", st(0, 0, agency: "California Department of Tax and Fee Administration (CDTFA)", yearly: (1, 31)), .biennialEndOfAnniversaryMonth,
                 reportName: "Statement of Information (every 2 years)",
                 extra: [StateRule.ExtraFiling(key: "ca-llc-tax", month: 4, day: 15, title: "California $800 LLC annual tax", detail: "Form FTB 3522, due the 15th day of the 4th month of the tax year (April 15 for calendar-year LLCs).", llcOnly: true)],
                 notes: ["Quarterly-prepay filers also owe prepayments on the 24th of each month in the quarter.", "Corporations owe a minimum franchise tax; the CPA handles it."],
                 nexus: NexusThreshold(amount: usd(500_000), minimumTransactions: nil, description: "$500,000 of sales delivered into California in the current or preceding calendar year"),
                 sources: ["cdtfa.ca.gov/taxes-and-fees/sales-use-tax-returns-filing-dates.htm", "sos.ca.gov/business-programs/business-entities/statements", "ftb.ca.gov/file/business/types/limited-liability-company", "cdtfa.ca.gov/industry/wayfair"]),
            rule("FL", st(20, 20, agency: "Florida Department of Revenue", semi: [(7, 20), (1, 20)], yearly: (1, 20)), .fixed(month: 5, day: 1), reportName: "Annual report (Sunbiz, $400 late fee after May 1)",
                 corp: .fixed(month: 5, day: 1), notes: ["Florida sales tax is due on the 1st and late after the 20th."],
                 sources: ["floridarevenue.com/taxes/taxesfees/Pages/sales_tax.aspx", "dos.fl.gov/sunbiz/manage-business/efile/annual-report"]),
            rule("NY", st(20, 20, agency: "New York State Department of Taxation and Finance", quarters: [5, 8, 11, 2], yearly: (3, 20)), .biennialEndOfAnniversaryMonth,
                 reportName: "Biennial statement", corp: .biennialEndOfAnniversaryMonth,
                 notes: ["New York sales tax quarters run March–May, June–August, September–November and December–February. Monthly filers are 'part-quarterly' filers."],
                 nexus: NexusThreshold(amount: usd(500_000), minimumTransactions: 100, description: "more than $500,000 AND more than 100 sales into New York over the last four sales tax quarters"),
                 sources: ["tax.ny.gov/pubs_and_bulls/tg_bulletins/st/filing_requirements_for_sales_and_use_tax_returns.htm", "dos.ny.gov/biennial-statements-business-corporations-and-limited-liability-companies", "tax.ny.gov/pubs_and_bulls/publications/sales/nexus.htm"]),
            rule("IL", st(20, 20, agency: "Illinois Department of Revenue", yearly: (1, 20)), .beforeAnniversaryMonth, reportName: "Annual report (due before the anniversary month)",
                 sources: ["tax.illinois.gov (Pub-113, Form ST-1)", "ilsos.gov (Guide for Organizing Domestic LLCs)"]),
            rule("PA", st(20, 20, agency: "Pennsylvania Department of Revenue", semi: [(8, 20), (2, 20)]), .fixed(month: 9, day: 30), reportName: "Annual report",
                 corp: .fixed(month: 6, day: 30), sources: ["pa.gov REV-819 (sales tax due dates)", "pa.gov/agencies/dos/programs/business/types-of-filings-and-registrations/annual-reports"]),
            rule("OH", st(23, nil, agency: "Ohio Department of Taxation", semi: [(7, 23), (1, 23)]), StateRule.AnnualReport.none, reportName: "No annual report for LLCs",
                 corp: StateRule.AnnualReport.none, notes: ["Ohio's Commercial Activity Tax (CAT) applies to larger businesses by gross receipts; check with the CPA."],
                 sources: ["tax.ohio.gov (sales and use due dates)", "ohiosos.gov/business/ohio-business-roadmap/frequently-asked-questions"]),
            rule("GA", st(20, 20, agency: "Georgia Department of Revenue", yearly: (1, 20)), .fixed(month: 4, day: 1), reportName: "Annual registration",
                 corp: .fixed(month: 4, day: 1), sources: ["dor.georgia.gov/taxes/business-taxes/sales-use-tax/file-pay", "sos.ga.gov/how-to-guide/how-file-annual-registration"]),
            rule("NC", st(20, 0, agency: "North Carolina Department of Revenue"), .fixed(month: 4, day: 15), reportName: "Annual report",
                 corp: .fixed(month: 4, day: 15), sources: ["ncdor.gov (filing frequency and due dates)", "sosnc.gov (annual reports)"]),
            rule("MI", st(20, 20, agency: "Michigan Department of Treasury", allAnnual: (2, 28)), .fixed(month: 2, day: 15), reportName: "Annual statement",
                 corp: .fixed(month: 5, day: 15), notes: ["Every Michigan sales, use and withholding taxpayer also files an annual return by February 28."],
                 sources: ["michigan.gov/taxes/business-taxes/sales-use-tax", "michigan.gov/lara/bureau-list/cscl/corps/michigan-business-roadmap/annual-reports-and-annual-statements"]),
            rule("NJ", st(20, 20, agency: "New Jersey Division of Taxation"), .endOfAnniversaryMonth, reportName: "Annual report",
                 corp: .endOfAnniversaryMonth, notes: ["Monthly remittances (ST-51) apply only when more than $500 is due for the month and over $30,000 was collected the prior year."],
                 sources: ["nj.gov/treasury/taxation (ST-50/ST-51)", "business.nj.gov/pages/filings-and-accounting"]),
            rule("VA", st(20, 20, agency: "Virginia Tax"), .endOfAnniversaryMonth, reportName: "Annual registration fee",
                 sources: ["tax.virginia.gov/retail-sales-and-use-tax", "scc.virginia.gov/businesses/business-faqs/annual-registration-fees"]),
            rule("WA", st(25, 0, agency: "Washington Department of Revenue"), .endOfAnniversaryMonth, reportName: "Annual report",
                 corp: .endOfAnniversaryMonth, notes: ["No state income tax. Washington's business and occupation (B&O) tax on gross receipts is reported on the same excise tax return as sales tax."],
                 sources: ["dor.wa.gov/file-pay-taxes/filing-frequencies-due-dates/2026-excise-tax-return-due-dates", "sos.wa.gov/corporations-charities/business-entities/maintain-business-compliance/annual-reports"]),
            rule("AZ", st(20, 20, agency: "Arizona Department of Revenue (TPT)", yearly: (1, 20)), StateRule.AnnualReport.none, reportName: "No annual report for LLCs",
                 corp: .lookUp, notes: ["Arizona's sales tax is the transaction privilege tax (TPT). Corporations file an annual report on their own date; LLCs file none."],
                 sources: ["azdor.gov/transaction-privilege-tax/tpt-license/tpt-filing-frequency", "azcc.gov/faqs/BusinessServicesFAQs"]),
            rule("CO", st(20, 20, agency: "Colorado Department of Revenue", yearly: (1, 20)), .endOfSecondMonthAfterAnniversary, reportName: "Periodic report",
                 corp: .endOfSecondMonthAfterAnniversary, notes: ["Many Colorado cities collect their own sales tax separately from the state."],
                 sources: ["tax.colorado.gov/sales-tax-filing-information", "sos.state.co.us/pubs/business/FAQs/reports.html"]),
            rule("TN", st(20, 20, agency: "Tennessee Department of Revenue", yearly: (1, 20)), .fixed(month: 4, day: 1), reportName: "Annual report (calendar fiscal year)",
                 corp: .fixed(month: 4, day: 1), notes: ["No tax on wages, but Tennessee's franchise and excise taxes apply to most LLCs and corporations; the CPA files them."],
                 sources: ["tn.gov/revenue/taxes/sales-and-use-tax/due-dates-and-tax-rates.html", "sos.tn.gov (annual report due date)"]),
        ]
        return Dictionary(uniqueKeysWithValues: list.map { ($0.code, $0) })
    }()

    public static var verifiedStates: [String] { verifiedRules.keys.sorted() }

    public static func rule(for code: String) -> StateRule {
        let c = code.uppercased()
        if let r = verifiedRules[c] { return r }
        let n = name(for: c) ?? c
        return StateRule(code: c, name: n, salesTax: nil, hasStatewideSalesTax: !noSalesTax.contains(c), annualReport: nil, annualReportName: "Annual report",
                         corporationReport: nil, extraFilings: [], notes: [], hasStateIncomeTax: !noIncomeTax.contains(c), nexusThreshold: nil, verified: false, sources: [])
    }
}
