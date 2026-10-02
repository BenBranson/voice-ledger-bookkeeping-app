import Foundation

public struct ComplianceDeadline: Identifiable, Sendable, Equatable {
    public enum Responsible: String, Sendable { case client, bookkeeper, cpa }
    public var id: String { "\(key)-\(date.formatted)" }
    public let key: String
    public let date: AccountingDate
    public let title: String
    public let detail: String
    public let responsible: Responsible

    public init(key: String, date: AccountingDate, title: String, detail: String, responsible: Responsible) {
        self.key = key
        self.date = date
        self.title = title
        self.detail = detail
        self.responsible = responsible
    }
}

/// Every dated filing and delivery for one client, from its practice
/// profile. Dates and rules (owner directive 2026-10-02), each verified:
/// - Texas sales tax: monthly on the 20th of the next month; quarterly Apr
///   20 / Jul 20 / Oct 20 / Jan 20; yearly Jan 20 (Texas Comptroller).
/// - Texas franchise tax PIR/OIR or report: May 15 (Texas Comptroller).
/// - 1099-NEC and W-2: Jan 31. Form 941 and TWC quarterly wage report:
///   Apr 30 / Jul 31 / Oct 31 / Jan 31. Form 940: Jan 31.
/// - IFTA: Apr 30 / Jul 31 / Oct 31 / Jan 31. Form 2290: Aug 31.
/// A date on a weekend or US federal holiday moves to the next business day.
public enum ComplianceCalendar {
    public static func deadlines(for p: ClientPracticeProfile, from start: AccountingDate, days: Int = 120) -> [ComplianceDeadline] {
        let end = start.adding(days: days)
        var out: [ComplianceDeadline] = []
        func add(_ key: String, _ y: Int, _ m: Int, _ d: Int, _ title: String, _ detail: String, _ who: ComplianceDeadline.Responsible) {
            let date = nextBusinessDay(AccountingDate(year: y, month: m, day: min(d, daysIn(y, m))))
            if date >= start && date <= end { out.append(ComplianceDeadline(key: key, date: date, title: title, detail: detail, responsible: who)) }
        }
        for year in [start.year - 1, start.year, start.year + 1] {
            for month in 1...12 {
                let (ny, nm) = month == 12 ? (year + 1, 1) : (year, month + 1)
                // The firm's own monthly delivery and the client's statement deadline.
                add("statements", ny, nm, p.statementsDueDay, "Statements due from client", "Bank and card statements for \(monthName(month)) \(year), per the engagement agreement.", .client)
                let report = businessDay(p.reportBusinessDay, year: ny, month: nm)
                if report >= start && report <= end {
                    out.append(ComplianceDeadline(key: "close-package", date: report, title: "Month-end package due", detail: "Deliver \(monthName(month)) \(year) reports, per the engagement agreement.", responsible: .bookkeeper))
                }
                if p.salesTaxFrequency == .monthly {
                    add("sales-tax", ny, nm, 20, "Texas sales tax return", "Monthly return for \(monthName(month)) \(year).", .client)
                }
            }
            if p.salesTaxFrequency == .quarterly {
                add("sales-tax", year, 4, 20, "Texas sales tax return", "Quarterly return for January–March \(year).", .client)
                add("sales-tax", year, 7, 20, "Texas sales tax return", "Quarterly return for April–June \(year).", .client)
                add("sales-tax", year, 10, 20, "Texas sales tax return", "Quarterly return for July–September \(year).", .client)
                add("sales-tax", year + 1, 1, 20, "Texas sales tax return", "Quarterly return for October–December \(year).", .client)
            }
            if p.salesTaxFrequency == .yearly {
                add("sales-tax", year + 1, 1, 20, "Texas sales tax return", "Yearly return for \(year).", .client)
            }
            if p.texasEntity {
                add("franchise", year, 5, 15, "Texas franchise tax", "Public Information Report (or Ownership Information Report) for \(year), plus the franchise tax report if revenue is over the no tax due threshold. Due even when no tax is owed.", .cpa)
            }
            if p.files1099s {
                add("1099", year + 1, 1, 31, "1099-NEC forms", "File with the IRS and send to contractors paid $2,000 or more in \(year) ($600 for 2025 payments).", .cpa)
            }
            if p.hasEmployees {
                add("w2", year + 1, 1, 31, "W-2s and Form 940", "W-2s to employees and the IRS, and the annual federal unemployment return for \(year).", .client)
                for (q, (m, label)) in [(1, (4, "January–March")), (2, (7, "April–June")), (3, (10, "July–September"))] {
                    add("941-q\(q)", year, m, 30 + (m == 7 || m == 10 ? 1 : 0), "Form 941 and TWC wage report", "Quarterly payroll returns for \(label) \(year).", .client)
                }
                add("941-q4", year + 1, 1, 31, "Form 941 and TWC wage report", "Quarterly payroll returns for October–December \(year).", .client)
            }
            if p.filesIFTA {
                for (m, label) in [(4, "January–March"), (7, "April–June"), (10, "July–September")] {
                    add("ifta", year, m, m == 4 ? 30 : 31, "IFTA fuel tax return", "Quarterly miles and fuel by state for \(label) \(year).", .client)
                }
                add("ifta", year + 1, 1, 31, "IFTA fuel tax return", "Quarterly miles and fuel by state for October–December \(year).", .client)
            }
            if p.filesForm2290 {
                add("2290", year, 8, 31, "Form 2290 heavy vehicle use tax", "For trucks of 55,000 lb or more, tax year July \(year)–June \(year + 1).", .client)
            }
        }
        var seen = Set<String>()
        return out.filter { seen.insert($0.id).inserted }.sorted { $0.date < $1.date || ($0.date == $1.date && $0.title < $1.title) }
    }

