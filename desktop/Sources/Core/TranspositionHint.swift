import Foundation

/// Swapping two adjacent digits always changes an amount by a multiple of
/// 9, so a difference divisible by 9 is CONSISTENT with a transposition —
/// a lead to check first, never proof (one in nine random differences is
/// divisible by 9 too).
public enum TranspositionHint {
    public static func isConsistentWithTransposition(_ difference: Money) -> Bool {
        difference.minorUnits != 0 && difference.minorUnits % 9 == 0
    }

    public static func sentence(for difference: Money) -> String? {
        guard isConsistentWithTransposition(difference) else { return nil }
        return "The \(difference) difference is evenly divisible by 9, which is the signature of two swapped digits (e.g. $54 keyed as $45) — check for a transposed amount first."
    }

    public static func appending(to narrative: String, difference: Money) -> String {
        sentence(for: difference).map { "\(narrative) \($0)" } ?? narrative
    }
}
