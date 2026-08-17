import Foundation
import Core

/// docs/phase-0/09_INGESTION_PIPELINE.md §9.3/§9.4/§9.8, Tier 1: applies a
/// confirmed `ColumnMapping` to a parsed CSV, producing `LedgerTransaction`
/// records in the SAME shape the QBO API path produces (§9.8 — "/core rules
/// cannot tell the difference"). Not the full pipeline: no cross-foot
/// validation (§9.5, needs a stated statement total/ending balance this
/// importer doesn't have), no learned-mapping persistence (§9.6/stage 6), no
/// confirm-and-correct UI (§9.4) — this is stage 1 (extract) plus enough of
/// stage 2/5 to produce real normalized data from a real CSV file.
public enum BankStatementCSVImporter {
    public struct Result: Sendable {
        public let transactions: [LedgerTransaction]
        public let defects: [NormalizationDefect]
    }

    /// - Parameters:
    ///   - csvText: raw file contents.
    ///   - mappings: column mappings. Must include a `confirmed` mapping
    ///     for `.date` and `.amount` at minimum (`.description` is
    ///     recommended but not required — some exports omit it).
    ///   - hasHeaderRow: whether row 0 is a header, skipped during parsing.
    ///   - realmID, documentID, importedAt: provenance fields, carried
    ///     through to every produced `LedgerTransaction.provenance`.
    ///   - statementAccountID: the QBO account this statement is FOR — you
    ///     declare which bank/card account you're importing a statement
    ///     for (the Type B page already knows this from context), it is
    ///     never inferred from the file. Stored as `paymentAccountID` on
    ///     every produced line, the same field a posted `Purchase` uses,
    ///     so a comparison rule (e.g. `VL-RECON-MISSING-001`) can match on
    ///     it directly.
    public static func `import`(
        csvText: String,
        mappings: [ColumnMapping],
        hasHeaderRow: Bool,
        realmID: RealmID,
        documentID: ImportedDocumentID,
        importedAt: Date,
        statementAccountID: String? = nil
    ) -> Result {
        Self.import(rows: CSVParser.parse(csvText), mappings: mappings, hasHeaderRow: hasHeaderRow, realmID: realmID, documentID: documentID, importedAt: importedAt, statementAccountID: statementAccountID)
    }

