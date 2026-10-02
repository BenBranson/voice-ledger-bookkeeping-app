import Foundation

/// Industry setups (owner directive 2026-10-02, for the Permian Basin market
/// around Odessa): the accounts a well-kept chart for that industry has, and
/// how to track profitability. The comparison only reports what the
/// client's chart of accounts has or lacks; it never creates accounts.
public enum IndustryTemplate {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case general, hotShotTrucking, oilfieldServices, construction, restaurant, retailEcommerce, professionalServices
        case propertyManagement, medicalDental, salonPersonalCare, homeFieldServices, groceryConvenience
        public var label: String {
            switch self {
            case .general: return "General small business"
            case .hotShotTrucking: return "Hot shot trucking / owner-operator"
            case .oilfieldServices: return "Oilfield services"
            case .construction: return "Construction and trades"
            case .restaurant: return "Restaurant, bar or food service"
            case .retailEcommerce: return "Retail store or e-commerce"
            case .professionalServices: return "Professional services (consulting, agency, law, design)"
            case .propertyManagement: return "Real estate rentals / property management"
            case .medicalDental: return "Medical, dental or therapy practice"
            case .salonPersonalCare: return "Salon, spa or personal care"
            case .homeFieldServices: return "Home and field services (cleaning, landscaping, pest, HVAC)"
            case .groceryConvenience: return "Grocery or convenience store"
            }
        }

        /// How much harder than an average client this industry is to keep.
        public var complexity: Complexity {
            switch self {
            case .groceryConvenience: return .high
            case .construction, .restaurant, .retailEcommerce, .medicalDental, .propertyManagement, .oilfieldServices, .hotShotTrucking: return .elevated
            default: return .standard
            }
        }

