import Foundation

/// Exact money. Integer minor units; no floating point anywhere in this type.
///
/// docs/phase-0/04_DATA_MODEL.md §4.3, decision M1: `Decimal` would also work,
/// but a fixed integer representation makes equality, hashing, and cross-foot
/// arithmetic exact and makes serialization unambiguous. Duplicate detection
/// (docs/phase-0/11_VERTICAL_SLICE.md) is an equality test on amounts;
/// floating point would make that subtly wrong.
public struct Money: Hashable, Codable, Sendable {
    public let minorUnits: Int64
    public let currency: CurrencyCode

    public init(minorUnits: Int64, currency: CurrencyCode) {
        self.minorUnits = minorUnits
        self.currency = currency
    }
}

public struct CurrencyCode: Hashable, Codable, Sendable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let usd = CurrencyCode(rawValue: "USD")
}

extension Money: Comparable {
    /// Comparing across currencies is a programmer error, not a silent
    /// coercion — there is no sensible ordering between USD and EUR minor
    /// units. Trapping here is preferable to a wrong answer computed quietly.
    public static func < (lhs: Money, rhs: Money) -> Bool {
        precondition(
            lhs.currency == rhs.currency,
            "Money comparison across currencies (\(lhs.currency.rawValue) vs \(rhs.currency.rawValue)) is not defined."
        )
        return lhs.minorUnits < rhs.minorUnits
    }
}

extension Money: AdditiveArithmetic {
    public static var zero: Money { Money(minorUnits: 0, currency: .usd) }

    public static func + (lhs: Money, rhs: Money) -> Money {
        precondition(lhs.currency == rhs.currency, "Cannot add Money across currencies.")
        return Money(minorUnits: lhs.minorUnits + rhs.minorUnits, currency: lhs.currency)
    }

    public static func - (lhs: Money, rhs: Money) -> Money {
        precondition(lhs.currency == rhs.currency, "Cannot subtract Money across currencies.")
        return Money(minorUnits: lhs.minorUnits - rhs.minorUnits, currency: lhs.currency)
    }
}

extension Money: CustomStringConvertible {
    /// A minimal, locale-naive rendering good enough for logs and CLI output.
    /// Real UI presentation belongs to a later, UI-approved step.
    public var description: String {
        let sign = minorUnits < 0 ? "-" : ""
        let absUnits = abs(minorUnits)
        let whole = absUnits / 100
        let fraction = absUnits % 100
        return "\(sign)\(currency.rawValue) \(whole).\(String(format: "%02d", fraction))"
    }
}