    /// Same as the `csvText:` overload, but takes already-parsed rows —
    /// for a caller (e.g. a column-mapping confirmation screen) that
    /// parsed the file once already to show a preview and would otherwise
    /// have to re-serialize rows back to CSV text just to parse them again,
    /// a lossy round-trip for any field that needed quoting.
    public static func `import`(
        rows allRows: [[String]],
        mappings: [ColumnMapping],
        hasHeaderRow: Bool,
        realmID: RealmID,
        documentID: ImportedDocumentID,
        importedAt: Date,
        statementAccountID: String? = nil
    ) -> Result {
        guard !allRows.isEmpty else {
            return Result(transactions: [], defects: [.emptyFile])
        }
        let dataRows = hasHeaderRow ? Array(allRows.dropFirst()) : allRows

        guard let dateMapping = mappings.first(where: { $0.target == .date }) else {
            return Result(transactions: [], defects: [.requiredFieldUnmapped(target: .date)])
        }
        guard dateMapping.confirmed else {
            return Result(transactions: [], defects: [.requiredMappingUnconfirmed(target: .date)])
        }
        guard let amountMapping = mappings.first(where: { $0.target == .amount }) else {
            return Result(transactions: [], defects: [.requiredFieldUnmapped(target: .amount)])
        }
        guard amountMapping.confirmed else {
            return Result(transactions: [], defects: [.requiredMappingUnconfirmed(target: .amount)])
        }
        let descriptionMapping = mappings.first(where: { $0.target == .description })

        // §9.3: date format ambiguity is a defect, not a guess. Look for a
        // disambiguating row (a day value > 12) ACROSS THE WHOLE COLUMN
        // before parsing any of it as MM/DD or DD/MM.
        let rawDateValues = dataRows.compactMap { row -> String? in
            row.indices.contains(dateMapping.sourceColumn) ? row[dateMapping.sourceColumn] : nil
        }
        guard let dateOrder = Self.disambiguateDateOrder(rawDateValues) else {
            let columnLabel = dateMapping.sourceHeader ?? "column \(dateMapping.sourceColumn)"
            return Result(transactions: [], defects: [.ambiguousDateFormat(column: columnLabel, sampleValues: Array(rawDateValues.prefix(5)))])
        }

        var transactions: [LedgerTransaction] = []
        var defects: [NormalizationDefect] = []

        for (rowIndex, row) in dataRows.enumerated() {
            guard row.indices.contains(dateMapping.sourceColumn), row.indices.contains(amountMapping.sourceColumn) else { continue }

            let rawDate = row[dateMapping.sourceColumn]
            guard let date = Self.parseDate(rawDate, order: dateOrder) else {
                defects.append(.unparsableDate(row: rowIndex, column: dateMapping.sourceHeader ?? "date", value: rawDate))
                continue
            }

            let rawAmount = row[amountMapping.sourceColumn]
            guard let amount = Self.parseAmount(rawAmount) else {
                defects.append(.unparsableAmount(row: rowIndex, column: amountMapping.sourceHeader ?? "amount", value: rawAmount))
                continue
            }

            let description = descriptionMapping.flatMap { m in row.indices.contains(m.sourceColumn) ? row[m.sourceColumn] : nil }

            transactions.append(LedgerTransaction(
                id: "\(documentID.rawValue)-row\(rowIndex)",
                entityKind: .importedBankStatementLine,
                vendorName: description,
                txnDate: date,
                totalAmount: amount,
                paymentAccountID: statementAccountID,
                docNumber: nil,
                isVoided: false,
                memo: nil,
                provenance: .importedFile(documentID: documentID.rawValue, importedAt: importedAt, extractionMethod: .deterministicParse, coverage: .partial(reason: "screenshot/CSV coverage evidence not yet checked — cross-foot validation (§9.5) is not implemented in this importer"))
            ))
        }

        return Result(transactions: transactions, defects: defects)
    }

    enum DateOrder { case monthDay, dayMonth }

    /// Scans every raw date string in the column for one whose first or
    /// second numeric component exceeds 12 — the only way to distinguish
    /// `MM/DD` from `DD/MM` without an explicit format declaration. Returns
    /// `nil` (ambiguous) if no value in the column disambiguates.
    static func disambiguateDateOrder(_ rawValues: [String]) -> DateOrder? {
        for value in rawValues {
            let parts = value.split(separator: "/").compactMap { Int($0) }
            guard parts.count == 3 else { continue }
            let (first, second) = (parts[0], parts[1])
            if first > 12 { return .dayMonth }
            if second > 12 { return .monthDay }
        }
        // No disambiguating evidence anywhere in the column. Every value
        // has both components <= 12 (or the column is all single-digit
        // days) — genuinely ambiguous, not a case to guess on.
        return nil
    }

    static func parseDate(_ raw: String, order: DateOrder) -> AccountingDate? {
        let parts = raw.split(separator: "/").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let (a, b, year) = (parts[0], parts[1], parts[2])
        let (month, day) = order == .monthDay ? (a, b) : (b, a)
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        let fullYear = year < 100 ? 2000 + year : year
        return AccountingDate(year: fullYear, month: month, day: day)
    }

    /// Handles a leading `$`, thousands separators, parenthesized negatives
    /// (`(486.20)` — a common bank-export convention for debits), and a
    /// leading `-`.
    static func parseAmount(_ raw: String) -> Money? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        var negative = false
        if s.hasPrefix("(") && s.hasSuffix(")") {
            negative = true
            s = String(s.dropFirst().dropLast())
        }
        s = s.replacingOccurrences(of: "$", with: "")
        s = s.replacingOccurrences(of: ",", with: "")
        if s.hasPrefix("-") {
            negative = true
            s = String(s.dropFirst())
        }
        guard let decimal = Decimal(string: s), decimal >= 0 else { return nil }
        let minorUnits = NSDecimalNumber(decimal: decimal * 100).int64Value
        return Money(minorUnits: negative ? -minorUnits : minorUnits, currency: .usd)
    }
}
