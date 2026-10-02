import Foundation

/// A pop-up card Moneypenny shows next to her spoken answer (owner
/// directive 2026-10-02: "more instances where cards pull up", with charts,
/// QBO links, how to deal with a discrepancy, and a recommendation).
/// Everything in it is computed by Core from the client's books; the
/// recommendations are fixed wording chosen by deterministic rules, never
/// model output (CLAUDE.md rule 1).
public struct InsightCard: Equatable, Sendable {
    public let title: String
    public let subtitle: String
    /// The one figure that answers the question, e.g. "$17,176.93".
    public let headline: String?
    /// The card's main QuickBooks record (an account register), if any.
    public let headerLink: QBOTarget?
    public let chart: InsightChartData?
    public let rows: [InsightRow]
    public let recommendations: [String]
    /// Scope and freshness ("July 2026, synced 5 minutes ago").
    public let footnote: String

    public init(title: String, subtitle: String, headline: String? = nil, headerLink: QBOTarget? = nil, chart: InsightChartData? = nil, rows: [InsightRow] = [], recommendations: [String] = [], footnote: String) {
        self.title = title
        self.subtitle = subtitle
        self.headline = headline
        self.headerLink = headerLink
        self.chart = chart
        self.rows = rows
        self.recommendations = recommendations
        self.footnote = footnote
    }
}

public struct InsightRow: Equatable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let detail: String
    public let amountText: String
    public let link: QBOTarget?
    /// Shown in the warning color (overdue, negative, over a threshold).
    public let warn: Bool

    public init(id: String, label: String, detail: String = "", amountText: String = "", link: QBOTarget? = nil, warn: Bool = false) {
        self.id = id
        self.label = label
        self.detail = detail
        self.amountText = amountText
        self.link = link
        self.warn = warn
    }
}

/// The exact QuickBooks record a card row opens (never a general page).
public enum QBOTarget: Equatable, Sendable {
    case finding(String)
    case account(String)
    case vendor(id: String?, name: String)
    case customer(id: String?, name: String)
    case transaction(id: String, kind: QBOEntityKind)
}

/// Data for the shared `insightChart` ECharts builder (vl-charts.js).
public struct InsightChartData: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case bar, stackedBar, hbar, hstackedBar, line }
    public struct Series: Codable, Equatable, Sendable {
        public let name: String
        public let values: [Double?]
        public let valueTexts: [String]
        public init(name: String, values: [Double?], valueTexts: [String]) {
            self.name = name
            self.values = values
            self.valueTexts = valueTexts
        }
    }
    public let type: Kind
    public let categories: [String]
    public let series: [Series]
    public let ids: [String]
    public let markZero: Bool

    public init(type: Kind, categories: [String], series: [Series], ids: [String]? = nil, markZero: Bool = false) {
        self.type = type
        self.categories = categories
        self.series = series
        self.ids = ids ?? categories
        self.markZero = markZero
    }

    /// One series of money amounts.
    public static func money(_ type: Kind, _ pairs: [(String, Money)], name: String = "Amount", markZero: Bool = false) -> InsightChartData {
        InsightChartData(type: type, categories: pairs.map(\.0),
                         series: [Series(name: name, values: pairs.map { $0.1.majorUnitsDouble }, valueTexts: pairs.map { $0.1.accountingDescription })],
                         markZero: markZero)
    }
}
