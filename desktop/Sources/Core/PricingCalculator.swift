import Foundation

/// Owner directive (2026-08-31): a monthly-retainer calculator and a
/// separate cleanup-project calculator, kept as two distinct quotes rather
/// than one blended price — "cleanup is a one-time forensic project, the
/// retainer is a recurring subscription; bundling them into one number
/// underprices the upfront labor a messy client actually needs." This
/// matches pricing guidance already on record for this project (see
/// `docs/VOICE_LEDGER_HANDOFF.md`'s note on why Cleanup Assessment exists
/// partly as a sales/pricing artifact).
///
/// CLAUDE.md rule 1: every number here is plain arithmetic on inputs the
/// bookkeeper themselves provides (hourly rate, which volume/complexity
/// flags apply) — there is no AI involved anywhere in this file, and
/// nothing here is "detected" from a client's real books. The coefficients
/// below (base hours per volume tier, hours per complexity add-on, the
/// months-behind multiplier, the 15%-per-issue complexity factor) are
/// starting defaults for a fractional-bookkeeping pricing model, not a
/// fact this app is asserting about any real client — the bookkeeper is
/// the one deciding which flags apply and what their own rate is.
public enum PricingCalculator {
    public enum VolumeTier: Int, CaseIterable, Identifiable, Sendable, Codable {
        case light, growth, high
        public var id: Int { rawValue }

        public var label: String {
            switch self {
            case .light: return "Under 200"
            case .growth: return "200–500"
            case .high: return "500+"
            }
        }

        /// Base monthly hours for ongoing bookkeeping at this transaction
        /// volume, before any complexity add-ons.
        var monthlyBaseHours: Double {
            switch self {
            case .light: return 3.0
            case .growth: return 5.5
            case .high: return 8.0
            }
        }

        /// How much a cleanup project scales with transaction volume —
        /// more transactions per month means more line items to untangle
        /// per month-behind, independent of how many months behind.
        var cleanupVolumeMultiplier: Double {
            switch self {
            case .light: return 1.0
            case .growth: return 1.3
            case .high: return 1.6
            }
        }
    }

    public struct MonthlyComplexityFlags: Sendable, Equatable, Codable {
        public var payrollProcessing: Bool
        public var salesTaxManagement: Bool
        /// Bank and card accounts beyond the 2 bank + 2 card every tier includes; each is a
        /// price-list "extra account" (2026-10-03, replaced a yes/no "5+ accounts" flag).
        public var extraAccounts: Int
        /// Old yes/no flag, kept so saved intakes and callers still work: true = 1 extra.
        public var multipleBankAccounts: Bool {
            get { extraAccounts > 0 }
            set { extraAccounts = newValue ? max(1, extraAccounts) : 0 }
        }
        public var inventoryTracking: Bool
        // Hard-to-price clients (owner directive 2026-10-02).
        /// Heavy inventory with many daily sales and deliveries (grocery, convenience, big retail).
        public var heavyInventory: Bool
        /// Sells into several states (sales tax nexus to watch).
        public var multiStateSales: Bool
        /// Large share of cash sales (drawer counts, over/short, deposits to match).
        public var cashHeavy: Bool
        /// Two or more related entities kept in separate books.
        public var multipleEntities: Bool
        /// Advisory add-on: Business Diagnosis, 13-week cash forecast, monthly review call.
        public var advisory: Bool

        public init(payrollProcessing: Bool = false, salesTaxManagement: Bool = false, multipleBankAccounts: Bool = false, inventoryTracking: Bool = false,
                    heavyInventory: Bool = false, multiStateSales: Bool = false, cashHeavy: Bool = false, multipleEntities: Bool = false, advisory: Bool = false,
                    extraAccounts: Int? = nil) {
            self.advisory = advisory
            self.extraAccounts = extraAccounts ?? (multipleBankAccounts ? 1 : 0)
            self.payrollProcessing = payrollProcessing
            self.salesTaxManagement = salesTaxManagement
            self.inventoryTracking = inventoryTracking
            self.heavyInventory = heavyInventory
            self.multiStateSales = multiStateSales
            self.cashHeavy = cashHeavy
            self.multipleEntities = multipleEntities
        }

        private enum CodingKeys: String, CodingKey {
            case payrollProcessing, salesTaxManagement, multipleBankAccounts, inventoryTracking, heavyInventory, multiStateSales, cashHeavy, multipleEntities, advisory, extraAccounts
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(payrollProcessing, forKey: .payrollProcessing)
            try c.encode(salesTaxManagement, forKey: .salesTaxManagement)
            try c.encode(multipleBankAccounts, forKey: .multipleBankAccounts)
            try c.encode(extraAccounts, forKey: .extraAccounts)
            try c.encode(inventoryTracking, forKey: .inventoryTracking)
            try c.encode(heavyInventory, forKey: .heavyInventory)
            try c.encode(multiStateSales, forKey: .multiStateSales)
            try c.encode(cashHeavy, forKey: .cashHeavy)
            try c.encode(multipleEntities, forKey: .multipleEntities)
            try c.encode(advisory, forKey: .advisory)
        }

