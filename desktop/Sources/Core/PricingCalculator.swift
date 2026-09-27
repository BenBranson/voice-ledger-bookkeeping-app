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
        public var multipleBankAccounts: Bool
        public var inventoryTracking: Bool

        public init(payrollProcessing: Bool = false, salesTaxManagement: Bool = false, multipleBankAccounts: Bool = false, inventoryTracking: Bool = false) {
            self.payrollProcessing = payrollProcessing
            self.salesTaxManagement = salesTaxManagement
            self.multipleBankAccounts = multipleBankAccounts
            self.inventoryTracking = inventoryTracking
        }

        var addOnHours: Double {
            var hours = 0.0
            if payrollProcessing { hours += 1.5 }
            if salesTaxManagement { hours += 1.0 }
            if multipleBankAccounts { hours += 1.0 }
            if inventoryTracking { hours += 2.0 }
            return hours
        }
    }

    public struct MonthlyQuote: Sendable, Equatable {
        public let volumeTier: VolumeTier
        public let baseHours: Double
        public let addOnHours: Double
        public let totalHours: Double
        public let hourlyRate: Money
        /// Rounded to the nearest $50 — a clean, quotable number, not a
        /// false-precision one.
        public let monthlyInvestment: Money
    }

    public static func monthlyQuote(tier: VolumeTier, hourlyRate: Money, flags: MonthlyComplexityFlags) -> MonthlyQuote {
        let base = tier.monthlyBaseHours
        let addOns = flags.addOnHours
        let total = base + addOns
        let investment = roundToNearest50(hours: total, rate: hourlyRate)
        return MonthlyQuote(volumeTier: tier, baseHours: base, addOnHours: addOns, totalHours: total, hourlyRate: hourlyRate, monthlyInvestment: investment)
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

    /// The low end is floored at $400 — a cleanup project small enough to
    /// price under that isn't really a cleanup project, per the same
    /// pricing floor already on record for this project's own $300–500
    /// range discussion.
    private static let cleanupFloor = Money(minorUnits: 40_000, currency: .usd)

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
