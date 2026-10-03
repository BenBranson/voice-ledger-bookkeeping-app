import Foundation

/// A single discovery-call intake record — the qualitative answers a
/// bookkeeper captures live on the call, plus the same `PricingCalculator`
/// inputs `PricingCalculatorView` exposes (so a saved intake reproduces
/// the exact quote given on the call, not just the notes around it).
///
/// Deliberately flat, all-`String` for every free-text answer (never an
/// enum/parsed type) — this is what a caller says in the moment, typed in
/// real time; forcing structure on it during a live call would slow the
/// bookkeeper down and risk losing what was actually said. The few fields
/// that DO drive `PricingCalculator` math (`volumeTier`, `monthsBehind`,
/// the boolean flags) are separate, deliberate choices the bookkeeper
/// makes alongside the free text, not parsed from it.
public struct ClientIntake: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var savedAt: Date

    // MARK: 1. Basic Business Context
    public var legalBusinessName: String
    public var entityType: String
    public var industry: String
    public var primaryRevenueSources: String
    public var yearsInBusiness: String

    // MARK: 2. The Financial Ecosystem
    public var accountingSoftware: String
    public var bankAccountCountAnswer: String
    public var creditCardCountAnswer: String
    public var monthlyTransactionCountAnswer: String

    // MARK: 3. Scope of Work & Boundaries
    public var booksUpToDateAnswer: String
    public var whoManagesARAP: String
    public var paymentProcessors: String

    // MARK: 4. Workflow & Communication
    public var pointOfContactName: String
    public var pointOfContactRole: String
    public var pointOfContactEmail: String
    public var pointOfContactPhone: String
    public var communicationPreference: String

    // MARK: 5. Goals & Reporting Needs
    public var frustrations: String
    public var desiredMetrics: String
    public var financialsUse: String

    // MARK: Pricing Calculator inputs — same fields `PricingCalculatorView`
    // exposes, captured here so a saved intake reproduces the exact quote.
    public var hourlyRateText: String
    public var volumeTier: PricingCalculator.VolumeTier
    public var monthlyFlags: PricingCalculator.MonthlyComplexityFlags
    public var needsCleanup: Bool
    public var monthsBehind: PricingCalculator.MonthsBehindTier
    public var cleanupIssues: PricingCalculator.CleanupIssueFlags

    /// CLAUDE.md rule 5's "green means verified, not merely absent" posture
    /// applied to a proposal email: this must never be silently on for a
    /// prospect whose books were never actually connected and synced.
    /// Defaults `true` (an "auto-included" checkbox, matching the owner's
    /// explicit instruction) precisely because most intakes at this stage
    /// have no findings to include at all (`openFindings` is empty for an
    /// unconnected prospect, so the section renders nothing regardless) —
    /// the one case this default matters is an EXISTING connected client
    /// re-doing intake, where leaving it on is correct. The UI's own label
    /// states the "only if connected" condition plainly rather than
    /// silently trusting the default.
    public var includeFindingsSummary: Bool

    public init(
        id: String = UUID().uuidString,
        savedAt: Date = Date(),
        legalBusinessName: String = "",
        entityType: String = "",
        industry: String = "",
        primaryRevenueSources: String = "",
        yearsInBusiness: String = "",
        accountingSoftware: String = "",
        bankAccountCountAnswer: String = "",
        creditCardCountAnswer: String = "",
        monthlyTransactionCountAnswer: String = "",
        booksUpToDateAnswer: String = "",
        whoManagesARAP: String = "",
        paymentProcessors: String = "",
        pointOfContactName: String = "",
        pointOfContactRole: String = "",
        pointOfContactEmail: String = "",
        pointOfContactPhone: String = "",
        communicationPreference: String = "",
        frustrations: String = "",
        desiredMetrics: String = "",
        financialsUse: String = "",
        hourlyRateText: String = "\(PriceBook.hourlyRate.minorUnits / 100)",
        volumeTier: PricingCalculator.VolumeTier = .light,
        monthlyFlags: PricingCalculator.MonthlyComplexityFlags = .init(),
        needsCleanup: Bool = false,
        monthsBehind: PricingCalculator.MonthsBehindTier = .threeToSix,
        cleanupIssues: PricingCalculator.CleanupIssueFlags = .init(),
        includeFindingsSummary: Bool = true
    ) {
        self.id = id
        self.savedAt = savedAt
        self.legalBusinessName = legalBusinessName
        self.entityType = entityType
        self.industry = industry
        self.primaryRevenueSources = primaryRevenueSources
        self.yearsInBusiness = yearsInBusiness
        self.accountingSoftware = accountingSoftware
        self.bankAccountCountAnswer = bankAccountCountAnswer
        self.creditCardCountAnswer = creditCardCountAnswer
        self.monthlyTransactionCountAnswer = monthlyTransactionCountAnswer
        self.booksUpToDateAnswer = booksUpToDateAnswer
        self.whoManagesARAP = whoManagesARAP
        self.paymentProcessors = paymentProcessors
        self.pointOfContactName = pointOfContactName
        self.pointOfContactRole = pointOfContactRole
        self.pointOfContactEmail = pointOfContactEmail
        self.pointOfContactPhone = pointOfContactPhone
        self.communicationPreference = communicationPreference
        self.frustrations = frustrations
        self.desiredMetrics = desiredMetrics
        self.financialsUse = financialsUse
        self.hourlyRateText = hourlyRateText
        self.volumeTier = volumeTier
        self.monthlyFlags = monthlyFlags
        self.needsCleanup = needsCleanup
        self.monthsBehind = monthsBehind
        self.cleanupIssues = cleanupIssues
        self.includeFindingsSummary = includeFindingsSummary
    }

    /// A reasonable display name for the roster list/filename — the legal
    /// business name when given, otherwise the contact's name, otherwise a
    /// dated placeholder so an in-progress intake is never unlabeled.
    public var displayName: String {
        if !legalBusinessName.trimmingCharacters(in: .whitespaces).isEmpty { return legalBusinessName }
        if !pointOfContactName.trimmingCharacters(in: .whitespaces).isEmpty { return pointOfContactName }
        return "New Prospect — \(DateFormatter.intakeDisplay.string(from: savedAt))"
    }

    public var hourlyRate: Money {
        let dollars = Double(hourlyRateText.trimmingCharacters(in: .whitespaces)) ?? 0
        return Money(minorUnits: Int64((dollars * 100).rounded()), currency: .usd)
    }

    public var monthlyQuote: PricingCalculator.MonthlyQuote {
        PricingCalculator.monthlyQuote(tier: volumeTier, hourlyRate: hourlyRate, flags: monthlyFlags)
    }

    public var cleanupQuote: PricingCalculator.CleanupQuote {
        PricingCalculator.cleanupQuote(monthsBehind: monthsBehind, volumeTier: volumeTier, hourlyRate: hourlyRate, issues: cleanupIssues)
    }

    public var combinedProposal: PricingCalculator.CombinedProposal {
        .init(cleanup: needsCleanup ? cleanupQuote : nil, monthly: monthlyQuote)
    }
}

private extension DateFormatter {
    static let intakeDisplay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