        /// Older saved intakes lack the 2026-10-02 flags; they load as off.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            payrollProcessing = try c.decodeIfPresent(Bool.self, forKey: .payrollProcessing) ?? false
            salesTaxManagement = try c.decodeIfPresent(Bool.self, forKey: .salesTaxManagement) ?? false
            let hadExtra = try c.decodeIfPresent(Bool.self, forKey: .multipleBankAccounts) ?? false
            extraAccounts = try c.decodeIfPresent(Int.self, forKey: .extraAccounts) ?? (hadExtra ? 1 : 0)
            inventoryTracking = try c.decodeIfPresent(Bool.self, forKey: .inventoryTracking) ?? false
            heavyInventory = try c.decodeIfPresent(Bool.self, forKey: .heavyInventory) ?? false
            multiStateSales = try c.decodeIfPresent(Bool.self, forKey: .multiStateSales) ?? false
            cashHeavy = try c.decodeIfPresent(Bool.self, forKey: .cashHeavy) ?? false
            multipleEntities = try c.decodeIfPresent(Bool.self, forKey: .multipleEntities) ?? false
            advisory = try c.decodeIfPresent(Bool.self, forKey: .advisory) ?? false
        }

        /// Each ticked add-on as its published price-list item (2026-10-03: fixed prices
        /// from `PriceBook`, so a quote matches the website; they used to be hours × rate).
        /// "Payroll" here is payroll bookkeeping; running payroll is a separate price-list item.
        public var addOns: [ScopePreset] {
            var ids: [String] = []
            if advisory { ids.append("advisory") }
            ids += Array(repeating: "extra-account", count: max(0, extraAccounts))
            if salesTaxManagement { ids.append("sales-tax") }
            if payrollProcessing { ids.append("payroll-bookkeeping") }
            if multiStateSales { ids.append("multi-state") }
            if cashHeavy { ids.append("cash-heavy") }
            if inventoryTracking { ids.append("inventory") }
            if heavyInventory { ids.append("heavy-inventory") }
            if multipleEntities { ids.append("additional-entity") }
            return ids.map(PriceBook.item)
        }

