import Foundation

/// Owner directive (2026-08-31): "search for a specific dollar amount and
/// it brings back all the transactions that are that amount... to pinpoint
/// matches or duplicates or miscategorized transactions."
///
/// **The "handle float rounding" concern this was asked to guard against
/// doesn't actually apply to this codebase** — `Money` (`Money.swift`) is
/// already integer minor units (cents), never a `Double`/`Float`, exactly
/// to make equality exact. `parseAmount` below keeps that guarantee at the
/// text-input boundary too: it parses the typed string digit-by-digit into
/// whole dollars and cents as integers, never through `Double(string)`,
/// so there's no floating-point representation step (and therefore no
/// rounding bug) anywhere between what the bookkeeper types and what gets
/// compared.
public enum AmountSearch {
    /// Accepts "142.50", "$142.50", "1,242.50", "142", "-45.00" — rejects
    /// anything with more than 2 digits after the decimal point (typing
    /// "142.5" is treated as $142.50, matching how a bookkeeper would read
    /// it, but "142.500" is rejected outright rather than silently
    /// truncated or rounded).
    public static func parseAmount(_ text: String, currency: CurrencyCode = .usd) -> Money? {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: "$", with: "")
        cleaned = cleaned.replacingOccurrences(of: ",", with: "")
        guard !cleaned.isEmpty else { return nil }

        let isNegative = cleaned.hasPrefix("-")
        if isNegative { cleaned.removeFirst() }
        guard !cleaned.isEmpty else { return nil }

        let parts = cleaned.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return nil }

        let wholeText = parts[0].isEmpty ? "0" : String(parts[0])
        guard wholeText.allSatisfy(\.isNumber), let whole = Int64(wholeText) else { return nil }

        var centsText = parts.count == 2 ? String(parts[1]) : ""
        guard centsText.count <= 2, centsText.allSatisfy(\.isNumber) else { return nil }
        while centsText.count < 2 { centsText += "0" }
        guard let cents = Int64(centsText) else { return nil }

        let minorUnits = whole * 100 + cents
        return Money(minorUnits: isNegative ? -minorUnits : minorUnits, currency: currency)
    }

    /// Matches on ABSOLUTE value, not signed value — a search for "142.50"
    /// also surfaces a -$142.50 credit/refund alongside a $142.50 charge,
    /// deliberately: a duplicate posting or a payment/refund pair worth
    /// comparing is exactly as likely to differ in sign as to match it, and
    /// the bookkeeper reviewing the results can already see each row's
    /// real sign. Only compares same-currency transactions — mixing
    /// currencies by raw minor-unit value would be a wrong answer, not a
    /// permissive one.
    public static func findTransactions(matching amount: Money, in transactions: [LedgerTransaction]) -> [LedgerTransaction] {
        transactions.filter { $0.totalAmount.currency == amount.currency && abs($0.totalAmount.minorUnits) == abs(amount.minorUnits) }
    }
}
