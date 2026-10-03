import Foundation

/// "From sales to profit": the revenue-to-net-income bridge as a plain list
/// (owner, 2026-10-03: the floating-bar waterfall was hard to read). Each row
/// is one QuickBooks section total with a minus or plus sign and a bar sized
/// against the largest row. Same wording as the PDF report's list.
public struct MoneyStep: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable { case moneyIn, moneyOut, profit, loss }
    public let id: String
    public let name: String
    /// "+$15,522.48", "-$12,768.12", "$2,483.11"; never accounting brackets.
    public let amountText: String
    /// Bar length, 0...1, relative to the largest row.
    public let barFraction: Double
    public let kind: Kind
    /// Plain explanation when a row behaves unexpectedly (a cost line that added money).
    public let hint: String?
}

public struct MoneyStepList: Equatable, Sendable {
    public let steps: [MoneyStep]
    /// "Out of every $1 in sales, 16¢ was left over as profit."
    public let perDollarSentence: String?
    /// "Each line is a QuickBooks total, and they add up exactly to the result." or why not.
    public let tieNote: String
}

public extension ChartData {
    static let moneyStepNames: [String: String] = [
        "revenue": "Money in (sales)", "cogs": "Cost of goods sold", "expenses": "Costs of running the business",
        "other-income": "Other income", "other-expenses": "Other costs (interest, fees)",
        "adjustment": "Bookkeeping adjustment (under review)",
    ]

    static func moneySteps(from lines: [ReportLine]) -> MoneyStepList? {
        waterfall(from: lines).map(moneySteps)
    }

    static func moneySteps(_ w: WaterfallData) -> MoneyStepList {
        func cents(_ d: Double) -> Int64 { Int64((d * 100).rounded()) }
        func text(_ c: Int64, sign: String) -> String {
            sign + Money(minorUnits: abs(c), currency: .usd).accountingDescription
        }
        let amounts = w.steps.map { abs(cents($0.to) - cents($0.from)) }
        let largest = max(amounts.max() ?? 1, 1)
        var steps: [MoneyStep] = []
        for (i, s) in w.steps.enumerated() {
            let isFirst = i == 0, isLast = i == w.steps.count - 1
            let amount = amounts[i]
            let fraction = Double(amount) / Double(largest)
            if isLast {
                let net = cents(s.to)
                steps.append(MoneyStep(id: s.id, name: net < 0 ? "Money lost this month" : "Money left over (profit)",
                                       amountText: text(net, sign: net < 0 ? "-" : ""), barFraction: fraction, kind: net < 0 ? .loss : .profit, hint: nil))
            } else {
                let adds = isFirst || s.kind == "increase"
                steps.append(MoneyStep(id: s.id, name: moneyStepNames[s.id] ?? s.label, amountText: text(amount, sign: adds ? "+" : "-"),
                                       barFraction: fraction, kind: adds ? .moneyIn : .moneyOut,
                                       hint: !isFirst && s.kind == "increase" && s.id != "other-income" ? "Credits were bigger than costs here, so this line added money." : nil))
            }
        }
        var sentence: String?
        if let first = w.steps.first, let last = w.steps.last, cents(first.to) > 0 {
            let perDollar = Int((Double(cents(last.to)) / Double(cents(first.to)) * 100).rounded())
            sentence = perDollar >= 0
                ? "Out of every $1 in sales, \(perDollar)¢ was left over as profit."
                : "For every $1 in sales, costs were $\(String(format: "%.2f", 1 + Double(-perDollar) / 100)), so the month lost money."
        }
        return MoneyStepList(steps: steps, perDollarSentence: sentence,
                             tieNote: w.reconciles ? "Each line is a QuickBooks total, and they add up exactly to the result." : (w.note ?? ""))
    }
}
