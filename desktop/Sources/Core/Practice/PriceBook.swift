import Foundation

/// The one price list (owner-approved 2026-10-03, after a market review: senior
/// bookkeeping band, Texas basic $300–$700/mo, trades $700–$2,000/mo, bookkeeping +
/// advisory $600–$1,200/mo). The pricing calculator, the scope-request price buttons,
/// the engagement agreement and the website all use these numbers. Before this there
/// were two lists that disagreed (payroll +$150 vs $400, an extra account +$100 vs $50).
public enum PriceBook {
    static func usd(_ dollars: Int64) -> Money { Money(minorUnits: dollars * 100, currency: .usd) }

    /// The standard rate the monthly tiers are built from (hours × rate):
    /// 3 / 5.5 / 8 hours → $400 / $700 / $1,000 a month.
    public static let hourlyRate = usd(125)
    /// Work outside a signed agreement, only with the client's written approval.
    /// Higher than the standard rate on purpose: extras cost more than in-scope work.
    public static let outOfScopeHourly = usd(150)
    /// Founding clients: Starter at this price for `foundingMonths`, in exchange for
    /// feedback and a testimonial.
    public static let foundingStarter = usd(300)
    public static let foundingMonths = 12
    /// Smallest clean-up project quoted.
    public static let cleanupFloor = usd(500)

    /// Every extra service with its published price. Ids are stable: saved scope
    /// requests and the calculator's add-on flags refer to them.
    public static let items: [ScopePreset] = [
        ScopePreset(id: "advisory", title: "Advisory: Business Diagnosis, 13-week cash forecast + monthly review call", price: usd(400), billing: .monthly),
        ScopePreset(id: "extra-account", title: "Additional bank or credit card account", price: usd(50), billing: .monthly),
        ScopePreset(id: "class-tracking", title: "Class, location or job tracking", price: usd(150), billing: .monthly),
        ScopePreset(id: "sales-tax", title: "Sales tax tracking and return prep", price: usd(150), billing: .monthly),
        ScopePreset(id: "payroll-bookkeeping", title: "Payroll bookkeeping (recording your provider's payroll, up to 10 employees)", price: usd(200), billing: .monthly),
        ScopePreset(id: "payroll", title: "Payroll processing (running payroll for you)", price: usd(400), billing: .monthly,
                    taxNote: "Payroll data entry may be taxable data processing in Texas. Ask your CPA whether to collect sales tax on it."),
        ScopePreset(id: "multi-state", title: "Multi-state sales", price: usd(200), billing: .monthly),
        ScopePreset(id: "cash-heavy", title: "Cash-heavy business", price: usd(200), billing: .monthly),
        ScopePreset(id: "inventory", title: "Inventory tracking", price: usd(250), billing: .monthly),
        ScopePreset(id: "heavy-inventory", title: "Heavy inventory (retail, grocery): from this price, quoted individually", price: usd(500), billing: .monthly),
        ScopePreset(id: "additional-entity", title: "Additional entity (separate books)", price: usd(250), billing: .monthly),
        ScopePreset(id: "catch-up-month", title: "Catch-up month (books behind)", price: usd(300), billing: .perUnit, unit: "month"),
        ScopePreset(id: "custom-report", title: "Custom or rush report", price: usd(150), billing: .oneTime),
        ScopePreset(id: "1099", title: "1099 preparation", price: usd(50), billing: .perUnit, unit: "form"),
        ScopePreset(id: "hourly", title: "Out-of-scope work (hourly, with written approval)", price: outOfScopeHourly, billing: .perUnit, unit: "hour"),
    ]

    /// "+$200/mo" — the price as a screen shows it beside a checkbox.
    public static func addOnPrice(_ id: String) -> String {
        let i = item(id)
        let dollars = i.price.minorUnits % 100 == 0 ? "$\(i.price.minorUnits / 100)" : i.price.accountingDescription
        return "+\(dollars)\(i.billing == .perUnit ? " per \(i.unit ?? "unit")" : i.billing.suffix)"
    }

    /// "$400" — whole-dollar money for labels.
    public static func dollars(_ m: Money) -> String {
        m.minorUnits % 100 == 0 ? "$\(m.minorUnits / 100)" : m.accountingDescription
    }

    public static func item(_ id: String) -> ScopePreset {
        guard let found = items.first(where: { $0.id == id }) else { preconditionFailure("PriceBook has no item \(id)") }
        return found
    }
}
