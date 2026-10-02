import Foundation

/// Industry setups (owner directive 2026-10-02, for the Permian Basin market
/// around Odessa): the accounts a well-kept chart for that industry has, and
/// how to track profitability. The comparison only reports what the
/// client's chart of accounts has or lacks; it never creates accounts.
public enum IndustryTemplate {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case general, hotShotTrucking, oilfieldServices
        public var label: String {
            switch self {
            case .general: return "General small business"
            case .hotShotTrucking: return "Hot shot trucking / owner-operator"
            case .oilfieldServices: return "Oilfield services"
            }
        }
    }

    public struct RecommendedAccount: Sendable, Equatable, Identifiable {
        public var id: String { name }
        public let name: String
        public let type: LedgerAccountType
        public let why: String
        /// Lowercased words; an existing account whose name contains any of them counts as a match.
        public let matchWords: [String]
    }

    public struct Comparison: Sendable, Equatable {
        public let present: [(RecommendedAccount, LedgerAccount)]
        public let missing: [RecommendedAccount]
        public static func == (a: Comparison, b: Comparison) -> Bool {
            a.missing == b.missing && a.present.map(\.0) == b.present.map(\.0) && a.present.map(\.1.id) == b.present.map(\.1.id)
        }
    }

    public static func accounts(for kind: Kind) -> [RecommendedAccount] {
        func a(_ n: String, _ t: LedgerAccountType, _ why: String, _ words: [String]) -> RecommendedAccount { RecommendedAccount(name: n, type: t, why: why, matchWords: words) }
        switch kind {
        case .general:
            return [
                a("Owner's Draw or Distributions", .equity, "Owner withdrawals kept out of expenses.", ["draw", "distribution"]),
                a("Sales Tax Payable", .otherCurrentLiability, "Collected sales tax is owed to the state, not income.", ["sales tax"]),
                a("Payroll Liabilities", .otherCurrentLiability, "Withholdings and employer taxes until paid.", ["payroll liabilit", "payroll tax payable"]),
                a("Bank Service Charges", .expense, "Bank and card processing fees.", ["bank", "service charge", "merchant"]),
                a("Interest Expense", .expense, "Interest part of loan payments.", ["interest"]),
            ]
        case .hotShotTrucking:
            return [
                a("Freight Revenue", .income, "Gross load revenue, recorded at the full rate, not the factored net.", ["freight", "hauling", "load revenue", "trucking revenue"]),
                a("Detention and Accessorial Income", .income, "Detention, layover and lumper reimbursements tracked apart so missing pay is noticed.", ["detention", "accessorial", "layover"]),
                a("Fuel Surcharge Income", .income, "Fuel surcharges billed to brokers.", ["fuel surcharge"]),
                a("Factoring Fees", .expense, "What the factoring company keeps; never netted out of revenue.", ["factoring"]),
                a("Factoring Reserve Receivable", .otherCurrentAsset, "Reserve held back by the factor until released.", ["reserve"]),
                a("Fuel", .expense, "Usually the largest cost; reconcile fuel card statements.", ["fuel"]),
                a("Tolls and Scales", .expense, "Tolls and scale tickets per load.", ["toll", "scale"]),
                a("Truck Repairs and Maintenance", .expense, "Repairs, tires and service per unit.", ["repair", "maintenance", "tire"]),
                a("Truck Insurance", .expense, "Liability, cargo and physical damage coverage.", ["insurance"]),
                a("Permits and Licenses", .expense, "IFTA, IRP, authority and permit costs.", ["permit", "license"]),
                a("Dispatch and Load Board Fees", .expense, "Dispatch services, load boards and ELD subscriptions.", ["dispatch", "load board", "eld"]),
                a("Truck and Trailer (fixed assets)", .fixedAsset, "Equipment capitalized and depreciated, not expensed.", ["truck", "trailer", "vehicle", "equipment"]),
                a("Equipment Loan", .longTermLiability, "Truck or trailer financing; payments split into principal and interest.", ["loan", "note payable", "notes payable"]),
            ]
        case .oilfieldServices:
            return [
                a("Service Revenue", .income, "Job revenue invoiced from field tickets.", ["service", "revenue", "sales"]),
                a("Equipment Rental Income", .income, "Equipment rented to operators, tracked apart from service work.", ["rental income", "equipment rental income"]),
                a("Retainage Receivable", .otherCurrentAsset, "Holdbacks owed by operators until released.", ["retainage", "retention"]),
                a("Job Labor", .costOfGoodsSold, "Crew labor charged to jobs.", ["labor", "wages", "payroll"]),
                a("Subcontractors", .costOfGoodsSold, "Contract crews and services (1099s).", ["subcontract", "contract labor"]),
                a("Fuel", .expense, "Trucks and equipment fuel; reconcile fuel cards.", ["fuel"]),
                a("Equipment Rental Expense", .expense, "Equipment rented from others for jobs.", ["equipment rental", "rent"]),
                a("Repairs and Maintenance", .expense, "Repairs by unit to judge replace-or-repair.", ["repair", "maintenance"]),
                a("Chemicals and Materials", .costOfGoodsSold, "Materials used on jobs.", ["material", "chemical", "supplies"]),
                a("Disposal Fees", .expense, "Saltwater and waste disposal charges.", ["disposal"]),
                a("Per Diem", .expense, "Crew per diem, per the CPA's treatment.", ["per diem"]),
                a("Safety and Training", .expense, "Required safety training and certifications.", ["safety", "training"]),
                a("Heavy Equipment and Trucks (fixed assets)", .fixedAsset, "Capitalized and depreciated.", ["equipment", "truck", "vehicle"]),
                a("Equipment Loans", .longTermLiability, "Equipment financing.", ["loan", "note payable", "notes payable"]),
            ]
        }
    }

    /// Tracking advice shown on the page.
    public static func tracking(for kind: Kind) -> [String] {
        switch kind {
        case .general:
            return ["Use classes or locations only if the owner will read reports by them."]
        case .hotShotTrucking:
            return ["Tag each load or lane with a class or project so revenue and direct costs (fuel, tolls, factoring) can be compared per run.",
                    "Record the full rate per load as revenue and the factoring fee as an expense.",
                    "Compare broker rate confirmations to settlements to catch missing detention pay.",
                    "Keep miles by state and fuel receipts for the quarterly IFTA return."]
        case .oilfieldServices:
            return ["Use customers/projects for operator and job, and classes or locations for service line or yard.",
                    "Put the field ticket number on every invoice.",
                    "Watch receivables aging by operator; 60 to 90 days is common.",
                    "Allocate shared equipment costs (a truck used on several wells) by hours or miles if the client wants job margins."]
        }
    }

    public static func compare(_ kind: Kind, accounts: [LedgerAccount]) -> Comparison {
        var present: [(RecommendedAccount, LedgerAccount)] = []
        var missing: [RecommendedAccount] = []
        for rec in self.accounts(for: kind) {
            let sameFamily = accounts.filter { family($0.accountType) == family(rec.type) }
            if let match = sameFamily.first(where: { acct in rec.matchWords.contains { acct.name.lowercased().contains($0) } }) {
                present.append((rec, match))
            } else {
                missing.append(rec)
            }
        }
        return Comparison(present: present, missing: missing)
    }

    /// Broad account family, so an "Interest" income account doesn't satisfy "Interest Expense".
    static func family(_ t: LedgerAccountType) -> Int {
        switch t {
        case .income, .otherIncome: return 1
        case .expense, .otherExpense, .costOfGoodsSold: return 2
        case .equity: return 3
        case .accountsPayable, .creditCard, .otherCurrentLiability, .longTermLiability: return 4
        default: return 5
        }
    }
}
