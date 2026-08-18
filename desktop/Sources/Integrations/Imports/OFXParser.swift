import Foundation

/// docs/phase-0/09_INGESTION_PIPELINE.md §9.3, Tier 1: "OFX/QFX are
/// structured and largely self-describing: account, date, amount, type,
/// FITID. Highest-fidelity source available for bank data."
///
/// Targets OFX 1.x's SGML-style format, which most banks still export
/// (rather than OFX 2.x's true XML) — tags frequently have **no closing
/// tag** on leaf elements (`<TRNAMT>-486.20` with the newline as the only
/// terminator, not `</TRNAMT>`). A strict XML parser rejects that outright.
/// This parser is deliberately line-oriented and tolerant of a trailing
/// close tag being present OR absent, rather than assuming either.
public enum OFXParser {
    public struct RawTransaction: Sendable, Equatable {
        /// OFX's own stable transaction identifier — used as the produced
        /// `LedgerTransaction.id` when present, since it's a better
        /// identity than the CSV importer's synthesized `doc-rowN` (a
        /// reimport of the same statement naturally dedupes on this,
        /// without needing byte-identical file content).
        public let fitID: String?
        /// `YYYYMMDD`, OFX's own date format — unambiguous, unlike a CSV's
        /// `MM/DD` vs `DD/MM` (§9.3's `ambiguousDateFormat` doesn't apply
        /// to OFX at all).
        public let datePosted: String
        /// Signed decimal string — OFX's own convention: negative for
        /// money out, positive for money in.
        public let amount: String
        public let name: String?
        public let memo: String?
        public let transactionType: String?
    }

    /// Extracts every `<STMTTRN>...</STMTTRN>` block and the leaf fields
    /// (`DTPOSTED`, `TRNAMT`, `FITID`, `NAME`, `MEMO`, `TRNTYPE`) inside
    /// each. A block missing `DTPOSTED` or `TRNAMT` is skipped, not
    /// half-produced — those two are the only fields this importer treats
    /// as required.
    public static func parseTransactions(_ text: String) -> [RawTransaction] {
        extractBlocks(text, tag: "STMTTRN").compactMap { block in
            let fields = extractLeafFields(block)
            guard let datePosted = fields["DTPOSTED"], let amount = fields["TRNAMT"] else { return nil }
            return RawTransaction(
                fitID: fields["FITID"],
                datePosted: datePosted,
                amount: amount,
                name: fields["NAME"],
                memo: fields["MEMO"],
                transactionType: fields["TRNTYPE"]
            )
        }
    }

    public struct RawLedgerBalance: Sendable, Equatable {
        /// Signed decimal string, same convention as `RawTransaction.amount`.
        public let balanceAmount: String
        /// `YYYYMMDD[...]`, same format as `RawTransaction.datePosted`.
        public let asOfDate: String
    }

    /// Extracts the single `<LEDGERBAL>` block's `BALAMT`/`DTASOF`, when
    /// present. `nil` if the file has no `<LEDGERBAL>` at all (not every
    /// bank includes one) — this is extraction only (`CLAUDE.md` rule 8):
    /// nothing in this parser compares this value against the imported
    /// transactions or computes a pass/fail from it. `nil` is a normal,
    /// silent outcome here, not a defect — the caller decides whether to
    /// show it.
    public static func parseLedgerBalance(_ text: String) -> RawLedgerBalance? {
        guard let block = extractBlocks(text, tag: "LEDGERBAL").first else { return nil }
        let fields = extractLeafFields(block)
        guard let balAmt = fields["BALAMT"], let dtAsOf = fields["DTASOF"] else { return nil }
        return RawLedgerBalance(balanceAmount: balAmt, asOfDate: dtAsOf)
    }

    static func extractBlocks(_ text: String, tag: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: "<\(tag)>(.*?)</\(tag)>",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        return matches.compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            return nsText.substring(with: match.range(at: 1))
        }
    }

    /// One line per leaf field, `<TAG>value` — a trailing `</TAG>` on the
    /// same line (if present) is stripped as part of the value rather than
    /// assumed absent or required.
    static func extractLeafFields(_ block: String) -> [String: String] {
        guard let regex = try? NSRegularExpression(pattern: #"^<([A-Za-z0-9.]+)>(.*)$"#) else { return [:] }
        var fields: [String: String] = [:]
        for rawLine in block.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let nsLine = line as NSString
            guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)),
                  match.numberOfRanges > 2 else { continue }
            let tag = nsLine.substring(with: match.range(at: 1)).uppercased()
            var value = nsLine.substring(with: match.range(at: 2))
            if let closeRange = value.range(of: "</", options: .backwards) {
                value = String(value[value.startIndex..<closeRange.lowerBound])
            }
            fields[tag] = value.trimmingCharacters(in: .whitespaces)
        }
        return fields
    }
}