        /// Carries inventory, so the inventory review applies.
        public var usesInventory: Bool { [.retailEcommerce, .restaurant, .groceryConvenience].contains(self) }
    }

    public enum Complexity: String, Sendable {
        case standard, elevated, high
        public var pricingNote: String {
            switch self {
            case .standard: return "Standard complexity. Price on volume."
            case .elevated: return "Above-average complexity (job costing, inventory, payouts or industry rules). Quote at least the middle tier."
            case .high: return "High complexity: heavy inventory, many daily sales and vendor deliveries. Quote the top tier, require a working point-of-sale integration, or decline."
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
        case .construction:
            return [
                a("Contract Revenue", .income, "Job revenue, invoiced by job or progress billing.", ["contract", "construction", "job income", "sales", "revenue"]),
                a("Retainage Receivable", .otherCurrentAsset, "Holdbacks the customer keeps until the job is accepted.", ["retainage", "retention"]),
                a("Job Materials", .costOfGoodsSold, "Materials charged to jobs.", ["material"]),
                a("Subcontractors", .costOfGoodsSold, "Subs by job; collect W-9s and certificates of insurance.", ["subcontract", "contract labor"]),
                a("Job Labor", .costOfGoodsSold, "Crew wages charged to jobs.", ["labor", "wages"]),
                a("Equipment Rental", .expense, "Equipment rented for jobs.", ["equipment rental", "rental"]),
                a("Permits and Licenses", .expense, "Building permits and trade licenses.", ["permit", "license"]),
                a("Customer Deposits", .otherCurrentLiability, "Deposits received before work starts are owed back until earned.", ["deposit", "unearned"]),
                a("Vehicles and Equipment (fixed assets)", .fixedAsset, "Capitalized and depreciated.", ["vehicle", "truck", "equipment"]),
            ]
        case .restaurant:
            return [
                a("Food Sales", .income, "Food sales from the point-of-sale daily summary.", ["food"]),
                a("Beverage and Alcohol Sales", .income, "Tracked apart for margins and liquor tax.", ["beverage", "alcohol", "bar", "liquor"]),
                a("Tips Payable", .otherCurrentLiability, "Card tips owed to staff until paid out.", ["tip"]),
                a("Sales Tax Payable", .otherCurrentLiability, "Collected sales tax owed to the state.", ["sales tax"]),
                a("Food Cost", .costOfGoodsSold, "Food purchases; compare to food sales every month.", ["food cost", "food purchase", "cost of food"]),
                a("Beverage Cost", .costOfGoodsSold, "Beverage and alcohol purchases.", ["beverage cost", "liquor cost", "alcohol cost"]),
                a("Merchant and Delivery App Fees", .expense, "Card processing and delivery-app commissions.", ["merchant", "processing", "doordash", "uber", "grubhub", "delivery"]),
                a("Inventory", .otherCurrentAsset, "Food and beverage on hand at month end, if counted.", ["inventory"]),
            ]
        case .retailEcommerce:
            return [
                a("Product Sales", .income, "Gross sales before platform fees.", ["sales", "product"]),
                a("Shipping Income", .income, "Shipping charged to customers.", ["shipping income", "shipping and delivery income"]),
                a("Inventory Asset", .otherCurrentAsset, "Stock on hand; matches the count.", ["inventory"]),
                a("Cost of Goods Sold", .costOfGoodsSold, "Cost of items sold.", ["cost of goods", "cogs", "cost of sales"]),
                a("Merchant and Platform Fees", .expense, "Shopify, Amazon, Etsy, Stripe and card fees, recorded gross, not netted out of sales.", ["merchant", "platform", "shopify", "amazon", "stripe", "paypal", "etsy"]),
                a("Shipping and Postage", .expense, "Outbound shipping costs.", ["shipping", "postage"]),
                a("Sales Tax Payable", .otherCurrentLiability, "Tax collected by the store (marketplaces often collect it themselves).", ["sales tax"]),
                a("Payouts Clearing", .otherCurrentAsset, "Platform payouts in transit to the bank; should clear to zero.", ["clearing", "payout", "undeposited"]),
            ]
        case .professionalServices:
            return [
                a("Service Revenue", .income, "Fees billed to clients.", ["service", "fee", "consulting", "revenue"]),
                a("Reimbursable Expenses", .income, "Costs billed back to clients, tracked apart.", ["reimburs", "billable"]),
                a("Contract Labor", .expense, "Freelancers and subcontractors (1099s).", ["contract labor", "contractor", "subcontract"]),
                a("Software and Subscriptions", .expense, "SaaS tools.", ["software", "subscription", "dues"]),
                a("Professional Liability Insurance", .expense, "E&O or malpractice coverage.", ["insurance"]),
                a("Client Retainers / Unearned Revenue", .otherCurrentLiability, "Retainers received before work is done.", ["retainer", "unearned", "deferred"]),
            ]
        case .propertyManagement:
            return [
                a("Rental Income", .income, "Rent by property (use classes or locations per property).", ["rent", "rental"]),
                a("Tenant Security Deposits", .otherCurrentLiability, "Deposits owed back to tenants; never income.", ["security deposit", "tenant deposit", "deposit"]),
                a("Repairs and Maintenance", .expense, "Repairs by property.", ["repair", "maintenance"]),
                a("Property Taxes", .expense, "Property taxes by property.", ["property tax"]),
                a("Mortgage Interest", .expense, "Interest part of each mortgage payment.", ["mortgage interest", "interest"]),
                a("Mortgages Payable", .longTermLiability, "Principal balance by property.", ["mortgage", "note payable", "loan"]),
                a("Buildings (fixed assets)", .fixedAsset, "Purchase price split between building and land.", ["building", "property", "land"]),
                a("Management Fees", .expense, "Fees paid to a property manager.", ["management fee"]),
            ]
        case .medicalDental:
            return [
                a("Patient and Insurance Revenue", .income, "Collections by payer type (insurance, patient, cash).", ["patient", "insurance", "fee", "revenue", "income"]),
                a("Refunds Payable", .otherCurrentLiability, "Patient or insurance overpayments owed back.", ["refund"]),
                a("Medical or Dental Supplies", .costOfGoodsSold, "Clinical supplies.", ["supplies", "dental", "medical"]),
                a("Lab Fees", .costOfGoodsSold, "Outside lab charges.", ["lab"]),
                a("Malpractice Insurance", .expense, "Professional liability coverage.", ["malpractice", "insurance"]),
                a("Equipment (fixed assets)", .fixedAsset, "Clinical equipment capitalized.", ["equipment"]),
                a("Equipment Loans", .longTermLiability, "Equipment financing.", ["loan", "note payable"]),
            ]
        case .salonPersonalCare:
            return [
                a("Service Revenue", .income, "Services from the booking system's daily summary.", ["service", "revenue", "sales"]),
                a("Retail Product Sales", .income, "Product sales tracked apart (usually taxable).", ["product", "retail"]),
                a("Tips Payable", .otherCurrentLiability, "Card tips owed to staff.", ["tip"]),
                a("Booth or Chair Rent Income", .income, "Rent from independent stylists.", ["booth", "chair rent"]),
                a("Commissions", .expense, "Stylist commissions (employees through payroll; contractors get 1099s).", ["commission"]),
                a("Salon Supplies", .costOfGoodsSold, "Color, products used in services.", ["supplies", "product"]),
                a("Merchant Fees", .expense, "Card processing.", ["merchant", "processing", "square"]),
            ]
        case .homeFieldServices:
            return [
                a("Service Revenue", .income, "Jobs or recurring service plans.", ["service", "revenue", "sales"]),
                a("Job Materials", .costOfGoodsSold, "Materials used on jobs.", ["material", "supplies", "chemical", "plant", "soil"]),
                a("Field Labor", .costOfGoodsSold, "Crew wages.", ["labor", "wages", "payroll"]),
                a("Fuel", .expense, "Vehicle fuel.", ["fuel", "gas"]),
                a("Vehicle Repairs", .expense, "Truck and equipment repairs.", ["repair", "maintenance", "automobile"]),
                a("Equipment Rental", .expense, "Rented equipment.", ["equipment rental", "rental"]),
                a("Vehicles and Equipment (fixed assets)", .fixedAsset, "Trucks, mowers, tools capitalized.", ["vehicle", "truck", "equipment"]),
                a("Customer Deposits", .otherCurrentLiability, "Prepaid service plans until earned.", ["deposit", "unearned"]),
            ]
        case .groceryConvenience:
            return [
                a("Grocery Sales (non-taxable)", .income, "Sales split taxable vs non-taxable from the point of sale.", ["grocery", "food sales", "sales"]),
                a("Taxable Sales", .income, "Taxable items (prepared food, general merchandise, beer and wine).", ["taxable"]),
                a("Lottery and Money Order Clearing", .otherCurrentLiability, "Lottery and money order collections owed to others; never income.", ["lottery", "money order"]),
                a("Inventory Asset", .otherCurrentAsset, "Stock on hand; must match counts.", ["inventory"]),
                a("Cost of Goods Sold", .costOfGoodsSold, "Purchases from distributors; compare to sales weekly.", ["cost of goods", "cogs", "purchases"]),
                a("Sales Tax Payable", .otherCurrentLiability, "Collected sales tax.", ["sales tax"]),
                a("EBT and Card Clearing", .otherCurrentAsset, "EBT, card and vendor-direct settlements in transit.", ["ebt", "clearing", "undeposited"]),
                a("Cash Over/Short", .expense, "Daily drawer differences; should stay small.", ["over/short", "over short", "cash short"]),
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
        case .construction:
            return ["Track every job as a QuickBooks project so income and costs compare by job.",
                    "Watch over- and under-billing on long jobs; progress billing can run ahead of the work.",
                    "Collect W-9s and insurance certificates from every sub before paying them."]
        case .restaurant:
            return ["Book one daily sales journal from the point-of-sale summary (sales by type, tax, tips, card and cash), then match deposits to it.",
                    "Food cost runs about 28–35% of food sales in most restaurants; a sudden jump means waste, theft or missed sales.",
                    "Delivery apps pay out net of commissions; record gross sales and the fee."]
        case .retailEcommerce:
            return ["Record platform payouts gross: sales, minus fees, refunds and sales tax, through a clearing account that ends at zero.",
                    "Count inventory at least yearly (monthly for big sellers) and adjust the books to the count.",
                    "Check which states the client sells into; marketplaces usually collect sales tax, the client's own store may not."]
        case .professionalServices:
            return ["Track revenue by client or engagement if the owner wants profitability by client.",
                    "Retainers are a liability until the work is done."]
        case .propertyManagement:
            return ["Use a class or location per property so each has its own profit and loss.",
                    "Security deposits are owed back to tenants; keep them out of income.",
                    "Split each mortgage payment into principal, interest and escrow."]
        case .medicalDental:
            return ["Track collections by payer (insurance, patient, cash) from the practice software's deposit report.",
                    "Patient records stay in the practice software; the books should hold totals, not health details.",
                    "Credit balances (overpayments) are refunds owed, not income."]
        case .salonPersonalCare:
            return ["Book daily sales from the booking system: services, retail, tips, tax and payment types.",
                    "Know who is an employee and who rents a chair; it decides payroll vs 1099."]
        case .homeFieldServices:
            return ["Track recurring service plans separately from one-off jobs.",
                    "Tag jobs or routes with classes if the owner wants crew or route margins.",
                    "Watch seasonality: build the cash forecast around the slow months."]
        case .groceryConvenience:
            return ["Never record sales one register ticket at a time: book a daily journal from the point-of-sale summary and match each deposit.",
                    "Split taxable and non-taxable sales from the point of sale; groceries are often exempt while prepared food and general merchandise are not.",
                    "Lottery, money orders and bill-pay collections belong to others; run them through clearing accounts.",
                    "Inventory: rely on the point-of-sale system's counts, compare cost of goods to sales every month, and adjust the books to a physical count at least yearly."]
        }
    }

    /// Red flags to look for in this industry's books.
    public static func redFlags(for kind: Kind) -> [String] {
        switch kind {
        case .general: return ["Personal spending in the business account.", "Uncategorized transactions left at month end."]
        case .hotShotTrucking: return ["Factoring deposits booked net as revenue.", "Fuel on personal cards.", "Truck loan payments posted entirely to expense."]
        case .oilfieldServices: return ["One income account with no job detail.", "Equipment purchases expensed.", "Invoices that don't match field tickets."]
        case .construction: return ["Customer deposits booked as income before work is done.", "Subs paid without a W-9.", "Materials for one job charged to another."]
        case .restaurant: return ["Deposits that don't match daily sales.", "Tips recorded as income.", "Cash sales missing from the books."]
        case .retailEcommerce: return ["Platform payouts booked as sales (net of fees).", "Inventory never adjusted to a count.", "No sales tax collected in states past their threshold."]
        case .professionalServices: return ["Retainers booked as income on receipt.", "Owner's personal subscriptions in the business."]
        case .propertyManagement: return ["Security deposits in income.", "Mortgage payments all expensed.", "No per-property tracking."]
        case .medicalDental: return ["Patient credit balances left in income.", "Equipment leases not recorded."]
        case .salonPersonalCare: return ["Booth renters paid like employees (or the reverse).", "Tips in income."]
        case .homeFieldServices: return ["Prepaid plans booked as income up front.", "Personal truck use in business expenses."]
        case .groceryConvenience: return ["Cash over/short that keeps growing.", "Lottery collections booked as sales.", "Cost of goods jumping without a price change.", "Vendor-direct deliveries (bread, beer, chips) paid in cash and never entered."]
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
