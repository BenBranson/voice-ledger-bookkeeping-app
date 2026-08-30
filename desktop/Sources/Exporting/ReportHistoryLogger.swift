import Foundation
import Core

/// Owner directive (2026-08-29): "when I generate a report it logs it
/// somewhere in an app and possible on a text file on my computer so I can
/// compare monthly and weekly, or even session report differences." The
/// in-app half is `AppState.conversationHistory` (persisted via
/// `ClientStore`); this is the on-disk half — a real, plain-text file the
/// owner can open, search, or diff with any tool, independent of the app.
///
/// One growing text file per report kind, in a Finder-visible location
/// (`~/Documents`, not the app's own hidden Application Support folder,
/// since the whole point is the owner opening it themselves) — each
/// generation appended as a clearly delimited, timestamped entry rather
/// than overwriting, so the file itself becomes the week-over-week/
/// month-over-month record to compare against.
public enum ReportHistoryLogger {
    private static let separator = String(repeating: "=", count: 64)

    /// - Parameters:
    ///   - reportTitle: used both as the on-screen header and to derive
    ///     the filename — "Book Health Report" / "Client Value Summary",
    ///     one file per title per client.
    ///   - baseDirectory: defaults to the real `~/Documents` — overridable
    ///     so tests can point this at a temp directory instead of writing
    ///     into the real user's Documents folder on every test run.
    public static func append(
        reportTitle: String,
        companyName: String?,
        environment: String,
        period: AccountingPeriod,
        providerLabel: String,
        bodyText: String,
        generatedAt: Date = Date(),
        baseDirectory: URL? = nil
    ) {
        let periodLabel = "\(period.year)-\(String(format: "%02d", period.month))"
        let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter
        }()
        let sandboxNote = environment.lowercased() == "sandbox" ? " — SANDBOX, not a real client's books" : ""

        var entry = "\(separator)\n"
        entry += "\(reportTitle) — \(providerLabel)\n"
        entry += "\(companyName ?? "Unknown company") — Period \(periodLabel)\(sandboxNote)\n"
        entry += "Generated \(dateFormatter.string(from: generatedAt))\n"
        entry += "\(separator)\n\n"
        entry += bodyText
        entry += "\n\n\n"

        guard let fileURL = fileURL(for: reportTitle, companyName: companyName, baseDirectory: baseDirectory) else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                if let data = entry.data(using: .utf8) {
                    handle.write(data)
                }
            } else {
                try entry.write(to: fileURL, atomically: true, encoding: .utf8)
            }
        } catch {
            // Best-effort, matching this app's other on-disk logging
            // (Activity Log, checklist completions) — a failure to write
            // this file is not a reason to make the report generation
            // itself look like it failed; the in-app conversation history
            // is the primary record, this is a convenience export.
        }
    }

    private static func fileURL(for reportTitle: String, companyName: String?, baseDirectory: URL?) -> URL? {
        guard let documentsDirectory = baseDirectory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let safeCompanyName = (companyName ?? "Voice Ledger Client")
            .replacingOccurrences(of: "/", with: "-")
        let safeReportTitle = reportTitle.replacingOccurrences(of: "/", with: "-")
        return documentsDirectory
            .appending(path: "Voice Ledger Reports", directoryHint: .isDirectory)
            .appending(path: safeCompanyName, directoryHint: .isDirectory)
            .appending(path: "\(safeReportTitle).txt", directoryHint: .notDirectory)
    }
}
