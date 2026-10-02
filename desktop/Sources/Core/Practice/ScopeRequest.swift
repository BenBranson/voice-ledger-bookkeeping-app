import Foundation

/// Owner directive 2026-10-02: an out-of-scope request log with preset
/// price buttons, so every "quick favor" gets a price before the work.
public enum ScopeBilling: String, Codable, Sendable, CaseIterable {
    case monthly, oneTime, perUnit
    public var suffix: String {
        switch self {
        case .monthly: return "/mo"
        case .oneTime: return " one-time"
        case .perUnit: return " each"
        }
    }
}

/// A price the bookkeeper sets once and clicks to add. Firm-wide.
public struct ScopePreset: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var title: String
    public var price: Money
    public var billing: ScopeBilling
    /// Singular unit for per-unit items ("hour", "form", "month").
    public var unit: String?
    /// Shown when the add-on is mostly data entry, which Texas can tax.
    public var taxNote: String?

    public init(id: String, title: String, price: Money, billing: ScopeBilling, unit: String? = nil, taxNote: String? = nil) {
        self.id = id
        self.title = title
        self.price = price
        self.billing = billing
        self.unit = unit
        self.taxNote = taxNote
    }

    public var priceLabel: String {
        "\(price.accountingDescription)\(billing == .perUnit ? " per \(unit ?? "unit")" : billing.suffix)"
    }

    static func usd(_ dollars: Int64) -> Money { Money(minorUnits: dollars * 100, currency: .usd) }

    /// Starting prices; the bookkeeper edits them in the app. Payroll $400/mo
    /// and the $150/hr out-of-scope rate follow the owner's practice guide.
    public static let defaults: [ScopePreset] = [
        ScopePreset(id: "payroll", title: "Payroll processing", price: usd(400), billing: .monthly,
                    taxNote: "Payroll data entry may be taxable data processing in Texas. Ask your CPA whether to collect sales tax on it."),
        ScopePreset(id: "advisory", title: "Advisory upgrade: 13-week forecast + monthly review call", price: usd(1_000), billing: .monthly),
        ScopePreset(id: "extra-account", title: "Additional bank or credit card account", price: usd(50), billing: .monthly),
        ScopePreset(id: "sales-tax", title: "Sales tax tracking and return prep", price: usd(100), billing: .monthly),
        ScopePreset(id: "class-tracking", title: "Class, location or job tracking", price: usd(150), billing: .monthly),
        ScopePreset(id: "custom-report", title: "Custom or rush report", price: usd(150), billing: .oneTime),
        ScopePreset(id: "catch-up-month", title: "Catch-up month (books behind)", price: usd(250), billing: .perUnit, unit: "month"),
        ScopePreset(id: "1099", title: "1099 preparation", price: usd(50), billing: .perUnit, unit: "form"),
        ScopePreset(id: "hourly", title: "Out-of-scope work (hourly)", price: usd(150), billing: .perUnit, unit: "hour"),
    ]
}

public struct ScopeRequest: Codable, Sendable, Equatable, Identifiable {
    public enum Status: String, Codable, Sendable, CaseIterable {
        case quoted, approved, declined, billed
        public var label: String { rawValue.capitalized }
    }

    public let id: String
    public let requestedAt: Date
    public var title: String
    public var unitPrice: Money
    public var quantity: Int
    public var billing: ScopeBilling
    public var unit: String?
    public var status: Status
    public var note: String

    public init(id: String = UUID().uuidString, requestedAt: Date = Date(), title: String, unitPrice: Money, quantity: Int = 1,
                billing: ScopeBilling, unit: String? = nil, status: Status = .quoted, note: String = "") {
        self.id = id
        self.requestedAt = requestedAt
        self.title = title
        self.unitPrice = unitPrice
        self.quantity = max(1, quantity)
        self.billing = billing
        self.unit = unit
        self.status = status
        self.note = note
    }

    public init(preset: ScopePreset, quantity: Int = 1) {
        self.init(title: preset.title, unitPrice: preset.price, quantity: quantity, billing: preset.billing, unit: preset.unit)
    }

    public var total: Money { Money(minorUnits: unitPrice.minorUnits * Int64(quantity), currency: unitPrice.currency) }

    public var priceText: String {
        switch billing {
        case .monthly: return "\(unitPrice.accountingDescription) a month"
        case .oneTime: return "\(unitPrice.accountingDescription), one time"
        case .perUnit:
            let u = unit ?? "unit"
            return quantity == 1 ? "\(unitPrice.accountingDescription) per \(u)" : "\(total.accountingDescription) (\(quantity) \(u)s at \(unitPrice.accountingDescription) each)"
        }
    }
}

public enum ScopeLog {
    public struct Totals: Sendable, Equatable {
        /// Approved or billed monthly add-ons: the new recurring amount.
        public let monthlyAddOns: Money
        /// Approved but not yet billed one-time and per-unit work.
        public let unbilledOneTime: Money
        /// Quoted, waiting on the client.
        public let awaitingApproval: Int
    }

    public static func totals(_ requests: [ScopeRequest]) -> Totals {
        func sum(_ r: [ScopeRequest]) -> Money { Money(minorUnits: r.reduce(0) { $0 + $1.total.minorUnits }, currency: .usd) }
        return Totals(monthlyAddOns: sum(requests.filter { $0.billing == .monthly && ($0.status == .approved || $0.status == .billed) }),
                      unbilledOneTime: sum(requests.filter { $0.billing != .monthly && $0.status == .approved }),
                      awaitingApproval: requests.filter { $0.status == .quoted }.count)
    }

    /// The reply to send the client: what the agreement covers, that the
    /// request is outside it, the price, and that work starts on approval.
    public static func clientReply(for request: ScopeRequest, clientName: String?) -> String {
        let greeting = clientName.map { "Hi \($0)," } ?? "Hi,"
        let what = request.title.prefix(1).lowercased() + request.title.dropFirst()
        let offer: String
        switch request.billing {
        case .monthly: offer = "I can add \(what) to your monthly package for \(request.priceText)."
        case .oneTime: offer = "I can take care of this for \(request.priceText)."
        case .perUnit: offer = "I can take care of this at \(request.priceText)."
        }
        return """
        \(greeting)

        Thanks for reaching out. Your current agreement covers monthly bookkeeping, reconciliation and reporting; \(what) is outside that scope. \(offer)

        Reply to approve and I'll start once I have your OK in writing.

        Benjamin Branson Bookkeeping
        """
    }
}
