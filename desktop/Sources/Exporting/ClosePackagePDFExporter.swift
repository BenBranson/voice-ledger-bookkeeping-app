import Foundation
import CoreGraphics
import CoreText
import Core

/// The "branded client PDF" `PDFReportExporter`'s own doc comment flagged
/// as a different, larger feature than a flat table export — built
/// 2026-08-28, specifically for the Close Package (docs/VOICE_LEDGER_SPEC.md's
/// Firm Cockpit section). A real designed document: a cover page (company
/// name, period, generated date) followed by titled sections, not one flat
/// spreadsheet-style table — `ClosePackageView`'s own multi-part shape
/// (checklist, cleanup summary, reports, corrections, carry-forward,
/// activity) doesn't fit `ExportTable`'s single-table shape at all.
///
/// **CLAUDE.md rule 7 extended to the exported document itself**: sandbox
/// vs. production must be visually unmistakable everywhere in the app —
/// a PDF handed to a client (or filed) is no exception. The cover page
/// prints a prominent SANDBOX banner whenever `environment` says so; a
/// production package prints no such banner at all, so the two are never
/// confusable from the file alone.
public enum ClosePackagePDFExporter {
    public struct Input {
        public let companyName: String?
        public let environment: String // "sandbox" or "production" — a plain label, not a type, since Exporting doesn't depend on VoiceLedgerUI's VLEnvironmentTone
        public let period: AccountingPeriod
        public let generatedAt: Date
        public let checklistCompleted: Int
        public let checklistTotal: Int
        public let openCleanupCount: Int
        public let resolvedCleanupCount: Int
        public let balanceSheetLines: [ReportLine]
        public let profitAndLossLines: [ReportLine]
        public let cashFlowLines: [ReportLine]
        public let trialBalanceLines: [TrialBalanceLine]
        public let agedReceivablesLines: [AgingLine]
        public let agedPayablesLines: [AgingLine]
        public let corrections: [ActivityLogEntry]
        public let carryForwardItems: [(mark: CarryForwardMark, findingTitle: String, dollarExposure: Money)]
        public let recentActivity: [ActivityLogEntry]

        public init(
            companyName: String?,
            environment: String,
            period: AccountingPeriod,
            generatedAt: Date = Date(),
            checklistCompleted: Int,
            checklistTotal: Int,
            openCleanupCount: Int,
            resolvedCleanupCount: Int,
            balanceSheetLines: [ReportLine],
            profitAndLossLines: [ReportLine],
            cashFlowLines: [ReportLine],
            trialBalanceLines: [TrialBalanceLine],
            agedReceivablesLines: [AgingLine],
            agedPayablesLines: [AgingLine],
            corrections: [ActivityLogEntry],
            carryForwardItems: [(mark: CarryForwardMark, findingTitle: String, dollarExposure: Money)],
            recentActivity: [ActivityLogEntry]
        ) {
            self.companyName = companyName
            self.environment = environment
            self.period = period
            self.generatedAt = generatedAt
            self.checklistCompleted = checklistCompleted
            self.checklistTotal = checklistTotal
            self.openCleanupCount = openCleanupCount
            self.resolvedCleanupCount = resolvedCleanupCount
            self.balanceSheetLines = balanceSheetLines
            self.profitAndLossLines = profitAndLossLines
            self.cashFlowLines = cashFlowLines
            self.trialBalanceLines = trialBalanceLines
            self.agedReceivablesLines = agedReceivablesLines
            self.agedPayablesLines = agedPayablesLines
            self.corrections = corrections
            self.carryForwardItems = carryForwardItems
            self.recentActivity = recentActivity
        }
    }

    private static let pageWidth: CGFloat = 612
    private static let pageHeight: CGFloat = 792
    private static let margin: CGFloat = 54
    private static let lineHeight: CGFloat = 15

