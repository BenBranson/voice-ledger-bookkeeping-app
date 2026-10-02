import Foundation

/// The Charts & Cards page's list (owner directive 2026-10-02: "a whole list
/// of clickable commands that also state what it shows and I can click on
/// them and it instantly pulls up the corresponding chart"). Each entry's
/// `phrase` is a real voice command; a test proves every one routes, so
/// clicking and saying it always do the same thing.
public enum CardCatalog {
    public struct Item: Identifiable, Sendable, Equatable {
        public var id: String { phrase }
        public let title: String
        public let shows: String
        public let phrase: String
        public let symbol: String
    }

    public struct Section: Identifiable, Sendable, Equatable {
        public var id: String { title }
        public let title: String
        public let items: [Item]
    }

    static func i(_ t: String, _ s: String, _ p: String, _ sym: String) -> Item { Item(title: t, shows: s, phrase: p, symbol: sym) }

    public static let sections: [Section] = [
        Section(title: "Money in and out", items: [
            i("Who owes us", "Customers by amount owed, split into current, 1–60 days and over 60 days, with what to do about late balances and credits.", "who owes us", "person.2"),
            i("What we owe", "Vendors by open bill amount and age, with what to check on old bills and vendor credits.", "what do we owe", "building.2"),
            i("Cash outlook", "Projected ending cash for each of the next 13 weeks, the lowest week, and what to do if it goes below zero.", "will we run out of cash", "chart.line.downtrend.xyaxis"),
            i("Spend by vendor", "This month's largest vendors (expenses and bills), with a link to each vendor in QuickBooks.", "top vendors", "cart"),
        ]),
        Section(title: "Results", items: [
            i("Revenue by month", "Revenue for the last 12 months, compared with the month you're reviewing.", "revenue by month", "chart.bar"),
            i("Net income by month", "Profit or loss for the last 12 months, with loss months flagged.", "net income by month", "chart.bar.xaxis"),
            i("Expense categories", "This month's largest expense categories.", "expense chart", "chart.pie"),
            i("Income vs expenses", "Revenue down to net income, step by step.", "income vs expenses chart", "chart.bar.doc.horizontal"),
            i("Biggest cost drivers", "Expense categories ranked, with their running share of the total.", "cost drivers chart", "list.number"),
            i("Financial health", "Working capital, current and quick ratios, margins — with what they mean.", "working capital", "heart.text.square"),
        ]),
        Section(title: "Problems to fix", items: [
            i("Duplicates", "Possible duplicate transactions, largest first, each with its QuickBooks link and the fix.", "pull up the duplicates", "doc.on.doc"),
            i("Negative balances", "Accounts on the wrong side (overdrawn banks, overpaid liabilities) with how to trace them.", "negative balances", "minus.circle"),
            i("Balance sheet issues", "Suspense, clearing, Undeposited Funds and Opening Balance Equity items that should be zero.", "balance sheet issues", "exclamationmark.triangle"),
            i("Uncategorized and miscoded", "Transactions in catch-all accounts or coded to the wrong account.", "uncategorized", "questionmark.folder"),
            i("Personal expenses", "Charges that look personal, to confirm with the client.", "personal expenses", "person.crop.circle.badge.exclamationmark"),
            i("Vendor price increases", "Vendors charging noticeably more than their usual amount.", "price increases", "arrow.up.right"),
            i("Everything open", "Every open finding, largest first.", "all findings", "tray.full"),
        ]),
        Section(title: "Deadlines and changes", items: [
            i("What's due", "The next filings and deliveries for this client, from the Compliance Calendar.", "what's due", "calendar"),
            i("New accounts", "Bank, card or loan accounts that appeared in QuickBooks since an earlier sync.", "any new accounts", "plus.rectangle.on.rectangle"),
        ]),
    ]

    /// For the two cards that need a name: "find <name>" and "balance of <name>".
    public static func vendorPhrase(_ name: String) -> String { "find \(name)" }
    public static func accountPhrase(_ name: String) -> String { "balance of \(name)" }
}