        /// What to tell the bookkeeper before quoting.
        public var warnings: [String] {
            var w: [String] = []
            if heavyInventory { w.append("Heavy inventory: quote the top tier, require the point-of-sale system to post daily sales summaries to QuickBooks, and set a yearly physical count in the agreement. Decline if the client has no working point-of-sale system.") }
            if multiStateSales { w.append("Multi-state sales: watch each state's sales threshold on the Compliance Calendar; sales tax registration in other states is the client's and CPA's decision.") }
            if cashHeavy { w.append("Cash-heavy: require daily drawer reports and deposit slips; unexplained cash differences are a risk you report, not cover.") }
            if multipleEntities { w.append("Multiple entities: each entity is its own QuickBooks company and its own monthly fee; inter-company transfers need matching entries on both sides.") }
            if heavyInventory && cashHeavy { w.append("Both heavy inventory and cash-heavy: this is the profile that most often outgrows a flat fee. Consider declining or pricing it as a custom engagement.") }
            return w
        }
    }

    public struct MonthlyQuote: Sendable, Equatable {
        public let volumeTier: VolumeTier
        public let baseHours: Double
        public let hourlyRate: Money
        /// Base hours × rate, rounded to the nearest $50.
        public let baseAmount: Money
        /// Ticked add-ons at their published prices.
        public let addOns: [ScopePreset]
        public let addOnTotal: Money
        /// Base + add-ons: a clean, quotable number, not a false-precision one.
        public let monthlyInvestment: Money
    }

    /// The quote in one sentence, the same wherever it's shown or handed to the AI for a proposal draft.
    public static func retainerSentence(_ q: MonthlyQuote) -> String {
        var s = "Monthly retainer: \(q.volumeTier.label) transactions/month, \(String(format: "%.1f", q.baseHours)) hrs at \(q.hourlyRate.accountingDescription)/hr = \(q.baseAmount.accountingDescription)"
        if !q.addOns.isEmpty { s += ", plus " + q.addOns.map { "\($0.title) \($0.price.accountingDescription)" }.joined(separator: ", ") }
        return s + ". Total \(q.monthlyInvestment.accountingDescription)/mo."
    }

    public static func monthlyQuote(tier: VolumeTier, hourlyRate: Money, flags: MonthlyComplexityFlags) -> MonthlyQuote {
        let base = tier.monthlyBaseHours
        let baseAmount = roundToNearest50(hours: base, rate: hourlyRate)
        let addOns = flags.addOns
        let addOnTotal = Money(minorUnits: addOns.reduce(0) { $0 + $1.price.minorUnits }, currency: hourlyRate.currency)
        let investment = baseAmount + addOnTotal
        return MonthlyQuote(volumeTier: tier, baseHours: base, hourlyRate: hourlyRate, baseAmount: baseAmount, addOns: addOns, addOnTotal: addOnTotal, monthlyInvestment: investment)
    }

    public enum MonthsBehindTier: Int, CaseIterable, Identifiable, Sendable, Codable {
        case oneToThree, threeToSix, sixToTwelve, twelvePlus
        public var id: Int { rawValue }

        public var label: String {
            switch self {
            case .oneToThree: return "1–3 months"
            case .threeToSix: return "3–6 months"
            case .sixToTwelve: return "6–12 months"
            case .twelvePlus: return "12+ months"
            }
        }

        var baseMultiplier: Double {
            switch self {
            case .oneToThree: return 2.0
            case .threeToSix: return 4.5
            case .sixToTwelve: return 9.0
            case .twelvePlus: return 15.0
            }
        }
    }

    public struct CleanupIssueFlags: Sendable, Equatable, Codable {
        public var multipleUncategorized: Bool
        public var personalBusinessMixed: Bool
        public var payrollNotReconciled: Bool
        public var salesTaxNotFiled: Bool
        public var inventoryTrackingIssues: Bool
        public var negativeBalances: Bool
        public var duplicatedAccounts: Bool

        public init(
            multipleUncategorized: Bool = false,
            personalBusinessMixed: Bool = false,
            payrollNotReconciled: Bool = false,
            salesTaxNotFiled: Bool = false,
            inventoryTrackingIssues: Bool = false,
            negativeBalances: Bool = false,
            duplicatedAccounts: Bool = false
        ) {
            self.multipleUncategorized = multipleUncategorized
            self.personalBusinessMixed = personalBusinessMixed
            self.payrollNotReconciled = payrollNotReconciled
            self.salesTaxNotFiled = salesTaxNotFiled
            self.inventoryTrackingIssues = inventoryTrackingIssues
            self.negativeBalances = negativeBalances
            self.duplicatedAccounts = duplicatedAccounts
        }

        var activeCount: Int {
            [multipleUncategorized, personalBusinessMixed, payrollNotReconciled, salesTaxNotFiled, inventoryTrackingIssues, negativeBalances, duplicatedAccounts]
                .filter { $0 }.count
        }
    }

    public struct CleanupQuote: Sendable, Equatable {
        public let monthsBehind: MonthsBehindTier
        public let volumeTier: VolumeTier
        public let hourlyRate: Money
        public let issueCount: Int
        public let low: Money
        public let high: Money
        public let midpoint: Money
    }

    /// The low end is floored at the price list's smallest clean-up (`PriceBook.cleanupFloor`):
    /// a project smaller than that isn't really a clean-up project.
    private static var cleanupFloor: Money { PriceBook.cleanupFloor }

    public static func cleanupQuote(monthsBehind: MonthsBehindTier, volumeTier: VolumeTier, hourlyRate: Money, issues: CleanupIssueFlags) -> CleanupQuote {
        let complexityFactor = 1.0 + Double(issues.activeCount) * 0.15
        let effectiveHourlyRate = Money(
            minorUnits: Int64((Double(hourlyRate.minorUnits) * volumeTier.cleanupVolumeMultiplier * complexityFactor).rounded()),
            currency: hourlyRate.currency
        )
        let midpoint = roundToNearest50(hours: monthsBehind.baseMultiplier, rate: effectiveHourlyRate)
        let low = max(cleanupFloor, scale(midpoint, by: 0.8))
        let high = scale(midpoint, by: 1.2)
        return CleanupQuote(monthsBehind: monthsBehind, volumeTier: volumeTier, hourlyRate: hourlyRate, issueCount: issues.activeCount, low: low, high: high, midpoint: midpoint)
    }

    /// Owner directive (2026-08-31): "a combined output... Phase 1
    /// cleanup + Phase 2 retainer... total day-one investment." `cleanup`
    /// is `nil` when the client doesn't need one — `dayOneTotal` then
    /// equals just the first month's retainer, not a fabricated cleanup
    /// figure.
    public struct CombinedProposal: Sendable, Equatable {
        public let cleanup: CleanupQuote?
        public let monthly: MonthlyQuote

        public init(cleanup: CleanupQuote?, monthly: MonthlyQuote) {
            self.cleanup = cleanup
            self.monthly = monthly
        }

        public var dayOneTotal: Money {
            (cleanup?.midpoint ?? Money(minorUnits: 0, currency: monthly.monthlyInvestment.currency)) + monthly.monthlyInvestment
        }
    }

    private static func roundToNearest50(hours: Double, rate: Money) -> Money {
        let rawMinorUnits = hours * Double(rate.minorUnits)
        let nearest: Double = 5_000 // $50 in minor units
        let rounded = (rawMinorUnits / nearest).rounded() * nearest
        return Money(minorUnits: Int64(rounded), currency: rate.currency)
    }

    private static func scale(_ money: Money, by factor: Double) -> Money {
        Money(minorUnits: Int64((Double(money.minorUnits) * factor).rounded()), currency: money.currency)
    }
}