    public static func export(_ input: Input) -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return Data() }
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return Data() }

        let coverTitleFont = CTFontCreateWithName("Helvetica-Bold" as CFString, 26, nil)
        let coverSubtitleFont = CTFontCreateWithName("Helvetica" as CFString, 13, nil)
        let sectionTitleFont = CTFontCreateWithName("Helvetica-Bold" as CFString, 13, nil)
        let bodyFont = CTFontCreateWithName("Helvetica" as CFString, 10, nil)
        let mutedFont = CTFontCreateWithName("Helvetica-Oblique" as CFString, 9, nil)
        let textColor = CGColor(gray: 0.1, alpha: 1)
        let mutedColor = CGColor(gray: 0.45, alpha: 1)
        let bannerColor = CGColor(red: 0.7, green: 0.15, blue: 0.1, alpha: 1)

        let periodLabel = "\(input.period.year)-\(String(format: "%02d", input.period.month))"
        let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter
        }()

        // MARK: Cover page
        context.beginPDFPage(nil)
        var y = pageHeight - margin - 80
        PDFReportExporter.drawLine("CLOSE PACKAGE", x: margin, y: y, font: coverTitleFont, color: textColor, in: context)
        y -= 34
        PDFReportExporter.drawLine(input.companyName ?? "Connected company", x: margin, y: y, font: coverSubtitleFont, color: textColor, in: context)
        y -= 20
        PDFReportExporter.drawLine("Period: \(periodLabel)", x: margin, y: y, font: coverSubtitleFont, color: mutedColor, in: context)
        y -= 18
        PDFReportExporter.drawLine("Generated \(dateFormatter.string(from: input.generatedAt))", x: margin, y: y, font: coverSubtitleFont, color: mutedColor, in: context)

        if input.environment.lowercased() == "sandbox" {
            y -= 40
            PDFReportExporter.drawLine("⚠ SANDBOX DATA — NOT A REAL CLIENT'S BOOKS", x: margin, y: y, font: sectionTitleFont, color: bannerColor, in: context)
        }

        y -= 40
        PDFReportExporter.drawLine("Voice Ledger Activity & Correction Log excerpt follows. Report figures are normalized from QuickBooks Online and may not be pixel-identical to QBO's own rendered reports.", x: margin, y: y, font: mutedFont, color: mutedColor, in: context, maxWidth: pageWidth - 2 * margin)
        context.endPDFPage()

        // MARK: Sections
        context.beginPDFPage(nil)
        y = pageHeight - margin

        func ensureRoom(_ needed: CGFloat = lineHeight) {
            if y - needed < margin {
                context.endPDFPage()
                context.beginPDFPage(nil)
                y = pageHeight - margin
            }
        }

        func sectionHeader(_ title: String) {
            ensureRoom(30)
            y -= 20
            PDFReportExporter.drawLine(title.uppercased(), x: margin, y: y, font: sectionTitleFont, color: textColor, in: context)
            y -= lineHeight
        }

        func bodyLine(_ text: String, muted: Bool = false) {
            ensureRoom()
            PDFReportExporter.drawLine(text, x: margin, y: y, font: bodyFont, color: muted ? mutedColor : textColor, in: context, maxWidth: pageWidth - 2 * margin)
            y -= lineHeight
        }

        sectionHeader("Month-End Checklist")
        bodyLine("\(input.checklistCompleted) of \(input.checklistTotal) steps completed")

        sectionHeader("Cleanup Assessment")
        bodyLine("\(input.openCleanupCount) open finding\(input.openCleanupCount == 1 ? "" : "s"), \(input.resolvedCleanupCount) resolved this period")

        sectionHeader("Financial Reports Summary")
        for (label, lines) in [("Balance Sheet", input.balanceSheetLines), ("Profit & Loss", input.profitAndLossLines), ("Cash Flow", input.cashFlowLines)] {
            if let total = lines.last(where: { $0.isSummary }), let amount = total.amount {
                bodyLine("\(label): \(total.label) — \(amount.description)")
            } else if !lines.isEmpty {
                bodyLine("\(label): loaded, no summary total line found", muted: true)
            } else {
                bodyLine("\(label): not loaded", muted: true)
            }
        }
        if let tbTotal = input.trialBalanceLines.last(where: { $0.isSummary }) {
            let debit = tbTotal.debit?.description ?? "-"
            let credit = tbTotal.credit?.description ?? "-"
            bodyLine("Trial Balance: total debit \(debit), total credit \(credit)")
        } else {
            bodyLine("Trial Balance: not loaded", muted: true)
        }
        if let arTotal = input.agedReceivablesLines.last(where: { $0.isSummary })?.total {
            bodyLine("Aged Receivables total: \(arTotal.description)")
        }
        if let apTotal = input.agedPayablesLines.last(where: { $0.isSummary })?.total {
            bodyLine("Aged Payables total: \(apTotal.description)")
        }

        sectionHeader("Corrections Made")
        if input.corrections.isEmpty {
            bodyLine("None this period.", muted: true)
        } else {
            for entry in input.corrections {
                bodyLine("\(dateFormatter.string(from: entry.recordedAt)) — \(entry.kind.humanLabel)\(entry.findingSummary.map { ": \($0)" } ?? "") (\(entry.actor.displayLabel))")
            }
        }

        sectionHeader("Carry-Forward Items")
        if input.carryForwardItems.isEmpty {
            bodyLine("None.", muted: true)
        } else {
            for item in input.carryForwardItems {
                bodyLine("\(item.findingTitle) — \(item.dollarExposure.description)\(item.mark.reason.map { ": \($0)" } ?? "")")
            }
        }

        sectionHeader("Recent Activity")
        if input.recentActivity.isEmpty {
            bodyLine("No activity recorded.", muted: true)
        } else {
            for entry in input.recentActivity.prefix(30) {
                bodyLine("\(dateFormatter.string(from: entry.recordedAt)) — \(entry.kind.humanLabel) (\(entry.actor.displayLabel))")
            }
        }

        context.endPDFPage()
        context.closePDF()
        return data as Data
    }
}
