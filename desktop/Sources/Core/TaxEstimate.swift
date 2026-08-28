import Foundation

/// docs/VOICE_LEDGER_SPEC.md Page 10 (Taxes, Type A): "locally estimates
/// trends and possible exposure from QBO financial data... Cannot:
/// determine actual liability, deductions, basis, outside income, or
/// filed-return status. Always labeled an estimate, never filing
/// guidance."
///
/// **This file contains ZERO tax law — no bracket, no rate, no
/// jurisdiction rule, no deduction logic, and it never will.** Per the
/// owner's explicit instruction (2026-08-28: "make sure all tax laws are
/// correct... adhering to that"), the only way this app can honestly
/// guarantee it never states an incorrect tax rule is to never encode a
/// tax rule at all. `estimatedSetAside` is pure multiplication —
/// `netIncome × a rate the user supplies` (typically one their own CPA
/// gave them) — never a rate this app knows, assumes, or looks up. If a
/// set-aside number is wrong, the cause is either QBO's own net income
/// figure or the rate the user typed in, never a tax rule inside this
/// codebase, because there is no tax rule inside this codebase.
public enum TaxEstimate {
    /// Finds QBO's own "Net Income" summary line — confirmed live
    /// 2026-08-27 against the real sandbox as a bare Summary-only Section
    /// (`"group": "NetIncome"`), going through the exact same `flatten()`
    /// path every other Summary row already does
    /// (`QBOSyncClient.flatten`). `nil` when the report hasn't loaded or
    /// genuinely carries no such line — never a guess, never `$0.00`.
    public static func netIncome(from profitAndLossLines: [ReportLine]) -> Money? {
        profitAndLossLines.first(where: { $0.isSummary && $0.label == "Net Income" })?.amount
    }

    /// `nil` for a missing/negative rate, or net income that's zero or a
    /// loss (a loss period has no meaningful "set aside" — showing `$0`
    /// would itself be a claim about tax liability this app cannot make;
    /// see this type's own doc comment on why it makes none at all).
    public static func estimatedSetAside(netIncome: Money?, ratePercent: Double?) -> Money? {
        guard let netIncome, let ratePercent, ratePercent >= 0, netIncome.minorUnits > 0 else { return nil }
        let cents = Double(netIncome.minorUnits) * (ratePercent / 100.0)
        return Money(minorUnits: Int64(cents.rounded()), currency: netIncome.currency)
    }
}

/// The rate `TaxEstimate.estimatedSetAside` multiplies by — a human's own
/// input, recorded not verified, same posture as every other attestation
/// in this codebase. `ratePercent` is deliberately never defaulted to a
/// nonzero value anywhere in this app; it starts `nil` and stays `nil`
/// until a person types one in.
public struct TaxEstimateSettings: Codable, Sendable, Equatable {
    public var ratePercent: Double?
    public var setBy: String?
    public var setAt: Date?
    public var note: String?

    public init(ratePercent: Double? = nil, setBy: String? = nil, setAt: Date? = nil, note: String? = nil) {
        self.ratePercent = ratePercent
        self.setBy = setBy
        self.setAt = setAt
        self.note = note
    }
}
