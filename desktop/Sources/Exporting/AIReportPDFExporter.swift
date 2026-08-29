import Foundation
import CoreGraphics
import CoreText
import Core

/// Owner directive (2026-08-29): a client-facing PDF for the two AI-
/// generated reports (Book Health Report, Client Value Summary) — the
/// content quality was proven live first (a real prompt-engineering fix
/// to `routes/ai.ts`), so this only had to become a document, not also
/// prove the content was worth exporting.
///
/// Unlike `PDFReportExporter` (a flat table) and `ClosePackagePDFExporter`
/// (fixed titled sections of already-structured data), this exporter's
/// body is free-flowing AI-generated prose — the one genuinely new piece
/// here is paragraph word-wrapping via `CTFramesetter`, which neither
/// existing exporter needed. Everything else (page geometry, the SANDBOX
/// banner, drawing a single line) reuses `PDFReportExporter.drawLine`
/// rather than re-implementing it.
///
/// **CLAUDE.md rule 7 applies here too**: a PDF that could be handed to a
/// client is exactly the kind of document that must never be confusable
/// between sandbox and production — the same prominent banner
/// `ClosePackagePDFExporter` already prints when `environment` says so.
///
/// **Honesty about what this is**: the footer always states which AI
/// provider generated the text and that it is AI-narrated prose
/// summarizing figures the app itself computed — never presented as if
/// Voice Ledger's own deterministic engine wrote the sentences, matching
/// the same boundary `AskAIContext`'s doc comments enforce everywhere
/// else (CLAUDE.md rule 1: the model explains, the app computes).
public enum AIReportPDFExporter {
    public struct Input {
        public let reportTitle: String // "Book Health Report" / "Client Value Summary"
        public let companyName: String?
        public let environment: String // "sandbox" or "production"
        public let period: AccountingPeriod
        public let generatedAt: Date
        public let providerLabel: String // "Gemma (local, free)" / "OpenAI"
        public let bodyText: String

        public init(
            reportTitle: String,
            companyName: String?,
            environment: String,
            period: AccountingPeriod,
            generatedAt: Date = Date(),
            providerLabel: String,
            bodyText: String
        ) {
            self.reportTitle = reportTitle
            self.companyName = companyName
            self.environment = environment
            self.period = period
            self.generatedAt = generatedAt
            self.providerLabel = providerLabel
            self.bodyText = bodyText
        }
    }

    private static let pageWidth: CGFloat = 612
    private static let pageHeight: CGFloat = 792
    private static let margin: CGFloat = 54
    private static let bodyFontSize: CGFloat = 11
    private static let paragraphSpacing: CGFloat = 10

