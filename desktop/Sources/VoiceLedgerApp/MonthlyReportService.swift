import Foundation
import Core

/// Runs the local report renderer (report-renderer/: ECharts SVG + WeasyPrint)
/// on a sealed report snapshot. Everything stays on this Mac; the renderer
/// never touches the network or QuickBooks.
enum MonthlyReportService {
    struct RenderError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// One generated report: the PDF and the exact snapshot behind it.
    struct GeneratedReport: Identifiable, Equatable {
        let folder: URL
        var id: String { folder.path }
        var pdfURL: URL { folder.appending(path: "report.pdf") }
        var snapshotURL: URL { folder.appending(path: "snapshot.json") }
        let periodKey: String
        let createdAt: Date
        let snapshotID: String
    }

    static func rendererDirectory() -> URL? {
        let fm = FileManager.default
        if let override = ProcessInfo.processInfo.environment["VOICE_LEDGER_REPORT_RENDERER"] {
            let url = URL(fileURLWithPath: override)
            if fm.fileExists(atPath: url.appending(path: "render.mjs").path) { return url }
        }
        // The app runs from <project>/desktop/.build/...; the renderer is
        // <project>/report-renderer.
        var cursor = Bundle.main.bundleURL
        for _ in 0..<8 {
            cursor = cursor.deletingLastPathComponent()
            let candidate = cursor.appending(path: "report-renderer")
            if fm.fileExists(atPath: candidate.appending(path: "render.mjs").path) { return candidate }
        }
        return nil
    }

    static func nodeExecutable() -> URL? {
        ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"]
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static func historyDirectory(root: URL, realmID: RealmID) -> URL {
        root.appending(path: realmID.rawValue).appending(path: "monthly-reports")
    }

    static func history(root: URL, realmID: RealmID) -> [GeneratedReport] {
        let base = historyDirectory(root: root, realmID: realmID)
        guard let periods = try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil) else { return [] }
        return periods.flatMap { periodFolder -> [GeneratedReport] in
            let runs = (try? FileManager.default.contentsOfDirectory(at: periodFolder, includingPropertiesForKeys: [.creationDateKey])) ?? []
            return runs.compactMap { run in
                guard FileManager.default.fileExists(atPath: run.appending(path: "report.pdf").path) else { return nil }
                let created = (try? run.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let snapshotID = String(run.lastPathComponent.split(separator: "-").last ?? "")
                return GeneratedReport(folder: run, periodKey: periodFolder.lastPathComponent, createdAt: created, snapshotID: snapshotID)
            }
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    /// Writes the snapshot, renders the PDF beside it, and reports each
    /// renderer stage through `onStage`.
    static func render(report: MonthlyClientReport, root: URL, realmID: RealmID, onStage: @escaping @Sendable (String) -> Void) async throws -> GeneratedReport {
        guard let rendererDir = rendererDirectory() else {
            throw RenderError(message: "The report renderer folder wasn't found. It should be at <project>/report-renderer (or set VOICE_LEDGER_REPORT_RENDERER).")
        }
        guard let node = nodeExecutable() else {
            throw RenderError(message: "Node.js wasn't found in /opt/homebrew/bin or /usr/local/bin. Install it with \"brew install node\".")
        }
        let sealed = try report.sealedJSON()
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
        let folder = historyDirectory(root: root, realmID: realmID)
            .appending(path: report.meta.periodKey)
            .appending(path: "\(stamp)-\(sealed.snapshotID.prefix(12))")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let snapshotURL = folder.appending(path: "snapshot.json")
        let pdfURL = folder.appending(path: "report.pdf")
        try sealed.json.write(to: snapshotURL, options: .atomic)

        let process = Process()
        process.executableURL = node
        process.arguments = [rendererDir.appending(path: "render.mjs").path, snapshotURL.path, pdfURL.path]
        process.currentDirectoryURL = rendererDir
        let stdout = Pipe(), stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let text = String(decoding: handle.availableData, as: UTF8.self)
            for line in text.split(separator: "\n") {
                if let data = line.data(using: .utf8),
                   let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let stage = object["stage"] as? String {
                    onStage(stage)
                }
            }
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { finished in
                stdout.fileHandleForReading.readabilityHandler = nil
                if finished.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let raw = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    let parsed = raw.split(separator: "\n").last.flatMap { $0.data(using: .utf8) }
                        .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] }
                    let message = parsed.map { "\($0["error"] ?? "Report rendering failed.") \($0["hint"] ?? "")" } ?? "Report rendering failed (exit \(finished.terminationStatus))."
                    continuation.resume(throwing: RenderError(message: message))
                }
            }
            do { try process.run() } catch { continuation.resume(throwing: RenderError(message: "Couldn't start the renderer: \(error.localizedDescription)")) }
        }
        return GeneratedReport(folder: folder, periodKey: report.meta.periodKey, createdAt: Date(), snapshotID: sealed.snapshotID)
    }
}
