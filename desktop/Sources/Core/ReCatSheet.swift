import Foundation

/// Client clarification sheet (owner feature list 2026-09-29): every
/// uncategorized / Ask My Accountant item in one CSV the client fills in
/// ("Home Depot: drywall for Project X"), then imported back as that
/// finding's client answer. Explanations only — importing never writes to
/// QBO; the bookkeeper still recategorizes through the normal review path.
public enum ReCatSheet {
    public static let findingIDColumn = "Voice Ledger ID (don't edit)"
    public static let explanationColumn = "What was this for? (client fills in)"
    public static let receiptColumn = "Receipt attached? (Y/N)"
    public static let columns = [findingIDColumn, "Date", "Payee", "Amount", "Currently in", explanationColumn, receiptColumn]

    public static func items(from findings: [Finding]) -> [Finding] {
        findings.filter { $0.status == .open && $0.ruleID.rawValue == UncategorizedTransactionRule.identity.id.rawValue }
    }

    public static func export(findings: [Finding], companyName: String?) -> ExportTable {
        let rows: [[ExportCell]] = items(from: findings).map { finding in
            let evidence = finding.evidence.first?.fieldValues ?? [:]
            return [
                ExportCell(text: finding.id),
                ExportCell(text: evidence["date"] ?? ""),
                ExportCell(text: finding.vendorName ?? evidence["vendor"] ?? ""),
                ExportCell(text: finding.dollarExposure.accountingDescription, numericValue: finding.dollarExposure.majorUnitsDouble),
                ExportCell(text: evidence["lineAccount"] ?? "Uncategorized"),
                ExportCell(text: ""),
                ExportCell(text: "")
            ]
        }
        return ExportTable(title: "Transactions we need your help with — \(companyName ?? "Client")", columns: columns, rows: rows)
    }

    public struct Answer: Equatable, Sendable {
        public let findingID: String
        public let text: String
    }

    /// `rows` are already-parsed CSV rows, header first. Rows the client
    /// left blank, and IDs that aren't open ReCat items, are skipped.
    public static func answers(fromRows rows: [[String]], openFindings: [Finding]) -> [Answer] {
        guard let header = rows.first,
              let idIndex = header.firstIndex(of: findingIDColumn),
              let explanationIndex = header.firstIndex(of: explanationColumn) else { return [] }
        let receiptIndex = header.firstIndex(of: receiptColumn)
        let valid = Set(items(from: openFindings).map(\.id))
        return rows.dropFirst().compactMap { row in
            guard row.count > max(idIndex, explanationIndex) else { return nil }
            let id = row[idIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            let explanation = row[explanationIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            guard valid.contains(id), !explanation.isEmpty else { return nil }
            let receipt = receiptIndex.flatMap { $0 < row.count ? row[$0].trimmingCharacters(in: .whitespaces).uppercased() : nil }
            let suffix = receipt == "Y" || receipt == "YES" ? " (client says a receipt is attached)" : ""
            return Answer(findingID: id, text: explanation + suffix)
        }
    }
}