    public static func export(_ input: Input) -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return Data() }
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return Data() }

        let titleFont = CTFontCreateWithName("Helvetica-Bold" as CFString, 20, nil)
        let subtitleFont = CTFontCreateWithName("Helvetica" as CFString, 11, nil)
        let bodyFont = CTFontCreateWithName("Helvetica" as CFString, bodyFontSize, nil)
        let footerFont = CTFontCreateWithName("Helvetica-Oblique" as CFString, 8, nil)
        let bannerFont = CTFontCreateWithName("Helvetica-Bold" as CFString, 12, nil)
        let textColor = CGColor(gray: 0.1, alpha: 1)
        let mutedColor = CGColor(gray: 0.45, alpha: 1)
        let sandboxColor = CGColor(red: 0.72, green: 0.45, blue: 0.09, alpha: 1)

        let periodLabel = "\(input.period.year)-\(String(format: "%02d", input.period.month))"
        let dateFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .short
            return f
        }()

        let contentWidth = pageWidth - 2 * margin
        let footerHeight: CGFloat = 30
        let contentBottom = margin + footerHeight

        func drawFooter(page: Int) {
            let footerText = "\(input.providerLabel) generated this summary from figures Voice Ledger's own rules already computed — it explains, it doesn't decide. Page \(page + 1)."
            PDFReportExporter.drawLine(footerText, x: margin, y: margin + 12, font: footerFont, color: mutedColor, in: context, maxWidth: contentWidth)
        }

        /// Header drawn only on page 1: title, company/period, and the
        /// SANDBOX banner when applicable. Returns the y-coordinate body
        /// text should start at.
        func drawFirstPageHeader() -> CGFloat {
            var y = pageHeight - margin - 20
            PDFReportExporter.drawLine(input.reportTitle, x: margin, y: y, font: titleFont, color: textColor, in: context)
            y -= 22
            let subtitle = [input.companyName, "Period \(periodLabel)", "Generated \(dateFormatter.string(from: input.generatedAt))"]
                .compactMap { $0 }
                .joined(separator: "  ·  ")
            PDFReportExporter.drawLine(subtitle, x: margin, y: y, font: subtitleFont, color: mutedColor, in: context, maxWidth: contentWidth)
            y -= 20
            if input.environment.lowercased() == "sandbox" {
                let bannerText = "SANDBOX — not a real client's books"
                PDFReportExporter.drawLine(bannerText, x: margin, y: y, font: bannerFont, color: sandboxColor, in: context)
                y -= 22
            }
            y -= 10
            return y
        }

        // MARK: - Paginated body via CTFramesetter, the one genuinely new
        // piece this exporter needed over the other two (both of which only
        // ever draw single, unwrapped lines).
        // CoreText's own paragraph-style API, not `NSMutableParagraphStyle`
        // (an AppKit extension unavailable here — see `PDFReportExporter`'s
        // own doc comment for why this module deliberately doesn't import
        // AppKit).
        let paragraphSpacingValue = Float(paragraphSpacing)
        let paragraphStyle = withUnsafeBytes(of: paragraphSpacingValue) { rawBuffer -> CTParagraphStyle in
            let setting = CTParagraphStyleSetting(spec: .paragraphSpacing, valueSize: MemoryLayout<Float>.size, value: rawBuffer.baseAddress!)
            return CTParagraphStyleCreate([setting], 1)
        }
        let attributedBody = NSAttributedString(
            string: input.bodyText,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): bodyFont,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): textColor,
                NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraphStyle
            ]
        )
        let framesetter = CTFramesetterCreateWithAttributedString(attributedBody)
        let totalLength = attributedBody.length

        var page = 0
        var consumed = 0
        // `beginPDFPage` MUST precede any drawing on a PDF-backed
        // CGContext — calling `drawFirstPageHeader()` before this (a real
        // bug caught by `AIReportPDFExporterTests`) silently drops every
        // header/banner draw call and, per CoreGraphics' own PDF error
        // logging, corrupts the page count besides.
        context.beginPDFPage(nil)
        var y = drawFirstPageHeader()

        while consumed < totalLength || page == 0 {
            let remainingHeight = y - contentBottom
            guard remainingHeight > bodyFontSize else {
                drawFooter(page: page)
                context.endPDFPage()
                page += 1
                context.beginPDFPage(nil)
                y = pageHeight - margin - 20
                continue
            }

            let path = CGPath(rect: CGRect(x: margin, y: contentBottom, width: contentWidth, height: remainingHeight), transform: nil)
            let range = CFRangeMake(consumed, 0)
            let frame = CTFramesetterCreateFrame(framesetter, range, path, nil)
            CTFrameDraw(frame, context)

            let visibleRange = CTFrameGetVisibleStringRange(frame)
            let newConsumed = visibleRange.location + visibleRange.length
            // A zero-progress frame (can happen if a single "word" is wider
            // than the whole column) would loop forever — force progress
            // rather than hang on a pathological input.
            consumed = newConsumed > consumed ? newConsumed : totalLength

            if consumed >= totalLength {
                break
            }
            drawFooter(page: page)
            context.endPDFPage()
            page += 1
            context.beginPDFPage(nil)
            y = pageHeight - margin - 20
        }

        if totalLength == 0 {
            PDFReportExporter.drawLine("No report content.", x: margin, y: y, font: bodyFont, color: mutedColor, in: context)
        }
        drawFooter(page: page)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }
}
