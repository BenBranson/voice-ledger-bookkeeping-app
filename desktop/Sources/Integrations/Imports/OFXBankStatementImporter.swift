import Foundation
import Core

/// docs/phase-0/09_INGESTION_PIPELINE.md §9.3/§9.8, Tier 1 for OFX/QFX:
/// normalizes `OFXParser`'s raw transactions into `LedgerTransaction` — the
/// same shape `BankStatementCSVImporter` and the QBO API path both produce
/// (§9.8's contract). Simpler than the CSV importer: no column mapping is
/// needed at all (OFX tags are self-describing), and OFX's `YYYYMMDD` date
/// format has no US-vs-international ambiguity to disambiguate.
public enum OFXBankStatementImporter {
    public struct Result: Sendable {
        public let transactions: [LedgerTransaction]
        public let defects: [NormalizationDefect]
    }

    /// - Parameters:
    ///   - ofxText: raw file contents.
    ///   - realmID, documentID, importedAt: provenance fields.
    ///   - statementAccountID: see `BankStatementCSVImporter`'s parameter
    ///     of the same name — the QBO account this statement is FOR, never
    ///     inferred from the file.
    public static func `import`(
        ofxText: String,
        realmID: RealmID,
        documentID: ImportedDocumentID,
        importedAt: Date,
        statementAccountID: String? = nil
    ) -> Result {
        let rawTransactions = OFXParser.parseTransactions(ofxText)
        guard !rawTransactions.isEmpty else {
            return Result(transactions: [], defects: [.emptyFile])
        }

        var transactions: [LedgerTransaction] = []
        var defects: [NormalizationDefect] = []

        for (index, raw) in rawTransactions.enumerated() {
            guard let date = parseOFXDate(raw.datePosted) else {
                defects.append(.unparsableDate(row: index, column: "DTPOSTED", value: raw.datePosted))
                continue
            }
            guard let amount = parseOFXAmount(raw.amount) else {
                defects.append(.unparsableAmount(row: index, column: "TRNAMT", value: raw.amount))
                continue
            }

            // FITID is OFX's own stable transaction identity — preferred
            // over a row index so reimporting the same statement (even a
            // re-downloaded file with different surrounding whitespace)
            // still upserts onto the same LedgerTransaction.id rather than
            // creating a duplicate.
            let id = raw.fitID.map { "\(documentID.rawValue)-\($0)" } ?? "\(documentID.rawValue)-row\(index)"
            let description = raw.name ?? raw.memo

            transactions.append(LedgerTransaction(
                id: id,
                entityKind: .importedBankStatementLine,
                vendorName: description,
                txnDate: date,
                totalAmount: amount,
                paymentAccountID: statementAccountID,
                docNumber: nil,
                isVoided: false,
                memo: raw.memo,
                provenance: .importedFile(documentID: documentID.rawValue, importedAt: importedAt, extractionMethod: .deterministicParse, coverage: .partial(reason: "cross-foot validation (§9.5) is not implemented in this importer"))
            ))
        }

        return Result(transactions: transactions, defects: defects)
    }

    /// `YYYYMMDD`, optionally followed by a time/timezone suffix
    /// (`YYYYMMDDHHMMSS[.XXX[:TZ]]`) per the OFX spec — only the date
    /// portion matters here (`LedgerTransaction.txnDate` has no time
    /// component, matching QBO's own `TxnDate`).
    static func parseOFXDate(_ raw: String) -> AccountingDate? {
        guard raw.count >= 8 else { return nil }
        let digits = raw.prefix(8)
        guard digits.allSatisfy(\.isNumber),
              let year = Int(digits.prefix(4)),
              let month = Int(digits.dropFirst(4).prefix(2)),
              let day = Int(digits.dropFirst(6).prefix(2)) else { return nil }
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        return AccountingDate(year: year, month: month, day: day)
    }

    /// OFX's own sign convention: negative for money out, positive for
    /// money in — no parenthesized-negative or `$`-stripping heuristics
    /// needed the way the CSV importer requires (self-describing, not a
    /// human-formatted export).
    static func parseOFXAmount(_ raw: String) -> Money? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard let decimal = Decimal(string: trimmed) else { return nil }
        let minorUnits = NSDecimalNumber(decimal: decimal * 100).int64Value
        return Money(minorUnits: minorUnits, currency: .usd)
    }
}
