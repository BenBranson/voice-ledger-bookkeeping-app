import Foundation

/// Which month the app reviews (2026-10-02). It used to be hard-coded to July
/// 2026, so no other month could be reviewed. The default is the last
/// COMPLETED month: on October 2 the books to close are September's.
public enum ReviewPeriod {
    public static func lastCompleted(today: AccountingDate) -> AccountingPeriod {
        AccountingPeriod(year: today.year, month: today.month).previousMonth
    }

    /// The months offered in the picker: the current month (in progress) and
    /// the `count - 1` completed months before it, newest first.
    public static func choices(today: AccountingDate, count: Int = 13) -> [AccountingPeriod] {
        var p = AccountingPeriod(year: today.year, month: today.month)
        var out: [AccountingPeriod] = []
        for _ in 0..<count { out.append(p); p = p.previousMonth }
        return out
    }

    /// "2026-09", the stored form.
    public static func key(_ p: AccountingPeriod) -> String { String(format: "%04d-%02d", p.year, p.month) }

    public static func parse(_ s: String?) -> AccountingPeriod? {
        guard let parts = s?.split(separator: "-"), parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]), (1...12).contains(m) else { return nil }
        return AccountingPeriod(year: y, month: m)
    }

    static let monthNames = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]

    /// A spoken month ("september", "aug", "september 2025") → the most recent
    /// such month that isn't in the future. nil if it isn't a month.
    public static func spoken(_ text: String, today: AccountingDate) -> AccountingPeriod? {
        let words = text.lowercased().split(separator: " ").map(String.init)
        guard let first = words.first,
              let index = monthNames.firstIndex(where: { $0 == first || ($0.hasPrefix(first) && first.count >= 3) }) else { return nil }
        let month = index + 1
        if words.count == 2, let y = Int(words[1]), (2000...2100).contains(y) { return AccountingPeriod(year: y, month: month) }
        guard words.count == 1 else { return nil }
        let year = month > today.month ? today.year - 1 : today.year
        return AccountingPeriod(year: year, month: month)
    }

    /// "September 2026".
    public static func label(_ p: AccountingPeriod) -> String { "\(monthNames[p.month - 1].capitalized) \(p.year)" }
}
