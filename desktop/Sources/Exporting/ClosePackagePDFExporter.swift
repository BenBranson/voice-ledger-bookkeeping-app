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
/// **Internal close record (owner, 2026-10-03).** This is the bookkeeper's
/// file copy of the close, not a client deliverable (clients get the
/// 2-page Client Summary and the Full Report). Every page says INTERNAL.
/// The bookkeeper's Ask AI conversations are deliberately NOT an input:
/// they are private working notes and must never land in an exported file.
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
        /// Built 2026-09-11, alongside the on-screen Close Package section
        /// of the same name — see `ClientQuestionDrafter.Thread`'s doc
        /// comment for how these are computed.
        public let clientQuestionThreads: [ClientQuestionDrafter.Thread]
        public let recentActivity: [ActivityLogEntry]
        /// Owner directive (2026-08-31): an AI-narrated executive summary
        /// paragraph, generated on the Close Package page (edited by the
        /// bookkeeper before export, same "review before it's real"
        /// posture as everything else AI-drafted in this app) — `nil`
        /// entirely omits the section rather than rendering an empty
        /// placeholder, since generating it is optional, not automatic.
        /// The exporter itself never calls AI or computes anything about
        /// this text; it only lays out whatever string it's handed.
        public let executiveSummary: String?
        /// Per-step sign-offs (who, when) — the workpaper half of the close.
        public let checklistSignOffs: ExportTable?

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
            clientQuestionThreads: [ClientQuestionDrafter.Thread] = [],
            recentActivity: [ActivityLogEntry],
            executiveSummary: String? = nil,
            checklistSignOffs: ExportTable? = nil
        ) {
            self.checklistSignOffs = checklistSignOffs
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
            self.clientQuestionThreads = clientQuestionThreads
            self.recentActivity = recentActivity
            self.executiveSummary = executiveSummary
        }
    }

    /// One line per day + kind + actor (+ finding, for corrections), with a
    /// count: "Oct 2, 2026 — Finding detected × 24 (By Voice Ledger)".
    /// Entries arrive most-recent-first and keep that order. Amounts in
    /// engine text ("USD 4264.76") are polished to "$4,264.76".
    public static func groupedLines(_ entries: [ActivityLogEntry], detail: Bool) -> [String] {
        let day = DateFormatter()
        day.dateStyle = .medium
        day.timeStyle = .none
        var keys: [String] = []
        var counts: [String: Int] = [:]
        for entry in entries {
            let what = entry.kind.humanLabel + (detail ? entry.findingSummary.map { ": \(ClientText.polish($0))" } ?? "" : "")
            let key = "\(day.string(from: entry.recordedAt)) — \(what)|\(entry.actor.displayLabel)"
            if counts[key] == nil { keys.append(key) }
            counts[key, default: 0] += 1
        }
        return keys.map { key in
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            let n = counts[key] ?? 1
            return "\(parts[0])\(n > 1 ? " × \(n)" : "") (\(parts[1]))"
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

        var pageNumber = 0
        func beginPage() {
            context.beginPDFPage(nil)
            pageNumber += 1
            PDFReportExporter.drawLine("INTERNAL — not for clients · \(input.companyName ?? "Connected company") · \(periodLabel) · page \(pageNumber)",
                                       x: margin, y: margin / 2, font: mutedFont, color: mutedColor, in: context, maxWidth: pageWidth - 2 * margin)
        }

        // MARK: Cover page
        beginPage()
        var y = pageHeight - margin - 80
        PDFReportExporter.drawLine("CLOSE RECORD — INTERNAL", x: margin, y: y, font: coverTitleFont, color: textColor, in: context)
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
        PDFReportExporter.drawLine("Internal bookkeeping record of this month's close: checklist, report totals, corrections and activity. Not for clients; send the Client Summary and Full Report instead.", x: margin, y: y, font: mutedFont, color: mutedColor, in: context, maxWidth: pageWidth - 2 * margin)
        context.endPDFPage()

        // MARK: Sections
        beginPage()
        y = pageHeight - margin

        func ensureRoom(_ needed: CGFloat = lineHeight) {
            if y - needed < margin {
                context.endPDFPage()
                beginPage()
                y = pageHeight - margin
            }
        }

        func sectionHeader(_ title: String) {
            ensureRoom(30)
            y -= 20
            PDFReportExporter.drawLine(title.uppercased(), x: margin, y: y, font: sectionTitleFont, color: textColor, in: context)
            y -= lineHeight
        }


        // Owner directive (2026-08-31): an AI-narrated executive summary
        // paragraph, unlike every other line in this exporter, is real
        // prose that can run well past one line — `bodyLine`/`drawLine`'s
        // `maxWidth` only TRUNCATES a single line (see `drawLine`'s own
        // comment: "truncate visually... a real column-width solver is out
        // of scope"), which is correct for this file's other short data
        // rows but would silently cut off most of a real paragraph here.
        // Reuses the same `CTFramesetter` word-wrapping technique
        // `AIReportPDFExporter` already built and tested for exactly this
        // reason, scoped down to one wrapped block within this exporter's
        // existing section-by-section page flow rather than that other
        // exporter's whole-document pagination.
        func drawWrappedParagraph(_ text: String, color: CGColor? = nil) {
            let attributed = NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): bodyFont,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color ?? textColor
            ])
            let framesetter = CTFramesetterCreateWithAttributedString(attributed)
            let totalLength = attributed.length
            var consumed = 0
            while consumed < totalLength {
                ensureRoom(lineHeight * 2)
                let availableHeight = y - margin
                let path = CGPath(rect: CGRect(x: margin, y: margin, width: pageWidth - 2 * margin, height: availableHeight), transform: nil)
                let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(consumed, 0), path, nil)
                CTFrameDraw(frame, context)

                let visibleRange = CTFrameGetVisibleStringRange(frame)
                let newConsumed = visibleRange.location + visibleRange.length
                // Same zero-progress guard as `AIReportPDFExporter` — a
                // single "word" wider than the column would otherwise loop
                // forever instead of just cutting it off.
                consumed = newConsumed > consumed ? newConsumed : totalLength

                let frameLines = CTFrameGetLines(frame) as! [CTLine]
                if !frameLines.isEmpty {
                    var origins = [CGPoint](repeating: .zero, count: frameLines.count)
                    CTFrameGetLineOrigins(frame, CFRangeMake(0, frameLines.count), &origins)
                    y = origins[frameLines.count - 1].y - lineHeight
                }

                if consumed < totalLength {
                    context.endPDFPage()
                    beginPage()
                    y = pageHeight - margin
                }
            }
        }

        // Wraps long rows (owner, 2026-10-03: the old one-line truncation cut
        // amounts and names off mid-word).
        func bodyLine(_ text: String, muted: Bool = false) {
            drawWrappedParagraph(text, color: muted ? mutedColor : textColor)
        }

        if let executiveSummary = input.executiveSummary, !executiveSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sectionHeader("Executive Summary")
            for paragraph in executiveSummary.components(separatedBy: "\n") where !paragraph.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                drawWrappedParagraph(paragraph)
                y -= lineHeight * 0.5
            }
        }

        sectionHeader("Month-End Checklist")
        bodyLine("\(input.checklistCompleted) of \(input.checklistTotal) steps completed")
        for row in input.checklistSignOffs?.rows ?? [] where row.count >= 6 {
            let who = row[3].text.isEmpty ? "" : " — \(row[3].text), \(row[4].text)"
            bodyLine("\(row[0].text). \(row[1].text): \(row[2].text)\(who)", muted: row[2].text == "Open")
        }

        sectionHeader("Cleanup Assessment")
        bodyLine("\(input.openCleanupCount) open finding\(input.openCleanupCount == 1 ? "" : "s"), \(input.resolvedCleanupCount) resolved this period")

        sectionHeader("Financial Reports Summary")
        for (label, lines) in [("Balance Sheet", input.balanceSheetLines), ("Profit & Loss", input.profitAndLossLines), ("Cash Flow", input.cashFlowLines)] {
            if let total = lines.last(where: { $0.isSummary }), let amount = total.amount {
                bodyLine("\(label): \(total.label) — \(amount.accountingDescription)")
            } else if !lines.isEmpty {
                bodyLine("\(label): loaded, no summary total line found", muted: true)
            } else {
                bodyLine("\(label): not loaded", muted: true)
            }
        }
        if let tbTotal = input.trialBalanceLines.last(where: { $0.isSummary }) {
            let debit = tbTotal.debit?.accountingDescription ?? "-"
            let credit = tbTotal.credit?.accountingDescription ?? "-"
            bodyLine("Trial Balance: total debit \(debit), total credit \(credit)")
        } else {
            bodyLine("Trial Balance: not loaded", muted: true)
        }
        if let arTotal = input.agedReceivablesLines.last(where: { $0.isSummary })?.total {
            bodyLine("Aged Receivables total: \(arTotal.accountingDescription)")
        }
        if let apTotal = input.agedPayablesLines.last(where: { $0.isSummary })?.total {
            bodyLine("Aged Payables total: \(apTotal.accountingDescription)")
        }

        sectionHeader("Corrections Made")
        if input.corrections.isEmpty {
            bodyLine("None this period.", muted: true)
        } else {
            for line in groupedLines(input.corrections, detail: true) { bodyLine(line) }
        }

        sectionHeader("Carry-Forward Items")
        if input.carryForwardItems.isEmpty {
            bodyLine("None.", muted: true)
        } else {
            for item in input.carryForwardItems {
                bodyLine("\(item.findingTitle) — \(item.dollarExposure.accountingDescription)\(item.mark.reason.map { ": \($0)" } ?? "")")
            }
        }

        sectionHeader("Client Q&A")
        if input.clientQuestionThreads.isEmpty {
            bodyLine("None this period.", muted: true)
        } else {
            for thread in input.clientQuestionThreads {
                bodyLine("\(thread.findingTitle) — Q: \(thread.question)")
                bodyLine(thread.answer.map { "A: \($0)" } ?? "Awaiting reply.", muted: thread.answer == nil)
            }
        }

        sectionHeader("Recent Activity")
        if input.recentActivity.isEmpty {
            bodyLine("No activity recorded.", muted: true)
        } else {
            for line in groupedLines(input.recentActivity, detail: false).prefix(30) { bodyLine(line) }
        }

        context.endPDFPage()
        context.closePDF()
        return data as Data
    }
}