    /// The Nth business day of a month (weekends and federal holidays skipped).
    public static func businessDay(_ n: Int, year: Int, month: Int) -> AccountingDate {
        var date = AccountingDate(year: year, month: month, day: 1)
        var count = 0
        while true {
            if isBusinessDay(date) { count += 1; if count >= max(1, n) { return date } }
            date = date.adding(days: 1)
        }
    }

    public static func nextBusinessDay(_ date: AccountingDate) -> AccountingDate {
        var d = date
        while !isBusinessDay(d) { d = d.adding(days: 1) }
        return d
    }

    public static func isBusinessDay(_ d: AccountingDate) -> Bool {
        let w = weekday(d)
        return w != 1 && w != 7 && !federalHolidays(d.year).contains(d)
    }

    /// 1 = Sunday ... 7 = Saturday.
    static func weekday(_ d: AccountingDate) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: DateComponents(year: d.year, month: d.month, day: d.day))!
        return cal.component(.weekday, from: date)
    }

    /// US federal holidays as observed (Saturday → Friday, Sunday → Monday).
    static func federalHolidays(_ y: Int) -> Set<AccountingDate> {
        func observed(_ m: Int, _ d: Int) -> AccountingDate {
            let date = AccountingDate(year: y, month: m, day: d)
            switch weekday(date) {
            case 7: return date.adding(days: -1)
            case 1: return date.adding(days: 1)
            default: return date
            }
        }
        func nth(_ n: Int, weekday target: Int, month m: Int) -> AccountingDate {
            var date = AccountingDate(year: y, month: m, day: 1)
            while weekday(date) != target { date = date.adding(days: 1) }
            return date.adding(days: 7 * (n - 1))
        }
        func last(weekday target: Int, month m: Int) -> AccountingDate {
            var date = AccountingDate(year: y, month: m, day: daysIn(y, m))
            while weekday(date) != target { date = date.adding(days: -1) }
            return date
        }
        return [observed(1, 1), nth(3, weekday: 2, month: 1), nth(3, weekday: 2, month: 2), last(weekday: 2, month: 5), observed(6, 19),
                observed(7, 4), nth(1, weekday: 2, month: 9), nth(2, weekday: 2, month: 10), observed(11, 11), nth(4, weekday: 5, month: 11), observed(12, 25)]
    }

    static func daysIn(_ y: Int, _ m: Int) -> Int { AccountingPeriod(year: y, month: m).daysInMonth }

    static func monthName(_ m: Int) -> String {
        ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"][m - 1]
    }
}
