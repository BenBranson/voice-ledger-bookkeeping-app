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

/// Something the calendar can't date honestly yet: an unchecked state rule,
/// a missing formation month, a per-entity date to look up.
public struct ComplianceCheck: Identifiable, Sendable, Equatable {
    public var id: String { title }
    public let title: String
    public let detail: String
}

/// Every dated filing and delivery for one client, from its practice
/// profile and its state's checked rules (`StateComplianceRules`).
/// - Federal: 1099-NEC, W-2/W-3 and 940 Jan 31; Form 941 Apr 30 / Jul 31 /
///   Oct 31 / Jan 31; business returns by entity type (1065 and 1120-S Mar
///   15, 1120 and Schedule C Apr 15) and estimated taxes; IFTA quarterly;
///   Form 2290 Aug 31.
/// - State: sales tax and annual reports only for checked states; any
///   unchecked rule becomes a `ComplianceCheck`, never a guessed date.
/// Dates on a weekend or US federal holiday move to the next business day.
public enum ComplianceCalendar {
    public static func deadlines(for p: ClientPracticeProfile, from start: AccountingDate, days: Int = 120) -> [ComplianceDeadline] {
        let end = start.adding(days: days)
        let rule = StateComplianceRules.rule(for: p.state)
        var out: [ComplianceDeadline] = []
        func add(_ key: String, _ y: Int, _ m: Int, _ d: Int, _ title: String, _ detail: String, _ who: ComplianceDeadline.Responsible) {
            let day = d == 0 ? daysIn(y, m) : min(d, daysIn(y, m))
            let date = nextBusinessDay(AccountingDate(year: y, month: m, day: day))
            if date >= start && date <= end { out.append(ComplianceDeadline(key: key, date: date, title: title, detail: detail, responsible: who)) }
        }
        func next(_ y: Int, _ m: Int) -> (Int, Int) { m == 12 ? (y + 1, 1) : (y, m + 1) }
        let salesTitle = "\(rule.name) sales tax return"

        for year in [start.year - 1, start.year, start.year + 1] {
            for month in 1...12 {
                let (ny, nm) = next(year, month)
                add("statements", ny, nm, p.statementsDueDay, "Statements due from client", "Bank and card statements for \(monthName(month)) \(year), per the engagement agreement.", .client)
                let report = businessDay(p.reportBusinessDay, year: ny, month: nm)
                if report >= start && report <= end {
                    out.append(ComplianceDeadline(key: "close-package", date: report, title: "Month-end package due", detail: "Deliver \(monthName(month)) \(year) reports, per the engagement agreement.", responsible: .bookkeeper))
                }
                if p.salesTaxFrequency == .monthly, let st = rule.salesTax, let d = st.monthlyDay {
                    add("sales-tax", ny, nm, d, salesTitle, "Monthly return for \(monthName(month)) \(year) (\(st.agency)).", .client)
                }
            }

            // Sales tax, non-monthly schedules.
            if let st = rule.salesTax {
                if p.salesTaxFrequency == .quarterly, let d = st.quarterlyDay {
                    for qEnd in st.quarterEndMonths {
                        let (dy, dm) = next(year, qEnd)
                        let firstMonth = ((qEnd + 9) % 12) + 1
                        add("sales-tax", dy, dm, d, salesTitle, "Quarterly return for \(monthName(firstMonth))–\(monthName(qEnd)) (\(st.agency)).", .client)
                    }
                }
                if p.salesTaxFrequency == .semiannual, let semi = st.semiannual, semi.count == 2 {
                    add("sales-tax", year, semi[0].0, semi[0].1, salesTitle, "Return for January–June \(year) (\(st.agency)).", .client)
                    let secondYear = semi[1].0 < 7 ? year + 1 : year
                    add("sales-tax", secondYear, semi[1].0, semi[1].1, salesTitle, "Return for July–December \(year) (\(st.agency)).", .client)
                }
                if p.salesTaxFrequency == .yearly, let y = st.yearly {
                    add("sales-tax", year + 1, y.0, y.1, salesTitle, "Yearly return for \(year) (\(st.agency)).", .client)
                }
                if p.salesTaxFrequency != .none, let all = st.allFilersAnnual {
                    add("sales-tax-annual", year + 1, all.0, all.1, "\(rule.name) annual sales and use tax return", "Every filer's annual return for \(year) (\(st.agency)).", .client)
                }
            }

            // State annual report.
            if p.entityType.isRegisteredEntity, let report = annualReportRule(p, rule) {
                let title = "\(rule.name) \(rule.annualReportName.lowercased())"
                switch report {
                case .fixed(let m, let d):
                    add("annual-report", year, m, d, title, "Keeps the \(p.entityType.label.lowercased()) in good standing with the state.", .client)
                case .endOfAnniversaryMonth:
                    if let fm = p.formationMonth { add("annual-report", year, fm, 0, title, "Due by the end of the month the business was formed.", .client) }
                case .beforeAnniversaryMonth:
                    if let fm = p.formationMonth {
                        let (py, pm) = fm == 1 ? (year - 1, 12) : (year, fm - 1)
                        add("annual-report", py, pm, 0, title, "Due before the first day of the month the business was formed.", .client)
                    }
                case .biennialEndOfAnniversaryMonth:
                    if let fm = p.formationMonth {
                        let onYear = p.formationYear.map { (year - $0) % 2 == 0 && year > $0 } ?? true
                        if onYear { add("annual-report", year, fm, 0, title, p.formationYear == nil ? "Every two years in the formation month; add the formation year to show only the right years." : "Every two years, by the end of the formation month.", .client) }
                    }
                case .endOfSecondMonthAfterAnniversary:
                    if let fm = p.formationMonth {
                        var (y2, m2) = (year, fm)
                        for _ in 0..<2 { (y2, m2) = next(y2, m2) }
                        add("annual-report", y2, m2, 0, title, "Due by the end of the second month after the formation month.", .client)
                    }
                case .none, .lookUp:
                    break
                }
            }
            for extra in rule.extraFilings where p.entityType.isRegisteredEntity && (!extra.llcOnly || isLLC(p.entityType)) {
                add(extra.key, year, extra.month, extra.day, extra.title, extra.detail, .cpa)
            }

            // Federal business return and estimated taxes (the CPA's job).
            switch p.entityType {
            case .partnership, .multiMemberLLC:
                add("federal-return", year, 3, 15, "Form 1065 partnership return", "Federal return for \(year - 1); K-1s to partners. Multi-member LLCs file this unless they elected corporate tax.", .cpa)
            case .sCorporation:
                add("federal-return", year, 3, 15, "Form 1120-S S corporation return", "Federal return for \(year - 1); K-1s to shareholders.", .cpa)
            case .cCorporation:
                add("federal-return", year, 4, 15, "Form 1120 corporation return", "Federal return for \(year - 1) (calendar year).", .cpa)
            case .soleProprietor, .singleMemberLLC:
                add("federal-return", year, 4, 15, "Owner's return with Schedule C", "The business is reported on the owner's Form 1040 for \(year - 1).", .cpa)
            }
            let estimated: [(Int, Int, Int)] = p.entityType == .cCorporation
                ? [(year, 4, 15), (year, 6, 15), (year, 9, 15), (year, 12, 15)]
                : [(year, 4, 15), (year, 6, 15), (year, 9, 15), (year + 1, 1, 15)]
            for (i, e) in estimated.enumerated() {
                add("estimated-tax", e.0, e.1, e.2, "Estimated tax payment \(i + 1) of 4", p.entityType == .cCorporation ? "Corporation estimated tax for \(year)." : "Owner's federal estimated tax for \(year).", .cpa)
            }

            if p.files1099s {
                add("1099", year + 1, 1, 31, "1099-NEC forms", "File with the IRS and send to contractors paid $2,000 or more in \(year) ($600 for 2025 payments).", .cpa)
            }
            if p.hasEmployees {
                add("w2", year + 1, 1, 31, "W-2s and Form 940", "W-2s to employees and the IRS, and the annual federal unemployment return for \(year).", .client)
                let quarterLabel = ["January–March", "April–June", "July–September", "October–December"]
                let dues: [(Int, Int, Int)] = [(year, 4, 30), (year, 7, 31), (year, 10, 31), (year + 1, 1, 31)]
                for (q, due) in dues.enumerated() {
                    let stateReport = p.state.uppercased() == "TX" ? " and TWC wage report" : ""
                    add("941-q\(q + 1)", due.0, due.1, due.2, "Form 941\(stateReport)", "Quarterly payroll return for \(quarterLabel[q]) \(year).", .client)
                }
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

    /// What the calendar can't date for this client yet, and why.
    public static func checks(for p: ClientPracticeProfile) -> [ComplianceCheck] {
        let rule = StateComplianceRules.rule(for: p.state)
        var out: [ComplianceCheck] = []
        if !rule.verified {
            out.append(ComplianceCheck(title: "\(rule.name) rules not checked yet",
                detail: "Voice Ledger has checked \(StateComplianceRules.verifiedStates.count) states so far. Verify \(rule.name)'s sales tax due dates, annual report and payroll filings on the state's own websites; federal dates below are complete."))
        }
        if p.salesTaxFrequency != .none {
            if !rule.hasStatewideSalesTax {
                out.append(ComplianceCheck(title: "\(rule.name) has no statewide sales tax", detail: "Check whether any local sales tax applies to this client."))
            } else if let st = rule.salesTax {
                let supported: Bool
                switch p.salesTaxFrequency {
                case .monthly: supported = st.monthlyDay != nil
                case .quarterly: supported = st.quarterlyDay != nil
                case .semiannual: supported = st.semiannual != nil
                case .yearly: supported = st.yearly != nil
                case .none: supported = true
                }
                if !supported {
                    out.append(ComplianceCheck(title: "\(p.salesTaxFrequency.label) sales tax in \(rule.name)", detail: "That schedule isn't in the checked \(rule.name) rules. Confirm the filing frequency on the state's notice and its due date."))
                }
            }
        }
        if p.entityType.isRegisteredEntity, rule.verified {
            switch annualReportRule(p, rule) {
            case nil:
                out.append(ComplianceCheck(title: "\(rule.name) report for \(p.entityType.label.lowercased())s", detail: "Only the LLC rule was checked for \(rule.name). Look up the corporation's annual report date with the Secretary of State."))
            case .lookUp?:
                out.append(ComplianceCheck(title: "\(rule.name) annual report date", detail: "Each \(rule.name) corporation has its own annual report date; find it on the corporation's record with the state."))
            case .endOfAnniversaryMonth?, .beforeAnniversaryMonth?, .biennialEndOfAnniversaryMonth?, .endOfSecondMonthAfterAnniversary?:
                if p.formationMonth == nil {
                    out.append(ComplianceCheck(title: "Add the formation month", detail: "\(rule.name)'s \(rule.annualReportName.lowercased()) is due based on the month the business was formed."))
                }
            default: break
            }
        }
        if p.hasEmployees && p.state.uppercased() != "TX" {
            out.append(ComplianceCheck(title: "\(rule.name) payroll filings", detail: "State unemployment wage reports\(rule.hasStateIncomeTax ? " and state income tax withholding returns" : "") are usually filed by the payroll provider. Confirm who files them and the due dates."))
        }
        if p.entityType.isRegisteredEntity && rule.hasStateIncomeTax && rule.verified {
            out.append(ComplianceCheck(title: "\(rule.name) business income tax return", detail: "Most states follow the federal due date; the CPA files it."))
        }
        for note in rule.notes { out.append(ComplianceCheck(title: "\(rule.name) note", detail: note)) }
        return out
    }

    static func annualReportRule(_ p: ClientPracticeProfile, _ rule: StateRule) -> StateRule.AnnualReport? {
        p.entityType.isCorporation ? rule.corporationReport : rule.annualReport
    }

    static func isLLC(_ e: ClientPracticeProfile.EntityType) -> Bool { e == .singleMemberLLC || e == .multiMemberLLC }

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
