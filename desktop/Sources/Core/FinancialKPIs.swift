import Foundation

/// Small, pure derived metrics for the Balance Sheet/Profit & Loss visual
/// layer's KPI cards — same shape as `TaxEstimate.swift`: no I/O, no
/// network, each function a simple lookup-and-arithmetic over already-loaded
/// `[ReportLine]`, returning `nil` the instant a required line is missing
/// rather than guessing (CLAUDE.md rule 5 — a KPI card renders gray/"not
/// available" on `nil`, never a number that isn't real).
///
/// **Label-matching caveat, stated honestly rather than silently assumed:**
/// `TaxEstimate.netIncome`'s "Net Income" lookup was confirmed live
/// 2026-08-27 against a real sandbox Balance Sheet/P&L. The labels below
/// ("Total Current Assets," "Total Current Liabilities," "Gross Profit,"
/// "Total Income," "Cash," "Accounts Receivable") are QBO's own standard,
/// well-documented report section names, but have NOT yet been individually
/// re-confirmed against this app's actual sandbox company the way "Net
/// Income" was — per CLAUDE.md rule 6 ("no feature labeled Automatic
/// without sandbox proof"), that live check still needs to happen before
/// these KPI cards are trusted as anything more than "should work against
/// standard QBO reports." Until then, a `nil` here is the honest, safe
/// failure mode: the card shows "not available," never a wrong number.
public enum FinancialKPIs {
    private static func summaryAmount(_ label: String, in lines: [ReportLine]) -> Money? {
        lines.first(where: { $0.isSummary && $0.label == label })?.amount
    }

    /// Gross Profit / Total Income, as a percentage (0...100 scale, e.g.
    /// `42.5` means 42.5%). `nil` if either line is missing, or Total
    /// Income is zero (division would be meaningless, not zero).
    public static func grossMarginPercent(from profitAndLossLines: [ReportLine]) -> Double? {
        guard let grossProfit = summaryAmount("Gross Profit", in: profitAndLossLines),
              let totalIncome = summaryAmount("Total Income", in: profitAndLossLines),
              totalIncome.minorUnits != 0 else { return nil }
        return grossProfit.majorUnitsDouble / totalIncome.majorUnitsDouble * 100
    }

    /// Net Income / Total Income, as a percentage. Reuses
    /// `TaxEstimate.netIncome` for the numerator — the one label in this
    /// file already live-verified — rather than re-deriving it.
    public static func netMarginPercent(from profitAndLossLines: [ReportLine]) -> Double? {
        guard let netIncome = TaxEstimate.netIncome(from: profitAndLossLines),
              let totalIncome = summaryAmount("Total Income", in: profitAndLossLines),
              totalIncome.minorUnits != 0 else { return nil }
        return netIncome.majorUnitsDouble / totalIncome.majorUnitsDouble * 100
    }

    /// Total Current Assets − Total Current Liabilities.
    public static func workingCapital(from balanceSheetLines: [ReportLine]) -> Money? {
        guard let currentAssets = summaryAmount("Total Current Assets", in: balanceSheetLines),
              let currentLiabilities = summaryAmount("Total Current Liabilities", in: balanceSheetLines),
              currentAssets.currency == currentLiabilities.currency else { return nil }
        return currentAssets - currentLiabilities
    }

    /// Total Current Assets / Total Current Liabilities. `nil` if
    /// liabilities are zero (an undefined ratio, not an infinite one worth
    /// displaying).
    public static func currentRatio(from balanceSheetLines: [ReportLine]) -> Double? {
        guard let currentAssets = summaryAmount("Total Current Assets", in: balanceSheetLines),
              let currentLiabilities = summaryAmount("Total Current Liabilities", in: balanceSheetLines),
              currentLiabilities.minorUnits != 0 else { return nil }
        return currentAssets.majorUnitsDouble / currentLiabilities.majorUnitsDouble
    }

    /// (Cash + Accounts Receivable) / Total Current Liabilities. Cash and
    /// Accounts Receivable are looked up as `isSummary` section totals the
    /// same way as everything else here — if either doesn't exist as its
    /// own summary line in this company's Balance Sheet (a real possibility
    /// depending on chart-of-accounts structure), this returns `nil` rather
    /// than guessing from a non-summary line.
    public static func quickRatio(from balanceSheetLines: [ReportLine]) -> Double? {
        guard let cash = summaryAmount("Cash", in: balanceSheetLines),
              let receivables = summaryAmount("Accounts Receivable", in: balanceSheetLines),
              let currentLiabilities = summaryAmount("Total Current Liabilities", in: balanceSheetLines),
              currentLiabilities.minorUnits != 0,
              cash.currency == receivables.currency else { return nil }
        return (cash.majorUnitsDouble + receivables.majorUnitsDouble) / currentLiabilities.majorUnitsDouble
    }
}
