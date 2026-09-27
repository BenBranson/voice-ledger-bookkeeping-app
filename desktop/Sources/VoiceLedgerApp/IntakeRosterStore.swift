import Foundation
import Core
import Exporting
import IntegrationsImports

/// Persists the firm's prospect/client intake roster as a single, plain
/// CSV file at a fixed, user-findable path — deliberately NOT scoped to
/// any one QBO `realmId` the way `ClientStore` is, since most intake
/// happens before a prospect has connected QBO at all (some may never
/// connect). Owner directive: "the file could go to a database or a csv
/// or a xlsx file on my computer... make sure the file can be opened in
/// google sheets" — CSV is the simplest format that opens cleanly in both
/// Sheets and Excel with zero conversion step, matching
/// `CSVReportExporter`'s own reasoning for every other export in this app.
///
/// This type only ever rewrites the WHOLE file from the in-app list it's
/// given — never a partial append, and never a silent merge with whatever
/// the file currently contains. `loadAll()` is the one place external
/// edits (made directly in Sheets/Excel) come back into the app, and it's
/// always an explicit action (app launch, or a "Reload from File" button)
/// — never a background watcher — so a bookkeeper's own in-app edits are
/// never silently clobbered by a stale file, and vice versa.
public struct IntakeRosterStore {
    public let fileURL: URL

    public init(directory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]) {
        let folder = directory.appendingPathComponent("Voice Ledger", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.fileURL = folder.appendingPathComponent("Client Intake.csv")
    }

    public func loadAll() -> [ClientIntake] {
        guard let data = try? Data(contentsOf: fileURL), let text = String(data: data, encoding: .utf8) else { return [] }
        let rows = CSVParser.parse(text)
        guard let header = rows.first else { return [] }
        return rows.dropFirst().compactMap { row in
            var fields: [String: String] = [:]
            for (index, key) in header.enumerated() where index < row.count {
                fields[key] = row[index]
            }
            return ClientIntakeCSV.intake(from: fields)
        }
    }

    public func saveAll(_ intakes: [ClientIntake]) throws {
        let table = ExportTable(
            title: "Client Intake",
            columns: ClientIntakeCSV.columns,
            rows: intakes.map { intake in
                let fields = ClientIntakeCSV.fields(for: intake)
                return ClientIntakeCSV.columns.map { ExportCell(text: fields[$0] ?? "") }
            }
        )
        let data = CSVReportExporter.export(table)
        try data.write(to: fileURL, options: .atomic)
    }
}
