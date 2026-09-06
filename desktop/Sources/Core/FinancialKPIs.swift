import Foundation

/// Small, pure derived metrics for the Balance Sheet/Profit & Loss visual
/// layer's KPI cards — same shape as `TaxEstimate.swift`: no I/O, no
/// network, each function a simple lookup-and-arithmetic over already-loaded
/// `[ReportLine]`, returning `nil` the instant a required line is missing
/// rather than guessing (CLAUDE.md rule 5 — a KPI card renders gray/"not
/// available" on `nil`, never a number that isn't real).
///
/// **Label-matching, now live-verified 2026-08-29** against this app's
/// actual sandbox company (`voiceledger-devtool sync-check`, and confirmed
/// again through the real running app) — "Total Current Assets," "Total
/// Current Liabilities," "Gross Profit," and "Total Income" all matched on
/// the first try. Two didn't, and are fixed here from the real observed
/// output rather than guessed again: this company's Balance Sheet has no
/// bare "Cash" summary line (its cash accounts total under "Total Bank
/// Accounts") and its receivables total is "Total Accounts Receivable," not
/// "Accounts Receivable." `summaryAmount` now takes a candidate list and
/// uses the first that matches, so a differently-configured QBO company
/// (e.g. one that DOES have a bare "Cash" line) still resolves correctly.
public enum FinancialKPIs {
    private static func summaryAmount(_ candidates: [String], in lines: [ReportLine]) -> Money? {
        for label in candidates {
            if let amount = lines.first(where: { $0.isSummary && $0.label == label })?.amount {
                return amount
            }
        }
        return nil
    }

    /// Gross Profit / Total Income, as a percentage (0...100 scale, e.g.
    /// `42.5` means 42.5%). `nil` if either line is missing, or Total
    /// Income is zero (division would be meaningless, not zero).
    public static func grossMarginPercent(from profitAndLossLines: [ReportLine]) -> Double? {
        guard let grossProfit = summaryAmount(["Gross Profit"], in: profitAndLossLines),
              let totalIncome = summaryAmount(["Total Income"], in: profitAndLossLines),
              totalIncome.minorUnits != 0 else { return nil }
        return grossProfit.majorUnitsDouble / totalIncome.majorUnitsDouble * 100
    }

    /// Net Income / Total Income, as a percentage. Reuses
    /// `TaxEstimate.netIncome` for the numerator — the one label in this
    /// file already live-verified — rather than re-deriving it.
    public static func netMarginPercent(from profitAndLossLines: [ReportLine]) -> Double? {
        guard let netIncome = TaxEstimate.netIncome(from: profitAndLossLines),
              let totalIncome = summaryAmount(["Total Income"], in: profitAndLossLines),
              totalIncome.minorUnits != 0 else { return nil }
        return netIncome.majorUnitsDouble / totalIncome.majorUnitsDouble * 100
    }

    /// Total Current Assets − Total Current Liabilities.
    public static func workingCapital(from balanceSheetLines: [ReportLine]) -> Money? {
        guard let currentAssets = summaryAmount(["Total Current Assets"], in: balanceSheetLines),
              let currentLiabilities = summaryAmount(["Total Current Liabilities"], in: balanceSheetLines),
              currentAssets.currency == currentLiabilities.currency else { return nil }
        return currentAssets - currentLiabilities
    }

    /// Total Current Assets / Total Current Liabilities. `nil` if
    /// liabilities are zero (an undefined ratio, not an infinite one worth
    /// displaying).
    public static func currentRatio(from balanceSheetLines: [ReportLine]) -> Double? {
        guard let currentAssets = summaryAmount(["Total Current Assets"], in: balanceSheetLines),
              let currentLiabilities = summaryAmount(["Total Current Liabilities"], in: balanceSheetLines),
              currentLiabilities.minorUnits != 0 else { return nil }
        return currentAssets.majorUnitsDouble / currentLiabilities.majorUnitsDouble
    }

    /// The client's current cash/bank balance — same label candidates
    /// `quickRatio` already verified live against this sandbox company
    /// ("Cash" first, falling back to "Total Bank Accounts"). Added
    /// 2026-09-06 for `VoiceToolLoop`'s `get_financial_summary` tool —
    /// previously this amount was only ever computed as a hidden
    /// intermediate inside `quickRatio`, never exposed on its own.
    public static func cashBalance(from balanceSheetLines: [ReportLine]) -> Money? {
        summaryAmount(["Cash", "Total Bank Accounts"], in: balanceSheetLines)
    }

    /// Total revenue for the period — same label `grossMarginPercent`/
    /// `netMarginPercent` already use as their denominator, exposed on its
    /// own for `VoiceToolLoop`'s `get_financial_summary` tool.
    public static func totalIncome(from profitAndLossLines: [ReportLine]) -> Money? {
        summaryAmount(["Total Income"], in: profitAndLossLines)
    }

    /// (Cash + Accounts Receivable) / Total Current Liabilities. "Cash"
    /// tries a bare "Cash" summary line first, falling back to "Total Bank
    /// Accounts" — this sandbox company (confirmed live 2026-08-29) has no
    /// bare "Cash" line; its cash accounts total under "Total Bank
    /// Accounts" instead. Receivables similarly tries "Accounts
    /// Receivable" then "Total Accounts Receivable" (this company's real
    /// label). `nil`, never a guess, if neither variant is found.
    public static func quickRatio(from balanceSheetLines: [ReportLine]) -> Double? {
        guard let cash = summaryAmount(["Cash", "Total Bank Accounts"], in: balanceSheetLines),
              let receivables = summaryAmount(["Accounts Receivable", "Total Accounts Receivable"], in: balanceSheetLines),
              let currentLiabilities = summaryAmount(["Total Current Liabilities"], in: balanceSheetLines),
              currentLiabilities.minorUnits != 0,
              cash.currency == receivables.currency else { return nil }
        return (cash.majorUnitsDouble + receivables.majorUnitsDouble) / currentLiabilities.majorUnitsDouble
    }
}
